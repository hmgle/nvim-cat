---@class ColorschemeManager
---@field current_scheme string|nil
---@field highlight_cache table<string, HighlightAttrs>
---@field scheme_loaded boolean

---@class HighlightAttrs
---@field fg string|nil RGB hex color for foreground
---@field bg string|nil RGB hex color for background
---@field bold boolean|nil
---@field italic boolean|nil
---@field underline boolean|nil
---@field strikethrough boolean|nil
---@field reverse boolean|nil

local M = {}

-- Cache for highlight group attributes
M.highlight_cache = {}
M.current_scheme = nil
M.scheme_loaded = false

-- Default colorscheme fallbacks
M.DEFAULT_SCHEMES = { "default", "habamax", "blue" }

-- Common highlight group mappings
M.COMMON_GROUPS = {
  "Normal", "Comment", "Constant", "String", "Character", "Number", "Boolean", "Float",
  "Identifier", "Function", "Statement", "Conditional", "Repeat", "Label", "Operator",
  "Keyword", "Exception", "PreProc", "Include", "Define", "Macro", "PreCondit",
  "Type", "StorageClass", "Structure", "Typedef", "Special", "SpecialChar", "Tag",
  "Delimiter", "SpecialComment", "Debug", "Underlined", "Ignore", "Error", "Todo"
}

---Detect and return current colorscheme name
---@return string|nil Current colorscheme name
function M.get_current_colorscheme()
  if M.current_scheme then
    return M.current_scheme
  end
  
  -- Try to get from vim.g.colors_name
  local colors_name = vim.g.colors_name
  if colors_name and colors_name ~= "" then
    M.current_scheme = colors_name
    return colors_name
  end
  
  -- Fallback: try to detect from available colorschemes
  local available = vim.fn.getcompletion("", "color")
  for _, scheme in ipairs(M.DEFAULT_SCHEMES) do
    if vim.tbl_contains(available, scheme) then
      M.current_scheme = scheme
      return scheme
    end
  end
  
  return nil
end

---Force load a specific colorscheme
---@param scheme_name string Colorscheme name to load
---@return boolean success True if successfully loaded
function M.load_colorscheme(scheme_name)
  if not scheme_name or scheme_name == "" then
    return false
  end
  
  local success = pcall(vim.cmd, "colorscheme " .. scheme_name)
  if success then
    M.current_scheme = scheme_name
    M.scheme_loaded = true
    M.highlight_cache = {} -- Clear cache when scheme changes
    return true
  end
  
  return false
end

---Auto-load user's colorscheme or fallback to default
---@param preferred_scheme? string Optional preferred colorscheme
---@return boolean success True if a colorscheme was loaded
function M.ensure_colorscheme_loaded(preferred_scheme)
  if M.scheme_loaded then
    return true
  end
  
  -- Try preferred scheme first
  if preferred_scheme and M.load_colorscheme(preferred_scheme) then
    return true
  end
  
  -- Try current scheme
  local current = M.get_current_colorscheme()
  if current and M.load_colorscheme(current) then
    return true
  end
  
  -- Try default schemes
  for _, scheme in ipairs(M.DEFAULT_SCHEMES) do
    if M.load_colorscheme(scheme) then
      return true
    end
  end
  
  return false
end

---Get highlight attributes for a specific group
---@param group_name string Highlight group name
---@return HighlightAttrs|nil Highlight attributes or nil if not found
function M.get_highlight_attrs(group_name)
  if not group_name then
    return nil
  end
  
  -- Check cache first
  if M.highlight_cache[group_name] then
    return M.highlight_cache[group_name]
  end
  
  -- Ensure colorscheme is loaded
  if not M.scheme_loaded then
    M.ensure_colorscheme_loaded()
  end
  
  -- Try multiple API approaches due to known issues with nvim_get_hl_by_name
  local attrs = M._query_highlight_attrs(group_name)
  
  -- Cache the result (even if nil)
  M.highlight_cache[group_name] = attrs
  
  return attrs
end

---Internal function to query highlight attributes with fallbacks
---@param group_name string Highlight group name
---@return HighlightAttrs|nil Parsed highlight attributes
function M._query_highlight_attrs(group_name)
  local attrs = {}
  local success = false
  
  -- Method 1: Try nvim_get_hl_by_name with rgb=true
  local ok, hl = pcall(vim.api.nvim_get_hl_by_name, group_name, true)
  if ok and hl and (hl.foreground or hl.background) then
    attrs.fg = hl.foreground and M._num_to_hex(hl.foreground) or nil
    attrs.bg = hl.background and M._num_to_hex(hl.background) or nil
    attrs.bold = hl.bold and true or nil
    attrs.italic = hl.italic and true or nil
    attrs.underline = hl.underline and true or nil
    attrs.strikethrough = hl.strikethrough and true or nil
    attrs.reverse = hl.reverse and true or nil
    success = true
  end
  
  -- Method 2: Try newer nvim_get_hl (if available)
  if not success then
    local has_new_api, new_hl = pcall(vim.api.nvim_get_hl, 0, { name = group_name })
    if has_new_api and new_hl and (new_hl.fg or new_hl.bg) then
      attrs.fg = new_hl.fg and M._num_to_hex(new_hl.fg) or nil
      attrs.bg = new_hl.bg and M._num_to_hex(new_hl.bg) or nil
      attrs.bold = new_hl.bold and true or nil
      attrs.italic = new_hl.italic and true or nil
      attrs.underline = new_hl.underline and true or nil
      attrs.strikethrough = new_hl.strikethrough and true or nil
      attrs.reverse = new_hl.reverse and true or nil
      success = true
    end
  end
  
  -- Method 3: Try synIDattr approach (legacy fallback)
  if not success then
    local syn_id = vim.fn.synIDtrans(vim.fn.hlID(group_name))
    if syn_id and syn_id > 0 then
      local fg = vim.fn.synIDattr(syn_id, "fg#")
      local bg = vim.fn.synIDattr(syn_id, "bg#")
      
      if fg and fg ~= "" and fg ~= "-1" then
        attrs.fg = M._normalize_hex_color(fg)
      end
      if bg and bg ~= "" and bg ~= "-1" then
        attrs.bg = M._normalize_hex_color(bg)
      end
      
      attrs.bold = vim.fn.synIDattr(syn_id, "bold") == "1" and true or nil
      attrs.italic = vim.fn.synIDattr(syn_id, "italic") == "1" and true or nil
      attrs.underline = vim.fn.synIDattr(syn_id, "underline") == "1" and true or nil
      
      success = fg ~= nil or bg ~= nil
    end
  end
  
  return success and attrs or nil
end

---Convert numeric color to hex string
---@param num number Color as number
---@return string Hex color string (e.g., "#ff0000")
function M._num_to_hex(num)
  if type(num) ~= "number" then
    return "#000000"
  end
  return string.format("#%06x", num)
end

---Normalize hex color string
---@param color string Color string
---@return string Normalized hex color (e.g., "#ff0000")
function M._normalize_hex_color(color)
  if not color or color == "" then
    return "#000000"
  end
  
  -- Remove any whitespace
  color = color:gsub("%s+", "")
  
  -- Add # if missing
  if not color:match("^#") then
    color = "#" .. color
  end
  
  -- Convert to lowercase
  color = color:lower()
  
  -- Validate hex format
  if color:match("^#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") then
    return color
  end
  
  -- Fallback
  return "#000000"
end

---Parse hex color to RGB components
---@param hex_color string Hex color (e.g., "#ff0000")
---@return number, number, number RGB components (0-255)
function M.hex_to_rgb(hex_color)
  if not hex_color or not hex_color:match("^#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
    return 0, 0, 0
  end
  
  local hex = hex_color:sub(2) -- Remove #
  local r = tonumber(hex:sub(1, 2), 16) or 0
  local g = tonumber(hex:sub(3, 4), 16) or 0
  local b = tonumber(hex:sub(5, 6), 16) or 0
  
  return r, g, b
end

---Get all available colorschemes
---@return string[] List of available colorscheme names
function M.get_available_colorschemes()
  return vim.fn.getcompletion("", "color")
end

---Preload common highlight groups for better performance
function M.preload_common_groups()
  if not M.scheme_loaded then
    M.ensure_colorscheme_loaded()
  end
  
  for _, group in ipairs(M.COMMON_GROUPS) do
    M.get_highlight_attrs(group)
  end
end

---Clear highlight cache (useful when colorscheme changes)
function M.clear_cache()
  M.highlight_cache = {}
end

---Get diagnostic information about current colorscheme
---@return table Diagnostic information
function M.get_diagnostics()
  return {
    current_scheme = M.current_scheme,
    scheme_loaded = M.scheme_loaded,
    cache_size = vim.tbl_count(M.highlight_cache),
    available_schemes = #M.get_available_colorschemes(),
    vim_colors_name = vim.g.colors_name,
  }
end

return M