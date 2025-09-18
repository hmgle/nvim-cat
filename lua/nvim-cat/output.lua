local utils = require("nvim-cat.utils")

local M = {}

-- Global background state
M._global_bg_active = false
M._global_background_sequence = nil

---Start global background mode with Normal background color
---@return string ANSI sequence to start global background
function M.start_global_background()
  M._global_bg_active = true

  local colorscheme = require("nvim-cat.colorscheme")
  local normal_attrs = colorscheme.get_highlight_attrs("Normal")
  if not normal_attrs or not normal_attrs.bg then
    M._global_background_sequence = nil
    return ""
  end

  local r, g, b = M._parse_color_to_rgb(normal_attrs.bg)
  local esc = string.char(27)
  M._global_background_sequence = esc .. "[48;2;" .. r .. ";" .. g .. ";" .. b .. "m"
  return M._global_background_sequence
end

---End global background mode and reset colors
---@return string ANSI sequence to reset colors
function M.end_global_background()
  M._global_bg_active = false
  M._global_background_sequence = nil
  return string.char(27) .. "[0m"
end

---Apply background color to a line to fill the entire width
---@param line string Line content
---@param terminal_width? number Optional terminal width (unused)
---@return string Line wrapped with background clearing
function M.apply_line_background(line, terminal_width)
  if not M._global_bg_active then
    return line
  end

  local bg_seq = M._global_background_sequence
  if not bg_seq or bg_seq == "" then
    return line
  end

  line = line or ""

  -- Expand tab characters so the cleared background covers the visual span
  if line:find("\t", 1, true) then
    local tabstop = tonumber(vim.o.tabstop) or 8
    line = M._expand_tabs_preserving_ansi(line, tabstop)
  end

  local esc = string.char(27)

  -- Ensure we restore the background after any hard reset sequences so the
  -- terminal fill inherits the configured backdrop.
  line = line:gsub(esc .. "%[0m", esc .. "[0m" .. bg_seq)

  -- Clear to end-of-line while the Normal background is active so blank
  -- space inherits the colorscheme. We keep the signature for compatibility
  -- but no longer need the terminal width when using CSI K.
  local cleared_line = bg_seq .. line .. bg_seq .. esc .. "[K"

  return cleared_line .. esc .. "[0m"
end

---Expand tab characters into spaces while preserving ANSI escape sequences
---@param line string Line content possibly containing tabs
---@param tabstop number Tab width
---@return string Line with tabs expanded
function M._expand_tabs_preserving_ansi(line, tabstop)
  local result = {}
  local col = 0
  local i = 1
  local length = #line

  while i <= length do
    local byte = line:byte(i)
    if byte == 27 then
      local esc_seq = line:match("^\27%[[0-9;]*[A-Za-z]", i)
      if esc_seq then
        table.insert(result, esc_seq)
        i = i + #esc_seq
      else
        table.insert(result, string.char(byte))
        i = i + 1
      end
    else
      local char = string.char(byte)
      if char == "\t" then
        local spaces = tabstop - (col % tabstop)
        table.insert(result, string.rep(" ", spaces))
        col = col + spaces
        i = i + 1
      else
        local char_len = 1
        if byte >= 240 then
          char_len = 4
        elseif byte >= 224 then
          char_len = 3
        elseif byte >= 192 then
          char_len = 2
        end

        local grapheme = line:sub(i, i + char_len - 1)
        table.insert(result, grapheme)

        local ok, width = pcall(vim.fn.strdisplaywidth, grapheme)
        if not ok or width <= 0 then
          width = char_len
        end
        col = col + width
        i = i + char_len
      end
    end
  end

  return table.concat(result)
end

---Format lines with decorations (line numbers, etc.)
---@param lines string[] Content lines
---@param opts table Formatting options
---@return string[] Formatted lines
function M.format_lines(lines, opts)
  opts = opts or {}
  
  local show_line_numbers = opts.show_line_numbers or false
  local filepath = opts.filepath
  local filetype = opts.filetype
  
  local formatted = {}
  
  -- Add header if requested
  if opts.show_header and filepath then
    local header_text = M.format_header(filepath, filetype)
    if header_text and header_text ~= "" then
      local header_lines = vim.split(header_text, "\n", {
        plain = true,
        trimempty = false,
      })
      for _, header_line in ipairs(header_lines) do
        table.insert(formatted, header_line)
      end
    end
    table.insert(formatted, "") -- Empty line after header
  end
  
  -- Calculate line number width if needed
  local line_num_width = 0
  if show_line_numbers then
    line_num_width = string.len(tostring(#lines))
  end
  
  -- Format each line
  for i, line in ipairs(lines) do
    local formatted_line = line
    
    if show_line_numbers then
      local line_num = utils.pad_number(i, line_num_width)
      formatted_line = string.format("%s│ %s", line_num, line)
    end
    
    table.insert(formatted, formatted_line)
  end
  
  return formatted
end

---Format file header
---@param filepath string File path
---@param filetype? string Detected filetype
---@return string Formatted header
function M.format_header(filepath, filetype)
  local header = filepath
  if filetype then
    header = header .. " (" .. filetype .. ")"
  end
  
  -- Add decorative border
  local border_length = math.min(string.len(header) + 4, utils.get_terminal_width())
  local border = string.rep("─", border_length)
  
  return string.format("┌%s┐\n│ %s │\n└%s┘", border, header, border)
end

---Format text with highlight attributes using True Color ANSI sequences
---@param text string Text to format
---@param attrs table|string Highlight attributes or legacy color name
---@return string Formatted text with ANSI codes
function M.colorize(text, attrs)
  if not text or text == "" then
    return text
  end
  
  -- Handle legacy color name strings for backward compatibility
  if type(attrs) == "string" then
    return M._colorize_legacy(text, attrs)
  end
  
  -- Handle highlight attributes
  if not attrs or type(attrs) ~= "table" then
    return text
  end
  
  local esc = string.char(27)
  local codes = {}
  
  -- Add style codes
  if attrs.bold then
    table.insert(codes, "1")
  end
  if attrs.italic then
    table.insert(codes, "3")
  end
  if attrs.underline then
    table.insert(codes, "4")
  end
  if attrs.strikethrough then
    table.insert(codes, "9")
  end
  if attrs.reverse then
    table.insert(codes, "7")
  end
  
  -- Add foreground color (24-bit RGB)
  if attrs.fg then
    local r, g, b = M._parse_color_to_rgb(attrs.fg)
    table.insert(codes, string.format("38;2;%d;%d;%d", r, g, b))
  end
  
  -- Add background color (24-bit RGB)
  if attrs.bg then
    local r, g, b = M._parse_color_to_rgb(attrs.bg)
    table.insert(codes, string.format("48;2;%d;%d;%d", r, g, b))
  end
  
  -- If no codes, return text as-is
  if #codes == 0 then
    return text
  end
  
  -- Construct ANSI sequence
  local start_seq = esc .. "[" .. table.concat(codes, ";") .. "m"
  
  -- Smart reset: if global background is active, restore it after reset
  local reset_seq
  if M._global_bg_active then
    local colorscheme = require("nvim-cat.colorscheme")
    local normal_attrs = colorscheme.get_highlight_attrs("Normal")
    if normal_attrs and normal_attrs.bg then
      local r, g, b = M._parse_color_to_rgb(normal_attrs.bg)
      reset_seq = esc .. "[0m" .. esc .. "[48;2;" .. r .. ";" .. g .. ";" .. b .. "m"
    else
      reset_seq = esc .. "[0m"
    end
  else
    reset_seq = esc .. "[0m"
  end
  
  return start_seq .. text .. reset_seq
end

---Parse color string to RGB components
---@param color string Color in hex format (#rrggbb) or color name
---@return number, number, number RGB components (0-255)
function M._parse_color_to_rgb(color)
  if not color then
    return 0, 0, 0
  end
  
  -- Handle hex colors
  if color:match("^#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
    local colorscheme = require("nvim-cat.colorscheme")
    return colorscheme.hex_to_rgb(color)
  end
  
  -- Fallback for named colors (convert to approximate RGB)
  local named_colors = {
    black = {0, 0, 0},
    red = {255, 0, 0},
    green = {0, 255, 0},
    yellow = {255, 255, 0},
    blue = {0, 0, 255},
    magenta = {255, 0, 255},
    cyan = {0, 255, 255},
    white = {255, 255, 255},
    bright_black = {128, 128, 128},
    bright_red = {255, 128, 128},
    bright_green = {128, 255, 128},
    bright_yellow = {255, 255, 128},
    bright_blue = {128, 128, 255},
    bright_magenta = {255, 128, 255},
    bright_cyan = {128, 255, 255},
    bright_white = {255, 255, 255},
  }
  
  local rgb = named_colors[color:lower()]
  if rgb then
    return rgb[1], rgb[2], rgb[3]
  end
  
  return 0, 0, 0 -- Default to black
end

---Legacy colorize function for backward compatibility
---@param text string Text to format
---@param color_name string Color name
---@return string Formatted text
function M._colorize_legacy(text, color_name)
  local esc = string.char(27)
  local colors = {
    -- Basic colors
    black = esc .. "[30m",
    red = esc .. "[31m", 
    green = esc .. "[32m",
    yellow = esc .. "[33m",
    blue = esc .. "[34m",
    magenta = esc .. "[35m",
    cyan = esc .. "[36m",
    white = esc .. "[37m",
    
    -- Bright colors
    bright_black = esc .. "[90m",
    bright_red = esc .. "[91m",
    bright_green = esc .. "[92m",
    bright_yellow = esc .. "[93m",
    bright_blue = esc .. "[94m",
    bright_magenta = esc .. "[95m",
    bright_cyan = esc .. "[96m",
    bright_white = esc .. "[97m",
    
    -- Styles
    bold = esc .. "[1m",
    dim = esc .. "[2m",
    italic = esc .. "[3m",
    underline = esc .. "[4m",
    strikethrough = esc .. "[9m",
    
    -- Reset
    reset = esc .. "[0m",
  }
  
  local color_code = colors[color_name] or ""
  local reset_code = colors.reset
  
  return color_code .. text .. reset_code
end

---Format syntax highlighting token using actual Neovim highlight group
---@param text string Token text
---@param highlight_group string Neovim highlight group
---@return string Formatted token
function M.format_token(text, highlight_group)
  if not text or text == "" then
    return text
  end
  
  if not highlight_group or highlight_group == "" then
    return text
  end
  
  -- Get actual highlight attributes from colorscheme
  local colorscheme = require("nvim-cat.colorscheme")
  local attrs = colorscheme.get_highlight_attrs(highlight_group)
  
  if attrs then
    return M.colorize(text, attrs)
  else
    -- Fallback to legacy color mapping for unknown groups
    local fallback_map = {
      Comment = "bright_black",
      String = "green", 
      Number = "red",
      Function = "blue",
      Keyword = "magenta",
      Type = "yellow",
      Error = "bright_red",
    }
    
    local fallback_color = fallback_map[highlight_group]
    if fallback_color then
      return M.colorize(text, fallback_color)
    end
  end
  
  return text
end

---Check if terminal supports colors
---@return boolean Whether colors are supported
function M.supports_color()
  local term = os.getenv("TERM") or ""
  local colorterm = os.getenv("COLORTERM") or ""
  
  -- Check for NO_COLOR environment variable (standard way to disable colors)
  if os.getenv("NO_COLOR") then
    return false
  end
  
  -- Explicitly disable colors for certain terminals
  if term == "dumb" or term == "" then
    return false
  end
  
  -- For now, skip TTY detection as it's causing issues
  -- TODO: Implement proper TTY detection for piped output
  
  -- Check for COLORTERM environment variable
  if colorterm ~= "" then
    return true
  end
  
  local color_terms = {
    "xterm",
    "xterm-256color", 
    "screen",
    "screen-256color",
    "tmux",
    "tmux-256color",
    "rxvt",
    "konsole", 
    "gnome",
    "alacritty",
    "kitty",
    "wezterm",
    "iterm",
  }
  
  for _, color_term in ipairs(color_terms) do
    if term:find(color_term, 1, true) then
      return true
    end
  end
  
  return false
end

---Strip ANSI color codes from text
---@param text string Text with ANSI codes
---@return string Text without ANSI codes
function M.strip_ansi(text)
  -- Pattern to match ANSI escape sequences
  local esc = string.char(27)
  local ansi_pattern = esc .. "%[[0-9;]*m"
  return text:gsub(ansi_pattern, "")
end

---Get text width without ANSI codes
---@param text string Text (possibly with ANSI codes)
---@return number Visual width
function M.display_width(text)
  return string.len(M.strip_ansi(text))
end

---Truncate text to fit terminal width
---@param text string Text to truncate
---@param max_width? number Maximum width (default: terminal width)
---@return string Truncated text
function M.truncate(text, max_width)
  max_width = max_width or utils.get_terminal_width()
  
  local display_width = M.display_width(text)
  if display_width <= max_width then
    return text
  end
  
  -- Truncate and add ellipsis
  local stripped = M.strip_ansi(text)
  local truncated = stripped:sub(1, max_width - 3) .. "..."
  
  return truncated
end

---Create a table-like output for multiple columns
---@param rows table[] Array of rows, each row is an array of columns
---@param headers? string[] Optional column headers
---@return string[] Formatted table lines
function M.format_table(rows, headers)
  if #rows == 0 then
    return {}
  end
  
  -- Calculate column widths
  local num_cols = #rows[1]
  local col_widths = {}
  
  for i = 1, num_cols do
    col_widths[i] = 0
  end
  
  -- Check headers
  if headers then
    for i, header in ipairs(headers) do
      col_widths[i] = math.max(col_widths[i], M.display_width(header))
    end
  end
  
  -- Check all rows
  for _, row in ipairs(rows) do
    for i, cell in ipairs(row) do
      if cell then
        col_widths[i] = math.max(col_widths[i], M.display_width(tostring(cell)))
      end
    end
  end
  
  local formatted = {}
  
  -- Add headers if provided
  if headers then
    local header_row = ""
    for i, header in ipairs(headers) do
      if i > 1 then
        header_row = header_row .. " │ "
      end
      header_row = header_row .. string.format("%-" .. col_widths[i] .. "s", header)
    end
    table.insert(formatted, header_row)
    
    -- Add separator
    local separator = ""
    for i = 1, num_cols do
      if i > 1 then
        separator = separator .. "─┼─"
      end
      separator = separator .. string.rep("─", col_widths[i])
    end
    table.insert(formatted, separator)
  end
  
  -- Add data rows
  for _, row in ipairs(rows) do
    local row_str = ""
    for i, cell in ipairs(row) do
      if i > 1 then
        row_str = row_str .. " │ "
      end
      local cell_str = tostring(cell or "")
      row_str = row_str .. string.format("%-" .. col_widths[i] .. "s", cell_str)
    end
    table.insert(formatted, row_str)
  end
  
  return formatted
end

return M
