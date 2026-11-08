# TBKDX Character Image Converter

A Windows PowerShell utility for preparing character artwork for **The BerserK DeX (TBKDX)**.

The converter takes source images from three input categories and automatically creates the standardized TBKDX image set for each matched character:

- **Spawn Art** → `720 × 720`
- **Card Art** → `600 × 900`
- **Icon Art** → `128 × 128`
- **Credits** → `Credits.txt`

The current script version is **Character Image Converter v2.1.0**.

---

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7+
- **ImageMagick 7**
- The `magick` command available in the system `PATH`

ImageMagick can be downloaded from:

https://imagemagick.org/download/

After installation, verify that PowerShell can find it:

```powershell
magick -version
```

If `magick` is not recognized, close and reopen PowerShell after installing ImageMagick.

---

## Repository structure

```text
TBKDX-Character-Image-Converter/
├── convert.ps1
├── README.md
├── .gitignore
│
├── input/
│   ├── Spawn/
│   │   └── PUT_SPAWN_IMAGES_HERE.txt
│   ├── artCard/
│   │   └── PUT_ARTCARD_IMAGES_HERE.txt
│   └── Icon/
│       └── PUT_ICON_IMAGES_HERE.txt
│
└── output/
    └── GENERATED_FILES_APPEAR_HERE.txt
```

The repository is intentionally configured so that real input artwork and generated output files are not tracked by Git.

---

## Supported source formats

The converter recognizes:

```text
.png
.jpg
.jpeg
.webp
.bmp
.tif
.tiff
```

Files are read directly from the three category folders. Subfolders inside those category folders are not scanned.

---

## Quick start

### 1. Install ImageMagick 7

Install ImageMagick and make sure the `magick` command works from PowerShell.

### 2. Place the source images

Put the corresponding files inside:

```text
input/Spawn/
input/artCard/
input/Icon/
```

A character does not need to have all three sources. Missing categories are skipped.

### 3. Run the converter

Open PowerShell in the repository folder and run:

```powershell
.\convert.ps1 -CleanOutput
```

`-CleanOutput` clears earlier generated subfolders under `output/` before converting. Original source artwork in `input/` is never deleted. Without this switch, existing output folders are retained.

Untagged images are skipped by default. To restore the old positional fallback, use:

```powershell
.\convert.ps1 -IncludeLegacy
```

If PowerShell blocks local scripts, you can run:

```powershell
powershell -ExecutionPolicy Bypass -File .\convert.ps1
```

### 4. Read the generated output

For a matched character such as `Berserk`, the result is:

```text
output/
└── Berserk/
    ├── spawn.png
    ├── art.png
    ├── icon.png
    └── Credits.txt
```

The converter also creates:

```text
output/_conversion_report.txt
```

This report lists processed files, generated images and ImageMagick errors.

---

# File matching

The converter first tries to match files using metadata embedded in the filename.

The main key is:

```text
ArtistCode + CharacterName
```

Files with valid metadata are grouped together even when their alphabetical positions differ between the three input folders.

---

## Recommended filename format (v2.1.0)

The preferred format puts the **character name first** and the artist's Discord numeric ID last:

```text
CharacterName_ArtistID.png
```

Examples:

```text
Berserk_123456789012345678.png
Dragon_Soul_123456789012345678.png
_Nyssa_123456789012345678_.png
```

Character names can contain underscores, and leading/trailing underscores are ignored. In this standard format, ArtistID must be **15 to 25 digits** to prevent camera file numbers, years or stray test files from being mistaken for artist credits.

The categories match by the same complete CharacterName and ArtistID:

```text
input/Spawn/Hades_123456789012345678.png
input/artCard/Hades_123456789012345678.png
input/Icon/Hades_123456789012345678.png
```

They produce a single `output/Hades/` folder. Individual categories may be missing.

### Writer markers

Append standalone `wdy` and/or `hrdw` to a filename to credit the artist as a description writer:

```text
Berserk_123456789012345678_wdy.png
Berserk_123456789012345678_hrdw.png
Dragon_Soul_123456789012345678_wdy_hrdw.png
```

A marker on **any** matching Spawn, artCard or Icon source applies to the whole character group. When absent, the respective writer credit is `Fallback`.

### Short IDs and custom codes

Short numeric or alphanumeric artist codes use an explicit double underscore separator:

```text
Berserk__123.png
Dragon_Soul__A123.png
```

A filename like `AAA_IMG_9642.png` is **not** interpreted as an artist-tagged character.

### Backward compatibility

Previously supported artist-first filenames are still valid:

```text
123456789012345678_Berserk.png
123456789012345678_Dragon_Soul.png
123456789012345678__Dragon_Soul.png
123__Berserk__final.png
raw__123__Dragon_Soul__final.png
```

The full name is preserved even when it contains underscores. Explicit `ArtistABC__Berserk.png` is also supported for an alphabetic artist code.

Known leading prefixes for explicit filenames include `raw`, `src`, `source`, `draft`, `final`, `render`, `sketch`, `preview`, `icon`, `spawn`, `art`, `artcard`, `card`, `image`, `img`, `drawing` and `export`. Supported explicit trailing export suffixes include `final`, `draft`, `render`, `preview` and `export`.

Ambiguous or untagged names are not guessed.

---

# Credit metadata

The converter can automatically create a `Credits.txt` file for correctly tagged character groups.

Example:

```text
Artist: 123456789012345678
Writer Description: 123456789012345678
High Rarity Description Writer: 123456789012345678
```

Credit metadata comes from the source filenames. The converter does **not** invent an artist or writer identity.

---

## Artist

The `Artist` field contains the detected `ArtistCode`.

Example source:

```text
123456789012345678_Berserk.png
```

Generated credit:

```text
Artist: 123456789012345678
```

---

## Writer Description: `wdy`

Add the standalone token:

```text
wdy
```

to at least one source filename in the matched character set when the same Artist/User ID should also be credited for the standard description writing.

Example:

```text
123456789012345678_Berserk_wdy.png
```

Result:

```text
Writer Description: 123456789012345678
```

If no source file in that character set contains `wdy`:

```text
Writer Description: Fallback
```

---

## High Rarity Description Writer: `hrdw`

Add the standalone token:

```text
hrdw
```

when the same Artist/User ID should also be credited for high-rarity descriptions.

Example:

```text
123456789012345678_Berserk_hrdw.png
```

Result:

```text
High Rarity Description Writer: 123456789012345678
```

If the token is absent:

```text
High Rarity Description Writer: Fallback
```

---

## Using both writer markers

Both markers can be used together:

```text
123456789012345678_Berserk_wdy_hrdw.png
```

or:

```text
123456789012345678__Dragon_Soul__wdy_hrdw.png
```

Result:

```text
Artist: 123456789012345678
Writer Description: 123456789012345678
High Rarity Description Writer: 123456789012345678
```

The markers are evaluated across the **entire matched character set**.

For example:

```text
input/Spawn/123456789012345678_Berserk_wdy.png
input/artCard/123456789012345678_Berserk.png
input/Icon/123456789012345678_Berserk.png
```

still generates:

```text
Writer Description: 123456789012345678
```

because at least one source belonging to the set contains the `wdy` marker.

---

## What `Fallback` means

`Fallback` is a reserved functional value.

It is **not** an artist name, user, writer or account.

It tells the TBKDX content system that no explicit custom writer was declared for that field and that the project's default/fallback handling should be used.

---

# Untagged files and legacy matching

Starting in v2.1.0, untagged files are **skipped by default**. Accidental test files such as `ù.png`, `Metre.png` and `AAA_IMG_9642.png` will not create extra characters or get matched solely by alphabetical position.

The converter reports skipped files in `output/_conversion_report.txt`.

For legacy collections that intentionally use alphabetical positions:

```powershell
.\convert.ps1 -IncludeLegacy
```

This restores fallback folders `Character_1`, `Character_2`, etc., and never invents credits. Tagged and untagged source files are never mixed.

To include a name-only file like `Metre.png` in normal mode, rename it with a valid ArtistID (or an explicit short code) first.

---

# Duplicate handling

If multiple files share the same ArtistCode and CharacterName in one or more categories, the converter processes additional rounds instead of silently discarding them.

Example output:

```text
Berserk/
Berserk_2/
Berserk_3/
```

If the same character name is associated with different ArtistCodes, the artist code is added to the output folder name to avoid collisions.

Example:

```text
Berserk_123/
Berserk_456/
```

---

# Image processing behavior

## Spawn Art

Target:

```text
720 × 720 PNG
```

If the source is already a transparent `720 × 720` PNG and does not require white-background cleanup, it is copied byte-for-byte.

Otherwise, the image is processed as RGBA PNG.

Images with different dimensions are proportionally resized to fill the square and then centered on the `720 × 720` output.

---

## Icon Art

Target:

```text
128 × 128 PNG
```

If the source is already a transparent `128 × 128` PNG and no cleanup is needed, it is copied byte-for-byte.

Otherwise, the same proportional fill and centered square behavior is used at `128 × 128`.

---

## Card Art

Final canvas:

```text
600 × 900 PNG
```

A source that is already exactly `600 × 900` is preserved without resizing or repositioning.

Other source dimensions use the TBKDX card-art adaptation pipeline:

1. Auto-orient the source.
2. Proportionally fill a `450 × 300` area without stretching.
3. Center-crop the result to `444 × 296`.
4. Create a transparent `600 × 900` canvas.
5. Place the adapted art at:

```text
X = 78
Y = 82
```

This produces the standard TBKDX card-art placement.

---

# Transparency and white-background removal

By default:

```powershell
$RemoveWhiteBorderBackground = $true
$WhiteBackgroundFuzz = '6%'
```

The converter can remove a solid white or near-white background connected to the **outer corners** of the source image.

It checks corner color and alpha before flood filling.

This is intentionally different from globally deleting every white pixel.

The goal is to preserve enclosed white or cream details inside the character while removing an external white background.

### Important limitation

If a white or near-white region belonging to the character physically touches the external white background, automatic flood-fill removal cannot know where the background ends and the artwork begins.

That connected region may also become transparent.

For sensitive artwork, disable automatic removal:

```powershell
$RemoveWhiteBorderBackground = $false
```

Existing transparency is preserved.

---

# Output safety

By default, old output folders are retained. When processing a known character folder, the converter only replaces its known generated outputs:

```text
spawn.png
art.png
icon.png
Credits.txt
```

A stale folder such as `Character_1`, `one-hades`, or `ù` may therefore remain visible after a new conversion, even if the current parser did not create it.

To remove old generated subfolders before a run:

```powershell
.\convert.ps1 -CleanOutput
```

**Warning:** `-CleanOutput` recursively deletes **every subfolder of `output/`**, including any custom folders placed there, and replaces `_conversion_report.txt`. It never deletes anything from `input/`. Back up custom contents under `output/` first.

To also restore legacy positional matching:

```powershell
.\convert.ps1 -CleanOutput -IncludeLegacy
```

---

# Technical credits and third-party software

## TBKDX

This utility is designed for **The BerserK DeX (TBKDX)** project and its character asset workflow.

Project maintenance and repository organization:

**Berserk 308 / TBKDX**

Artwork ownership and authorship remain with their respective creators. The generated `Credits.txt` files exist specifically to preserve the attribution metadata declared through the source filenames.

---

## ImageMagick

Image processing is performed through **ImageMagick 7** and its `magick` command-line interface.

ImageMagick is developed by **ImageMagick Studio LLC**.

Official website:

https://imagemagick.org/

Official license:

https://imagemagick.org/license/

This repository does not claim ownership of ImageMagick.

The default repository setup contains only the PowerShell converter and calls an independently installed copy of ImageMagick. It does not need to bundle ImageMagick binaries.

If a future distribution includes or redistributes ImageMagick itself, that distribution must follow the ImageMagick License requirements, including the applicable license copy and attribution notices.

---

# Git behavior

The included `.gitignore` intentionally excludes:

- real images inside `input/`
- all generated character assets inside `output/`
- temporary files
- common operating-system metadata

The small instruction files inside the empty input/output folders are explicitly kept in Git.

This keeps the repository lightweight and avoids accidentally publishing source artwork.

---

# Suggested workflow

```text
1. Clone or download the repository.
2. Install ImageMagick 7.
3. Place the source artwork in input/Spawn, input/artCard and input/Icon.
4. Use the preferred `CharacterName_ArtistID.png` filenames.
5. Run `convert.ps1 -CleanOutput` if you want to remove stale output folders.
6. Check `output/_conversion_report.txt` for generated and skipped files.
7. Review the generated images and Credits.txt files.
8. Move the final approved assets into the appropriate TBKDX project location.
```

---

# Notes

- The converter never intentionally modifies the original source files.
- Input folders are not recursive.
- Missing categories are allowed.
- Untagged files are skipped by default; use `-IncludeLegacy` to enable alphabetical fallback.
- Tagged and untagged files are never mixed during matching.
- Output folder names are sanitized for Windows compatibility.
- Windows reserved names are automatically protected.
- Very long generated folder names are shortened for filesystem safety.

