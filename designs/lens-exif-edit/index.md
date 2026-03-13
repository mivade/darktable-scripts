# Lens EXIF editor script

## Goal

Create a Lua script for darktable to edit lens EXIF information.

## Context

I have Fuji and Nikon mirrorless cameras. I often like to use non-CPU, manual focus lenses. I want
to be able to update the EXIF data in my raw files to reflect the lens that was actually used after
the fact.

## Requirements

Minimum darktable version to support: 5.4.1.

### GUI

The script should create a panel in the lighttable view. It should have options for:

- Lens model name (e.g., Nikkor 50mm f/1.4 AI)
- Focal length (e.g., 50mm)
- Maximum aperture (e.g., f/1.4)

I should be able to select images in the lighttable and press "Apply" in this new panel to modify
the lens EXIF data.

### File editing

The script should

- Modify the EXIF data of the raw file in place
  - I will manage backups myself
- Create/update sidecar files as needed
- Force updates to darktable's database as necessary once the EXIF data are updated
