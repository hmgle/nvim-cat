local output = require("nvim-cat.output")
local treesitter = require("nvim-cat.treesitter")
local syntax = require("nvim-cat.syntax")

local M = {}

---Apply syntax highlighting to lines using the best available engine
---@param lines string[] File lines
---@param filetype string Detected filetype
---@return string[] Highlighted lines
function M.apply_syntax(lines, filetype)
  -- Check if we can use colors
  if not output.supports_color() then
    return lines
  end
  
  -- Try Treesitter first (most advanced)
  if treesitter.has_parser(filetype) then
    local highlighted = treesitter.apply_treesitter_highlighting(lines, filetype)
    if highlighted and #highlighted > 0 then
      return highlighted
    end
  end
  
  -- Fallback to traditional Vim syntax highlighting
  local highlighted = syntax.apply_vim_syntax_highlighting(lines, filetype)
  if highlighted and #highlighted > 0 then
    return highlighted
  end
  
  -- Last resort: simple pattern-based highlighting
  return M.apply_simple_highlighting(lines, filetype)
end

---Get diagnostic information about highlighting engines
---@return table Diagnostic information
function M.get_diagnostics()
  return {
    treesitter = treesitter.get_diagnostics(),
    syntax = syntax.get_diagnostics(),
    color_support = output.supports_color(),
  }
end

---Clear all caches for highlighting engines
function M.clear_cache()
  treesitter.clear_cache()
  syntax.clear_cache()
end

---Apply simple pattern-based syntax highlighting
---@param lines string[] File lines
---@param filetype string Filetype
---@return string[] Highlighted lines
function M.apply_simple_highlighting(lines, filetype)
  local highlighted = {}
  
  for _, line in ipairs(lines) do
    table.insert(highlighted, M.highlight_line_simple(line, filetype))
  end
  
  return highlighted
end

---Apply simple highlighting to a single line
---@param line string Line to highlight
---@param filetype string Filetype
---@return string Highlighted line
function M.highlight_line_simple(line, filetype)
  -- Get patterns for the filetype
  local patterns = M.get_highlight_patterns(filetype)
  
  -- Create a list of highlights to apply
  local highlights = {}
  
  -- Optimized pattern matching with early termination
  for _, pattern_info in ipairs(patterns) do
    local pattern = pattern_info.pattern
    local color = pattern_info.color
    local priority = pattern_info.priority or 1
    
    local pos = 1
    local line_len = #line
    
    while pos <= line_len do
      local start_pos, end_pos = line:find(pattern, pos)
      if not start_pos then
        break
      end
      
      -- Store the highlight info (avoid string operations in inner loop)
      table.insert(highlights, {
        start_pos = start_pos,
        end_pos = end_pos,
        color = color,
        priority = priority
      })
      
      pos = end_pos + 1
    end
  end
  
  -- Sort highlights by position, then by priority
  table.sort(highlights, function(a, b)
    if a.start_pos == b.start_pos then
      return (a.priority or 1) > (b.priority or 1)
    end
    return a.start_pos < b.start_pos
  end)
  
  -- Optimized highlight application with minimal string operations
  local result_parts = {}
  local last_pos = 1
  
  -- Pre-build color mapping for efficiency
  local color_to_group_map = {
    bright_black = "Comment",
    green = "String", 
    red = "Number",
    blue = "Function",
    magenta = "Keyword",
    yellow = "Type",
    cyan = "Identifier",
  }
  
  for _, hl in ipairs(highlights) do
    -- Skip overlapping highlights
    if hl.start_pos >= last_pos then
      -- Add text before highlight
      if hl.start_pos > last_pos then
        table.insert(result_parts, line:sub(last_pos, hl.start_pos - 1))
      end
      
      local highlight_group = color_to_group_map[hl.color] or hl.color
      local text = line:sub(hl.start_pos, hl.end_pos)
      
      -- Use format_token for consistent highlighting with colorscheme
      table.insert(result_parts, output.format_token(text, highlight_group))
      
      last_pos = hl.end_pos + 1
    end
  end
  
  -- Add remaining text
  if last_pos <= #line then
    table.insert(result_parts, line:sub(last_pos))
  end
  
  return table.concat(result_parts)
end

---Get highlight patterns for a filetype
---@param filetype string Filetype
---@return table[] Array of pattern info tables
function M.get_highlight_patterns(filetype)
  local common_patterns = {
    -- Comments (highest priority to avoid conflicts)
    { pattern = "//.*$", color = "bright_black", capture = 0, priority = 10 },
    { pattern = "#.*$", color = "bright_black", capture = 0, priority = 10 },
    
    -- Strings (high priority)
    { pattern = '"[^"]*"', color = "green", capture = 0, priority = 9 },
    { pattern = "'[^']*'", color = "green", capture = 0, priority = 9 },
    
    -- Numbers (medium priority)
    { pattern = "%f[%d]%d+%.?%d*%f[%D]", color = "red", capture = 0, priority = 5 },
  }
  
  local filetype_patterns = {
    lua = {
      -- Lua comments (highest priority)
      { pattern = "%-%-.*$", color = "bright_black", capture = 0, priority = 10 },
      
      -- Lua keywords (high priority)
      { pattern = "%f[%a]local%f[%A]", color = "magenta", capture = 0, priority = 8 },
      { pattern = "%f[%a]function%f[%A]", color = "blue", capture = 0, priority = 8 },
      { pattern = "%f[%a]return%f[%A]", color = "magenta", capture = 0, priority = 8 },
      { pattern = "%f[%a]if%f[%A]", color = "magenta", capture = 0, priority = 8 },
      { pattern = "%f[%a]then%f[%A]", color = "magenta", capture = 0, priority = 8 },
      { pattern = "%f[%a]else%f[%A]", color = "magenta", capture = 0, priority = 8 },
      { pattern = "%f[%a]elseif%f[%A]", color = "magenta", capture = 0, priority = 8 },
      { pattern = "%f[%a]end%f[%A]", color = "magenta", capture = 0, priority = 8 },
      { pattern = "%f[%a]for%f[%A]", color = "magenta", capture = 0, priority = 8 },
      { pattern = "%f[%a]while%f[%A]", color = "magenta", capture = 0, priority = 8 },
      { pattern = "%f[%a]do%f[%A]", color = "magenta", capture = 0, priority = 8 },
      { pattern = "%f[%a]repeat%f[%A]", color = "magenta", capture = 0, priority = 8 },
      { pattern = "%f[%a]until%f[%A]", color = "magenta", capture = 0, priority = 8 },
      
      -- Lua operators (medium priority)
      { pattern = "%f[%a]and%f[%A]", color = "yellow", capture = 0, priority = 7 },
      { pattern = "%f[%a]or%f[%A]", color = "yellow", capture = 0, priority = 7 },
      { pattern = "%f[%a]not%f[%A]", color = "yellow", capture = 0, priority = 7 },
      
      -- Lua constants (medium priority)
      { pattern = "%f[%a]true%f[%A]", color = "red", capture = 0, priority = 6 },
      { pattern = "%f[%a]false%f[%A]", color = "red", capture = 0, priority = 6 },
      { pattern = "%f[%a]nil%f[%A]", color = "red", capture = 0, priority = 6 },
    },
    
    javascript = {
      -- JavaScript keywords
      { pattern = "%f[%a]function%f[%A]", color = "blue", capture = 0 },
      { pattern = "%f[%a]var%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]let%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]const%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]if%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]else%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]for%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]while%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]return%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]true%f[%A]", color = "red", capture = 0 },
      { pattern = "%f[%a]false%f[%A]", color = "red", capture = 0 },
      { pattern = "%f[%a]null%f[%A]", color = "red", capture = 0 },
      { pattern = "%f[%a]undefined%f[%A]", color = "red", capture = 0 },
    },
    
    python = {
      -- Python keywords
      { pattern = "%f[%a]def%f[%A]", color = "blue", capture = 0 },
      { pattern = "%f[%a]class%f[%A]", color = "yellow", capture = 0 },
      { pattern = "%f[%a]import%f[%A]", color = "cyan", capture = 0 },
      { pattern = "%f[%a]from%f[%A]", color = "cyan", capture = 0 },
      { pattern = "%f[%a]if%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]elif%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]else%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]for%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]while%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]return%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]True%f[%A]", color = "red", capture = 0 },
      { pattern = "%f[%a]False%f[%A]", color = "red", capture = 0 },
      { pattern = "%f[%a]None%f[%A]", color = "red", capture = 0 },
    },
    
    shell = {
      -- Shell keywords
      { pattern = "%f[%a]if%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]then%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]else%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]elif%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]fi%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]for%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]while%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]do%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]done%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]case%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]esac%f[%A]", color = "magenta", capture = 0 },
      { pattern = "%f[%a]function%f[%A]", color = "blue", capture = 0 },
      { pattern = "$[%w_]+", color = "cyan", capture = 0 },
      { pattern = "${[^}]+}", color = "cyan", capture = 0 },
    },
  }
  
  -- Optimized pattern combination without deep copy
  local patterns = {}
  
  -- Add filetype-specific patterns first (higher priority)
  local ft_patterns = filetype_patterns[filetype] or filetype_patterns.shell
  for _, pattern in ipairs(ft_patterns) do
    table.insert(patterns, pattern)
  end
  
  -- Add common patterns
  for _, pattern in ipairs(common_patterns) do
    table.insert(patterns, pattern)
  end
  
  return patterns
end


---Apply theme-specific color mapping
---@param color string Base color name
---@param theme? string Theme name
---@return string Adjusted color name
function M.apply_theme_color(color, theme)
  if not theme or theme == "auto" then
    return color
  end
  
  local theme_mappings = {
    dark = {
      -- Keep default colors for dark theme
    },
    light = {
      -- Adjust colors for light theme
      bright_black = "black",
      black = "bright_black",
    }
  }
  
  local mapping = theme_mappings[theme]
  if mapping and mapping[color] then
    return mapping[color]
  end
  
  return color
end

return M