## Overview

Implement a darktable Lua script that adds a lighttable panel for editing lens-related EXIF fields
on selected images, writes updated EXIF data back to the raw files (and sidecars as needed), and
ensures darktable's database is refreshed to reflect the changes. The script must support darktable
version 5.4.1 and later.

## Assumptions

- darktable 5.4.1 exposes a Lua API for:
  - Creating lighttable UI modules / widgets (panel, text inputs, buttons).
  - Enumerating and operating on the current selection of images.
  - Forcing metadata reload / database refresh from updated files or sidecars.
- Direct EXIF writes to raw files will be done via:
  - An external metadata tool (`exiftool`) invoked via `os.execute`, with paths
    resolved from darktable's image objects.
- Sidecars are managed in the standard darktable way (XMP files alongside raw files) and can be
  regenerated or updated via the API and/or external tool.

## High-level Architecture

1. **Module registration**
   - Register a new Lua script as a lighttable module (e.g., `lens_exif_editor`).
   - Ensure minimum darktable version check (5.4.1) at initialization.

2. **UI layer (lighttable panel)**
   - Create a panel in lighttable view containing:
     - Text input: `Lens model` (e.g., "Nikkor 50mm f/1.4 AI").
     - Numeric input: `Focal length` (e.g., 50).
     - Numeric input or text: `Maximum aperture` (e.g., 1.4 or "f/1.4").
     - `Apply` button.
   - Also include:
     - A `Preview from first selected image` helper that reads current EXIF lens info to
       pre-populate fields.
     - Status message / log area to show success/failure per image.

3. **Core operations**
   - On `Apply` click:
     - Collect current values from the three UI inputs.
     - Resolve the current lighttable selection to a list of image objects (files).
     - For each image:
       - Construct a metadata update command / API call that:
         - Sets lens model.
         - Sets focal length.
         - Sets maximum aperture.
       - Apply changes to:
         - The raw file in place.
         - The associated sidecar (if present or required).
     - After updates, trigger darktable to reload metadata / refresh database for those images.

4. **Error handling and UX**
   - Handle cases where:
     - No images are selected (disable `Apply` and show a short hint in the panel about needing a selection).
     - External metadata tool (`exiftool`) is missing:
       - Show a clear error message in the panel explaining that `exiftool` is required.
       - Disable the `Apply` button while the dependency is not available.
     - External metadata invocation fails for a specific file (e.g., non-zero exit code).
     - Individual files fail to update (continue processing the rest; log failures).
   - Provide minimal but clear feedback to the user in the panel.

## Detailed Implementation Steps

1. **Project layout**
   - Create a new Lua script file (e.g., `lens_exif_edit.lua`) at the top level of this repository.
     The user can then install or reference it from the appropriate darktable scripts directory.
   - Add any necessary registration to the project’s script loader or manifest (if the repo uses
     one).

2. **Initialize module**
   - In `lens_exif_edit.lua`:
     - Require the darktable Lua API (e.g., `local dt = require "darktable"`).
     - Implement a version check using the API to ensure darktable ≥ 5.4.1; if not, show an error
       and abort module registration.

3. **Build lighttable UI**
   - Use darktable’s UI constructs to define:
     - `lens_model_entry`: text input.
     - `focal_length_entry`: numeric or text field; validate as positive number.
     - `max_aperture_entry`: numeric or text field; validate as positive number.
     - `apply_button`: button labeled "Apply".
   - Register the UI elements as a lighttable module:
     - Place them in a vertical box or similar container.
     - Provide a descriptive label and tooltip for the module.

4. **Selection handling**
   - Implement a function `get_selected_images()` using the Lua API to fetch currently selected
     images in lighttable.
   - If no images are selected when `Apply` is pressed:
     - Show a non-blocking warning (e.g., via `dt.print` or within the panel).
     - Abort processing.

5. **EXIF update backend**
   - Use `exiftool` as the backend for metadata editing:
     - On module initialization:
       - Probe for `exiftool` in `PATH` and store its availability.
       - If not found, display a clear error in the panel and disable `Apply`.
     - Build commands for each image path that:
       - Set lens model tag (e.g., `-LensModel="..."`).
       - Set focal length (e.g., `-FocalLength="50 mm"`).
       - Set max aperture (e.g., `-MaxApertureValue=1.4` or equivalent).
       - Ensure commands modify files in place (e.g., use appropriate flags to avoid copies where
         possible).
     - Only touch metadata fields relevant to this script (lens model, focal length, maximum
       aperture); never overwrite or reset unrelated tags.
     - If darktable uses XMP sidecars:
       - Ensure `exiftool` updates the corresponding XMP fields without clobbering unrelated
         metadata, or
       - Regenerate or sync sidecars in a way that preserves other metadata fields.

6. **Database refresh**
   - After successfully updating metadata for an image (raw and/or sidecar):
     - Use the Lua API to trigger metadata re-read for that image, or
     - If only a coarse-grained API is available, trigger a general metadata rescan and ensure it
       runs after updates complete.
   - Confirm that:
     - Lens model, focal length, and max aperture fields update in the lighttable and darkroom views
       after refresh.

7. **User feedback and logging**
   - For each `Apply` operation:
     - Print a short summary: number of images processed, number succeeded, number failed.
     - For failures:
       - Capture exit codes and key parts of error messages from external tools (if used).
       - Show a concise error line per failed file.
   - Provide a small log buffer in the panel that shows recent operations, including per-image
     success/failure messages.

8. **Performance and safety considerations**
   - Batch external tool invocations where feasible:
     - If supported by the tool, pass multiple file paths in a single command to speed up
       processing.
   - Avoid blocking darktable’s UI for a long time:
     - If the Lua API provides asynchronous job helpers, wrap long-running EXIF updates in such jobs
       and report progress.
   - Do not create backups automatically, per requirement; clearly document this in the script
     header and tooltip.

9. **Testing plan**
   - Prepare a test set:
     - A few raw files from Fuji and Nikon bodies.
     - Some with existing EXIF lens data, some without.
   - Test scenarios:
     - Apply changes with a single selected image.
     - Apply changes with multiple images of mixed existing lens metadata.
     - Change lens information multiple times on the same set of images.
     - Verify that darktable shows updated lens, focal length, and max aperture after refresh.
     - Confirm sidecar behavior matches expectations (created/updated when needed).

10. **Documentation**
   - Add header comments in `lens_exif_edit.lua` with:
     - Description of functionality.
     - Minimum darktable version requirement (5.4.1).
     - Optional external tool requirement (name and version suggestions).
   - Update the project’s main `README` or scripts index, if applicable, with:
     - Brief usage instructions (where to find the panel, how to use it).
     - Any caveats about metadata editing and backups.
