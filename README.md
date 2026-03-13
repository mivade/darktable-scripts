# darktable-scripts

Scripts that I use to automate photo processing in darktable.

## lens_exif_edit.lua

Lens EXIF editor: change lens model, focal length, and maximum aperture in the EXIF of selected raw files from the lighttable.

**Requirements:** darktable ≥ 5.4.1, [exiftool](https://exiftool.org/) installed and on your PATH.

**Install:** Copy `lens_exif_edit.lua` into darktable’s Lua scripts folder (e.g. `$CONFIG/darktable/lua`), then enable it in **Scripts → Script manager**.

**Usage:**

1. Open the **lighttable** view.
2. Open the **Lens EXIF** panel (left sidebar).
3. Select one or more images.
4. Optionally click **Preview from first selected** to fill the fields from the first image’s EXIF.
5. Edit **Lens model**, **Focal length (mm)**, and **Max aperture (f-number)** as needed.
6. Click **Apply** to write the values to the selected images’ files (and their XMP sidecars if present). darktable’s database is updated and thumbnails refreshed.

**Caveats:**

- Files are modified **in place**. Create backups yourself if needed.
- Only the three lens-related tags are written; other metadata is left unchanged.
- If **Apply** is disabled, check that exiftool is installed and that at least one image is selected.
