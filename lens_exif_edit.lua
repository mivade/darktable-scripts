--[[
  Lens EXIF editor - darktable Lua script

  Adds a lighttable panel to edit lens EXIF (lens model, focal length, maximum
  aperture) on selected images. Writes changes to the raw files and sidecars
  via exiftool and refreshes darktable's database.

  Requirements:
  - darktable >= 5.4.1
  - exiftool installed and on PATH (script will disable Apply if not found)

  The script modifies files in place. Manage backups yourself.
]]

local dt = require "darktable"

-- Minimum darktable version: 5.4.1 (check if API available)
if dt.configuration and dt.configuration.check_version then
  dt.configuration.check_version("lens_exif_edit", {5, 4, 1})
end

-- Probe for exiftool
local function exiftool_available()
  local f = io.popen("exiftool -ver 2>/dev/null")
  if not f then return false end
  local ver = f:read("*l")
  f:close()
  return ver and ver ~= ""
end

local exiftool_ok = exiftool_available()

-- Convert f-number to EXIF MaxApertureValue (APEX)
local function fnumber_to_apex(fnumber)
  if not fnumber or fnumber <= 0 then return nil end
  return 2 * math.log(fnumber) / math.log(2)
end

-- Normalize path: ensure one slash between dir and file
local function join_path(dir, file)
  if not dir or not file then return nil end
  dir = dir:match("^(.*)/$") and dir:match("^(.*)/$") or dir
  return dir .. "/" .. file
end

-- Build exiftool arguments for lens-only updates (no overwriting of other tags)
local function build_exiftool_args(lens_model, focal_length_mm, aperture_apex)
  local args = { "-overwrite_original" }
  if lens_model and lens_model ~= "" then
    table.insert(args, "-LensModel=" .. lens_model)
  end
  if focal_length_mm and focal_length_mm > 0 then
    table.insert(args, "-FocalLength=" .. tostring(focal_length_mm))
  end
  if aperture_apex and aperture_apex > 0 then
    table.insert(args, "-MaxApertureValue=" .. tostring(aperture_apex))
  end
  return args
end

-- Escape a single argument for shell (simple: wrap in single quotes, escape quotes inside)
local function shell_escape(s)
  if not s then return "" end
  return "'" .. tostring(s):gsub("'", "'\"'\"'") .. "'"
end

-- Run exiftool on a list of file paths; returns success, stderr
local function run_exiftool(args, paths)
  if #paths == 0 then return true, "" end
  local cmd = "exiftool"
  for _, a in ipairs(args) do
    cmd = cmd .. " " .. shell_escape(a)
  end
  for _, p in ipairs(paths) do
    cmd = cmd .. " " .. shell_escape(p)
  end
  local f = io.popen(cmd .. " 2>&1")
  if not f then return false, "failed to run exiftool" end
  local out = f:read("*a")
  f:close()
  -- exiftool returns 0 on success; we don't have exit code from popen, so check for "Error"
  if out and (out:match("Error") or out:match("error")) then
    return false, out
  end
  return true, out or ""
end

-- Log buffer (last N lines)
local LOG_MAX = 10
local log_lines = {}

local function log_append(msg)
  table.insert(log_lines, msg)
  while #log_lines > LOG_MAX do
    table.remove(log_lines, 1)
  end
end

local function log_text()
  return table.concat(log_lines, "\n")
end

-- UI state
local lens_model_entry
local focal_length_entry
local max_aperture_entry
local apply_button
local status_label
local preview_button

local function update_apply_sensitive()
  local images = dt.gui.action_images
  local has_selection = images and #images > 0
  if apply_button then
    apply_button.sensitive = exiftool_ok and has_selection
  end
  if preview_button then
    preview_button.sensitive = has_selection
  end
  if status_label then
    if not exiftool_ok then
      status_label.label = "exiftool not found. Install it and restart the script."
    elseif not has_selection then
      status_label.label = "Select one or more images to enable Apply."
    else
      status_label.label = #images .. " image(s) selected."
    end
  end
end

local function preview_from_first()
  local images = dt.gui.action_images
  if not images or #images == 0 then
    log_append("No image selected for preview.")
    if status_label then status_label.label = log_text() end
    return
  end
  local img = images[1]
  if lens_model_entry then lens_model_entry.text = img.exif_lens or "" end
  if focal_length_entry then
    focal_length_entry.text = (img.exif_focal_length and img.exif_focal_length > 0)
        and tostring(img.exif_focal_length) or ""
  end
  if max_aperture_entry then
    max_aperture_entry.text = (img.exif_aperture and img.exif_aperture > 0)
        and tostring(img.exif_aperture) or ""
  end
  log_append("Preview from: " .. (img.filename or "?"))
  if status_label then status_label.label = log_text() end
end

local function apply_clicked()
  local images = dt.gui.action_images
  if not images or #images == 0 then
    log_append("No images selected.")
    if status_label then status_label.label = log_text() end
    return
  end

  local lens_model = lens_model_entry and lens_model_entry.text or ""
  local focal_s = focal_length_entry and focal_length_entry.text or ""
  local aperture_s = max_aperture_entry and max_aperture_entry.text or ""

  local focal_length_mm = tonumber(focal_s)
  local aperture_f = tonumber(aperture_s)
  if focal_s ~= "" and (not focal_length_mm or focal_length_mm <= 0) then
    log_append("Invalid focal length (positive number expected).")
    if status_label then status_label.label = log_text() end
    return
  end
  if aperture_s ~= "" and (not aperture_f or aperture_f <= 0) then
    log_append("Invalid maximum aperture (positive number expected, e.g. 1.4).")
    if status_label then status_label.label = log_text() end
    return
  end

  local aperture_apex = aperture_f and fnumber_to_apex(aperture_f)
  local args = build_exiftool_args(lens_model, focal_length_mm, aperture_apex)
  if #args <= 1 then
    log_append("Set at least one of: lens model, focal length, or max aperture.")
    if status_label then status_label.label = log_text() end
    return
  end

  local paths = {}
  for _, img in ipairs(images) do
    local raw_path = join_path(img.path, img.filename)
    if raw_path then
      table.insert(paths, raw_path)
    end
    if img.sidecar and img.sidecar ~= "" then
      local sidecar_path = join_path(img.path, img.sidecar)
      if sidecar_path then
        table.insert(paths, sidecar_path)
      end
    end
  end

  local ok, err = run_exiftool(args, paths)
  local succeeded = 0
  local failed = 0
  if ok then
    succeeded = #images
    for _, img in ipairs(images) do
      if lens_model ~= "" then img.exif_lens = lens_model end
      if focal_length_mm and focal_length_mm > 0 then
        img.exif_focal_length = focal_length_mm
      end
      if aperture_f and aperture_f > 0 then
        img.exif_aperture = aperture_f
      end
      pcall(function() img:drop_cache() end)
    end
    log_append("Applied to " .. tostring(succeeded) .. " image(s).")
  else
    failed = #images
    log_append("exiftool failed: " .. (err:match("[^\n]+") or err))
  end

  if status_label then status_label.label = log_text() end
end

-- Build panel
lens_model_entry = dt.new_widget("entry") {
  tooltip = "Lens model name (e.g. Nikkor 50mm f/1.4 AI)",
  text = "",
}

focal_length_entry = dt.new_widget("entry") {
  tooltip = "Focal length in mm (e.g. 50)",
  text = "",
}

max_aperture_entry = dt.new_widget("entry") {
  tooltip = "Maximum aperture as f-number (e.g. 1.4 for f/1.4)",
  text = "",
}

preview_button = dt.new_widget("button") {
  label = "Preview from first selected",
  clicked_callback = preview_from_first,
}

apply_button = dt.new_widget("button") {
  label = "Apply",
  clicked_callback = apply_clicked,
}

status_label = dt.new_widget("label") {
  label = "Select images and optionally run Preview.",
  selectable = true,
}

local panel = dt.new_widget("box") {
  orientation = "vertical",
  dt.new_widget("label") { label = "Lens model", halign = "start" },
  lens_model_entry,
  dt.new_widget("label") { label = "Focal length (mm)", halign = "start" },
  focal_length_entry,
  dt.new_widget("label") { label = "Max aperture (f-number)", halign = "start" },
  max_aperture_entry,
  preview_button,
  apply_button,
  dt.new_widget("separator") { orientation = "horizontal" },
  status_label,
}

dt.register_lib(
  "lens_exif_editor",
  "Lens EXIF",
  true,  -- expandable
  false, -- resetable
  {
    [dt.gui.views.lighttable] = { "DT_UI_CONTAINER_PANEL_LEFT_CENTER", 20 },
  },
  panel
)

-- Initial state and selection changes
dt.register_event(
  "lens_exif_edit_selection",
  "selection-changed",
  function()
    update_apply_sensitive()
  end
)

update_apply_sensitive()
