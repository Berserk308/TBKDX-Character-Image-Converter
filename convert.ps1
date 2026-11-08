# Character Image Converter v2.1.0 | Windows PowerShell 5.1 / PowerShell 7+
# Requires ImageMagick 7 (magick).
# Smart matching by CharacterName_ArtistID (preferred), or legacy ID_CharacterName.
# Untagged source files are skipped by default; -IncludeLegacy restores positional matching.
# -CleanOutput explicitly removes prior output folders without touching source artwork.
# Output PNGs keep transparency; solid near-white corner-connected backgrounds
# are removed when enabled. Pre-sized transparent PNGs are copied byte-for-byte.
# Skips unnecessary scaling: Spawn 720x720, Icon 128x128, and ONLY Art
# 600x900. Other Art sizes use proportional fill + center crop to the mask.
# Adds Writer Description in Credits: if any source filename in the set contains
# the token 'wdy', Writer Description = Artist/User ID, otherwise = Fallback.
# Likewise 'hrdw' marks High Rarity Description Writer = Artist/User ID;
# otherwise High Rarity Description Writer = Fallback.
# Optionally removes white/near-white background connected to image CORNERS only,
# preserving enclosed white/cream details inside the character.
# If a white region in the character touches the external background, automatic
# removal cannot distinguish it and may remove that connected region.
param(
    [switch]$IncludeLegacy,
    [switch]$CleanOutput
)

$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$inputRoot = Join-Path $root 'input'
$outputRoot = Join-Path $root 'output'
$extensions = @('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.tif', '.tiff')
$categories = @('Spawn', 'artCard', 'Icon')

# You can adjust these settings for your source drawings.
# $true: remove a white background connected to the corners of the source.
# $false: preserve the source exactly, retaining any transparency already there.
$RemoveWhiteBorderBackground = $true
$WhiteBackgroundFuzz = '6%'

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    Write-Host 'ERRORE: comando magick non trovato. Installa ImageMagick, poi riapri PowerShell.' -ForegroundColor Red
    exit 1
}

function Get-Images([string]$folder) {
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    Get-ChildItem -LiteralPath $folder -File | Where-Object {
        $extensions -contains $_.Extension.ToLowerInvariant()
    } | Sort-Object -Property Name
}

function Test-Code([string]$value) {
    # For the explicit __ syntax, purely alphabetic codes are permitted.
    return ($value -cmatch '^[A-Za-z0-9]+$')
}

function Get-FileMetadata([string]$baseName) {
    # Preferred: CharacterName_ArtistID (15-25 digit Discord ID), including names
    # with underscores and accidental leading/trailing underscores.
    # Also supports CharacterName__ShortCode (explicit delimiter) and existing
    # ArtistCode_CharacterName or ArtistCode__CharacterName formats.
    $candidate = $baseName.Trim().Trim('_')
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }

    # Remove optional standalone writing markers at the end. Credit detection
    # still inspects the original filenames in Test-HasWdy/Test-HasHrdw.
    while ($candidate -match '(?i)_{1,2}(?:wdy|hrdw)$') {
        $candidate = $candidate -replace '(?i)_{1,2}(?:wdy|hrdw)$', ''
        $candidate = $candidate.TrimEnd('_')
    }

    # Backwards-compatible explicit export suffix and leading source prefix.
    $candidate = $candidate -replace '(?i)__(?:final|draft|render|preview|export)$', ''
    $candidate = $candidate -replace '^(?i:raw|src|source|draft|final|render|sketch|preview|icon|spawn|art|artcard|card|image|img|drawing|export)__', ''
    $candidate = $candidate.Trim('_')
    if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }

    # New order. Do not mistake arbitrary short numbers (e.g. IMG_9642)
    # for Discord IDs: short codes must use an explicit double underscore.
    if ($candidate -match '^(?<character>.+?)_+(?<code>[0-9]{15,25})$') {
        $character = $Matches['character'].Trim('_').Trim()
        if (-not [string]::IsNullOrWhiteSpace($character)) {
            return [pscustomobject]@{ Code = $Matches['code']; Character = $character }
        }
    }
    if ($candidate -match '^(?<character>.+)__(?<code>[A-Za-z0-9]*[0-9][A-Za-z0-9]*)$') {
        $character = $Matches['character'].Trim('_').Trim()
        if (-not [string]::IsNullOrWhiteSpace($character)) {
            return [pscustomobject]@{ Code = $Matches['code']; Character = $character }
        }
    }

    # Old order, including 123__Dragon_Soul, raw__123__Dragon_Soul,
    # 123_Dragon_Soul, and short/alphanumeric codes with digits.
    if ($candidate -match '^(?<code>[A-Za-z0-9]*[0-9][A-Za-z0-9]*)_+(?<character>.+)$') {
        $character = $Matches['character'].Trim('_').Trim()
        if (-not [string]::IsNullOrWhiteSpace($character)) {
            return [pscustomobject]@{ Code = $Matches['code']; Character = $character }
        }
    }
    # Purely alphabetical artist codes are allowed only in explicit CODE__NAME.
    if ($candidate -match '^(?<code>[A-Za-z]+)__(?<character>.+)$') {
        $character = $Matches['character'].Trim('_').Trim()
        if (-not [string]::IsNullOrWhiteSpace($character)) {
            return [pscustomobject]@{ Code = $Matches['code']; Character = $character }
        }
    }
    return $null
}

function Test-HasWdy($files) {
    foreach ($item in $files.Values) {
        if ($null -eq $item) { continue }
        $baseName = [string]$item.BaseName
        # Accept wdy as an isolated token or separated by underscores/double underscores/hyphens/spaces.
        if ($baseName -match '(?i)(^|[_\-\s])wdy($|[_\-\s])' -or $baseName -imatch '(?i)__wdy(__|$)' -or $baseName -ieq 'wdy') {
            return $true
        }
    }
    return $false
}

function Test-HasHrdw($files) {
    foreach ($item in $files.Values) {
        if ($null -eq $item) { continue }
        $baseName = [string]$item.BaseName
        # hrdw must be a whole token, not part of a character name.
        # Accept ID_Character_hrdw, ID__Character__hrdw, and hyphen/space separators.
        if ($baseName -match '(?i)(^|[_\-\s])hrdw($|[_\-\s])') {
            return $true
        }
    }
    return $false
}

function Get-SafeFolderName([string]$text) {
    $safe = [regex]::Replace($text, '[\\/:*?"<>|\x00-\x1F]', '_')
    $safe = $safe.Trim().TrimEnd([char[]]@(' ', '.'))
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'UnknownCharacter' }
    if ($safe -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
        $safe = '_' + $safe
    }
    if ($safe.Length -gt 90) { $safe = $safe.Substring(0, 90).TrimEnd([char[]]@(' ', '.')) }
    return $safe
}

function Get-FreeName([string]$baseName) {
    $candidate = $baseName
    $suffix = 2
    while ($script:usedNames.ContainsKey($candidate)) {
        $candidate = '{0}_{1}' -f $baseName, $suffix
        $suffix++
    }
    $script:usedNames[$candidate] = $true
    return $candidate
}

function Invoke-Magick([string[]]$arguments, [string]$label) {
    & magick @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick ha restituito codice $LASTEXITCODE durante: $label"
    }
}

# Build a safe ImageMagick operation to clear ONLY a white background connected
# to the outer corners. Check color AND alpha before flood filling, otherwise
# a dark drawing touching a corner could accidentally be removed.
function Get-TransparencyArgs([string]$source) {
    $argsList = @('-auto-orient', '-alpha', 'on')
    if (-not $RemoveWhiteBorderBackground) { return $argsList }

    $corners = @('0,0', 'w-1,0', '0,h-1', 'w-1,h-1')
    $checks = @(
        foreach ($p in $corners) {
            '%[fx:(u.p{' + $p + '}.r>0.94 && u.p{' + $p + '}.g>0.94 && u.p{' + $p + '}.b>0.94 && u.p{' + $p + '}.a>0.95)?1:0]'
        }
    ) -join ','

    $sample = & magick $source '-auto-orient' '-format' ('%w,%h;' + $checks) 'info:'
    if ($LASTEXITCODE -ne 0) {
        throw "Impossibile controllare lo sfondo: $source"
    }
    $segments = [string]$sample -split ';'
    if ($segments.Count -ne 2) { throw "Risposta ImageMagick non valida: $sample" }
    $size = $segments[0] -split ','
    $width = [int]$size[0]
    $height = [int]$size[1]
    $cornerXY = @( '0,0', ('{0},0' -f ($width - 1)), ('0,{0}' -f ($height - 1)), ('{0},{1}' -f ($width - 1), ($height - 1)) )
    $found = $false
    $flags = $segments[1] -split ','
    for ($i = 0; $i -lt $corners.Count; $i++) {
        if ($i -lt $flags.Count -and $flags[$i].Trim() -eq '1') {
            if (-not $found) {
                $argsList += @('-fuzz', $WhiteBackgroundFuzz, '-fill', 'none')
                $found = $true
            }
            # The source is only modified in memory, never on disk.
            $argsList += @('-draw', ('color {0} floodfill' -f $cornerXY[$i]))
        }
    }
    return $argsList
}

# Read the oriented pixel dimensions, so an already-compliant image is not
# resampled. %[opaque] is False if there is at least one transparent pixel.
function Get-ImageInfo([string]$source) {
    $answer = & magick $source '-auto-orient' '-format' '%w,%h,%[opaque]' 'info:'
    if ($LASTEXITCODE -ne 0) { throw "Impossibile leggere le dimensioni: $source" }
    $parts = ([string]$answer).Trim() -split ','
    if ($parts.Count -ne 3) { throw "Dimensioni ImageMagick non valide: $answer" }
    return [pscustomobject]@{
        Width = [int]$parts[0]
        Height = [int]$parts[1]
        IsOpaque = ($parts[2].Trim() -ieq 'True')
    }
}

function Convert-Group([string]$folderName, $files, [string]$artistCode) {
    $folder = Join-Path $outputRoot $folderName
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    Write-Host "`n$folderName" -ForegroundColor Cyan
    $script:report.Add("[$folderName]") | Out-Null
    $hasWdy = Test-HasWdy $files
    $hasHrdw = Test-HasHrdw $files

    $jobs = @(
        @{ category = 'Spawn'; outFile = 'spawn.png'; kind = 'square720' },
        @{ category = 'artCard'; outFile = 'art.png'; kind = 'art' },
        @{ category = 'Icon'; outFile = 'icon.png'; kind = 'square128' }
    )

    foreach ($job in $jobs) {
        $out = Join-Path $folder $job.outFile
        # Remove ONLY this converter's known outputs from an earlier run of this folder.
        if (Test-Path -LiteralPath $out -PathType Leaf) {
            Remove-Item -LiteralPath $out -Force
        }
        $sourceFile = $files[$job.category]
        if ($null -eq $sourceFile) {
            Write-Host "  $($job.category): assente (saltato)"
            $script:report.Add("  $($job.category): assente") | Out-Null
            continue
        }

        $source = $sourceFile.FullName
        try {
            $imageInfo = Get-ImageInfo $source
            $width = $imageInfo.Width
            $height = $imageInfo.Height
            $transparencyArgs = @(Get-TransparencyArgs $source)
            $needsBackgroundRemoval = ($transparencyArgs -contains '-draw')
            $isReadyPNG = ($sourceFile.Extension -ieq '.png' -and
                           -not $imageInfo.IsOpaque -and
                           -not $needsBackgroundRemoval)
            $operation = 'RESIZE'

            switch ($job.kind) {
                'square720' {
                    if ($width -eq 720 -and $height -eq 720) {
                        if ($isReadyPNG) {
                            # Preserve source bytes (including its existing alpha and artwork).
                            Copy-Item -LiteralPath $source -Destination $out -Force
                            $operation = 'COPIA DIRETTA'
                        }
                        else {
                            # Geometry is already correct. Only convert to PNG or
                            # clean up a white external background; never rescale.
                            Invoke-Magick -arguments (@($source) + $transparencyArgs + @('-define', 'png:color-type=6', $out)) -label 'Spawn (no resize)'
                            $operation = 'NESSUN RESIZE'
                        }
                    }
                    else {
                        Invoke-Magick -arguments (@($source) + $transparencyArgs + @('-resize', '720x720^', '-background', 'none', '-gravity', 'center', '-extent', '720x720', '-alpha', 'on', '-define', 'png:color-type=6', $out)) -label 'Spawn'
                    }
                }
                'square128' {
                    if ($width -eq 128 -and $height -eq 128) {
                        if ($isReadyPNG) {
                            Copy-Item -LiteralPath $source -Destination $out -Force
                            $operation = 'COPIA DIRETTA'
                        }
                        else {
                            Invoke-Magick -arguments (@($source) + $transparencyArgs + @('-define', 'png:color-type=6', $out)) -label 'Icon (no resize)'
                            $operation = 'NESSUN RESIZE'
                        }
                    }
                    else {
                        Invoke-Magick -arguments (@($source) + $transparencyArgs + @('-resize', '128x128^', '-background', 'none', '-gravity', 'center', '-extent', '128x128', '-alpha', 'on', '-define', 'png:color-type=6', $out)) -label 'Icon'
                    }
                }
                'art' {
                    if ($width -eq 600 -and $height -eq 900) {
                        # A card already laid out on the full 600x900 canvas.
                        # Do not scale/crop/move anything inside it.
                        if ($isReadyPNG) {
                            Copy-Item -LiteralPath $source -Destination $out -Force
                            $operation = 'COPIA DIRETTA'
                        }
                        else {
                            Invoke-Magick -arguments (@($source) + $transparencyArgs + @('-define', 'png:color-type=6', $out)) -label 'Art canvas (no resize)'
                            $operation = 'NESSUN RESIZE'
                        }
                    }
                    else {
                        # All Art sources other than ready 600x900 canvases use the
                        # Proportional FILL: cover 450x300 without stretching,
                        # center-crop to 444x296, then position the result on
                        # a transparent 600x900 canvas at (78,82).
                        # This also handles square, portrait, and panoramic art.
                        # Sources already 600x900 are handled above unchanged.
                        $inner = @('(', $source) + $transparencyArgs
                        $inner += @('-resize', '450x300^', '-background', 'none',
                                    '-gravity', 'center', '-extent', '444x296', ')')
                        $operation = 'ADATTAMENTO + CANVAS'
                        # Always create a TRANSPARENT 600x900 canvas, position 78,82.
                        Invoke-Magick -arguments (@('-size', '600x900', 'xc:none') + $inner + @('-gravity', 'NorthWest', '-geometry', '+78+82', '-compose', 'over', '-composite', '-alpha', 'on', '-define', 'png:color-type=6', $out)) -label 'Art canvas'
                    }
                }
            }
            $script:createdImages++
            Write-Host "  $($job.category): OK ($operation) ($($sourceFile.Name))"
            $script:report.Add("  $($job.category): $($sourceFile.Name) => $($job.outFile) [$operation]") | Out-Null
        }
        catch {
            $script:errors++
            Write-Warning "  $($job.category): ERRORE su $source - $_"
            $script:report.Add("  $($job.category): ERRORE - $($sourceFile.Name) - $_") | Out-Null
            if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
        }
    }

    $creditsFile = Join-Path $folder 'Credits.txt'
    if (-not [string]::IsNullOrWhiteSpace($artistCode)) {
        $writerDescription = if ($hasWdy) { $artistCode } else { 'Fallback' }
        $highRarityWriter = if ($hasHrdw) { $artistCode } else { 'Fallback' }
        $creditLines = @(
            "Artist: $artistCode"
            "Writer Description: $writerDescription"
            "High Rarity Description Writer: $highRarityWriter"
        )
        Set-Content -LiteralPath $creditsFile -Value $creditLines -Encoding UTF8
        Write-Host "  Credits: Artist: $artistCode | Writer Description: $writerDescription | High Rarity Description Writer: $highRarityWriter"
        $script:report.Add("  Credits: Artist=$artistCode | WriterDescription=$writerDescription | HighRarityDescriptionWriter=$highRarityWriter") | Out-Null
    }
    else {
        # No valid metadata: don't invent an artist name or keep old credits.
        if (Test-Path -LiteralPath $creditsFile) { Remove-Item -LiteralPath $creditsFile -Force }
    }
    $script:report.Add('') | Out-Null
}

$taggedGroups = @{}
$untagged = @{}
$counts = @{}
foreach ($category in $categories) {
    $untagged[$category] = New-Object System.Collections.ArrayList
    $files = @(Get-Images (Join-Path $inputRoot $category))
    $counts[$category] = $files.Count
    foreach ($file in $files) {
        $metadata = Get-FileMetadata $file.BaseName
        if ($null -eq $metadata) {
            [void]$untagged[$category].Add($file)
            continue
        }
        $key = '{0}|{1}' -f $metadata.Code.ToLowerInvariant(), $metadata.Character.ToLowerInvariant()
        if (-not $taggedGroups.ContainsKey($key)) {
            $taggedGroups[$key] = @{
                Code = $metadata.Code
                Character = $metadata.Character
                Spawn = (New-Object System.Collections.ArrayList)
                artCard = (New-Object System.Collections.ArrayList)
                Icon = (New-Object System.Collections.ArrayList)
            }
        }
        [void]$taggedGroups[$key][$category].Add($file)
    }
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
if ($CleanOutput) {
    # Explicit opt-in: clear previously generated character folders, including
    # stale legacy folders from older versions. Never touch input artwork.
    Get-ChildItem -LiteralPath $outputRoot -Directory | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
    $oldReport = Join-Path $outputRoot '_conversion_report.txt'
    if (Test-Path -LiteralPath $oldReport -PathType Leaf) {
        Remove-Item -LiteralPath $oldReport -Force
    }
    Write-Host 'Output precedente ripulito (-CleanOutput).' -ForegroundColor Yellow
}
$usedNames = @{}
$report = New-Object 'System.Collections.Generic.List[string]'
$createdImages = 0
$errors = 0
$createdFolders = 0
$report.Add('CHARACTER IMAGE CONVERTER - REPORT') | Out-Null
$report.Add('Abbinamento: Nome_ArtistID (preferito), ID_Nome (legacy) e formati espliciti con __.') | Out-Null
$report.Add(("Legacy alfabetico: {0}; ripulitura output: {1}" -f $IncludeLegacy.IsPresent, $CleanOutput.IsPresent)) | Out-Null
$report.Add('') | Out-Null

Write-Host ("Spawn: {0} | artCard: {1} | Icon: {2}" -f $counts['Spawn'], $counts['artCard'], $counts['Icon'])
if (($counts['Spawn'] + $counts['artCard'] + $counts['Icon']) -eq 0) {
    Write-Host 'Nessuna immagine trovata nelle cartelle input.' -ForegroundColor Yellow
    exit 0
}

# Resolve duplicate character names from DIFFERENT artist codes.
# Normal names become output/Berserk. Conflicts become Berserk_A123 etc.
$nameCounts = @{}
foreach ($key in @($taggedGroups.Keys)) {
    $name = Get-SafeFolderName $taggedGroups[$key].Character
    if (-not $nameCounts.ContainsKey($name)) { $nameCounts[$name] = 0 }
    $nameCounts[$name]++
}

# Metadata groups: process every file. If multiple files in one category have
# the same key, create second/third rounds rather than silently discarding files.
foreach ($key in @($taggedGroups.Keys | Sort-Object)) {
    $group = $taggedGroups[$key]
    $name = Get-SafeFolderName $group.Character
    if ($nameCounts[$name] -gt 1) {
        $name = '{0}_{1}' -f $name, $group.Code
    }
    $cycles = [Math]::Max($group.Spawn.Count, [Math]::Max($group.artCard.Count, $group.Icon.Count))
    for ($i = 0; $i -lt $cycles; $i++) {
        $baseName = $name
        if ($i -gt 0) { $baseName = '{0}_{1}' -f $name, ($i + 1) }
        $folderName = Get-FreeName $baseName
        $selected = @{}
        foreach ($category in $categories) {
            $selected[$category] = $null
            if ($i -lt $group[$category].Count) {
                $selected[$category] = $group[$category][$i]
            }
        }
        Convert-Group -folderName $folderName -files $selected -artistCode $group.Code
        $createdFolders++
    }
}

# Untagged files are skipped by default, so stray tests like `u` or `Metre`
# cannot accidentally become a character. Old positional matching is opt-in.
$untaggedCount = 0
foreach ($category in $categories) {
    $untaggedCount += $untagged[$category].Count
}
if ($IncludeLegacy) {
    $maxFallback = [Math]::Max($untagged['Spawn'].Count, [Math]::Max($untagged['artCard'].Count, $untagged['Icon'].Count))
    for ($i = 0; $i -lt $maxFallback; $i++) {
        $num = $i + 1
        $folderName = Get-FreeName "Character_$num"
        $selected = @{}
        foreach ($category in $categories) {
            $selected[$category] = $null
            if ($i -lt $untagged[$category].Count) {
                $selected[$category] = $untagged[$category][$i]
            }
        }
        Convert-Group -folderName $folderName -files $selected -artistCode ''
        $createdFolders++
    }
}
elseif ($untaggedCount -gt 0) {
    Write-Host "Ignorati $untaggedCount file senza metadati validi. Usa -IncludeLegacy per il vecchio abbinamento." -ForegroundColor Yellow
    $report.Add('File ignorati (assenza di metadati):') | Out-Null
    foreach ($category in $categories) {
        foreach ($file in $untagged[$category]) {
            $report.Add("  $category`: $($file.Name)") | Out-Null
        }
    }
    $report.Add('') | Out-Null
}

$report.Add("Totale cartelle elaborate: $createdFolders") | Out-Null
$report.Add("Totale immagini generate: $createdImages") | Out-Null
$report.Add("File senza metadati validi: $untaggedCount") | Out-Null
$report.Add("Errori ImageMagick: $errors") | Out-Null
$reportPath = Join-Path $outputRoot '_conversion_report.txt'
Set-Content -LiteralPath $reportPath -Value $report -Encoding UTF8

Write-Host "`nCompletato: $createdFolders cartelle; $createdImages PNG generati; errori: $errors" -ForegroundColor Green
Write-Host "Dettagli: $reportPath"
Write-Host 'NOTA: per eliminare le vecchie cartelle output usa -CleanOutput; per il matching alfabetico usa -IncludeLegacy.'
if ($errors -gt 0) { exit 1 }
