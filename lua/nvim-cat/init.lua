---@class NvimCat
---@field config NvimCatConfig
local M = {}

local config = require("nvim-cat.config")
local utils = require("nvim-cat.utils")
local filedetect = require("nvim-cat.filedetect")
local colorscheme = require("nvim-cat.colorscheme")

---Setup nvim-cat with user configuration
---@param opts? NvimCatConfig User configuration options
function M.setup(opts)
  config.setup(opts)
  
  -- Initialize colorscheme management
  local cfg = config.get()
  local preferred_scheme = cfg.colorscheme or nil
  
  -- Ensure we have a colorscheme loaded in headless mode
  colorscheme.ensure_colorscheme_loaded(preferred_scheme)
  
  -- Preload common highlight groups for better performance
  colorscheme.preload_common_groups()
end

---Display file(s) with syntax highlighting
---@param pattern string File path or glob pattern
---@param opts? table Additional options for this call
function M.cat(pattern, opts)
  opts = opts or {}
  
  -- Optimized file pattern expansion
  local files = {}
  local stat = vim.loop.fs_stat(pattern)
  
  if stat then
    if stat.type == "file" then
      table.insert(files, pattern)
    elseif stat.type == "directory" then
      vim.notify("Cannot cat a directory: " .. pattern, vim.log.levels.ERROR)
      return
    end
  else
    -- Try glob expansion only if direct file doesn't exist
    local expanded = utils.expand_glob(pattern)
    if #expanded == 0 then
      vim.notify("No files found matching pattern: " .. pattern, vim.log.levels.ERROR)
      return
    end
    files = expanded
  end
  
  -- Sort files for consistent output
  table.sort(files)
  
  -- Process each file
  for i, filepath in ipairs(files) do
    if #files > 1 then
      -- Print separator for multiple files
      if i > 1 then
        io.write("\n") -- Empty line between files
      end
      io.write(string.format("==> %s <==\n", filepath))
      io.flush()
    end
    
    M.cat_single_file(filepath, opts)
  end
end

---Display a single file with syntax highlighting
---@param filepath string Path to the file
---@param opts? table Additional options
function M.cat_single_file(filepath, opts)
  opts = opts or {}
  
  -- Optimized file existence check (already done in calling function)
  -- Skip redundant file_exists call since we already validated the file
  
  -- Read file contents
  local lines, err = utils.read_file(filepath)
  if not lines then
    vim.notify("Error reading file: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end
  
  -- Detect filetype
  local filetype = filedetect.detect_filetype(filepath)
  
  -- Get configuration
  local cfg = config.get()
  local show_line_numbers = opts.show_line_numbers ~= nil and opts.show_line_numbers or cfg.show_line_numbers
  local paging_enabled = opts.paging ~= nil and opts.paging or cfg.paging.enabled
  local lines_per_page = opts.lines_per_page or cfg.paging.lines_per_page
  local use_global_bg = opts.use_global_background ~= nil and opts.use_global_background or cfg.use_global_background
  
  -- Set global background state before highlighting
  local output = require("nvim-cat.output")
  if use_global_bg then
    output.start_global_background()
  end
  
  -- Apply syntax highlighting if supported
  local highlighted_lines = lines
  if filetype and filedetect.supports_highlighting(filetype) then
    highlighted_lines = M.apply_syntax_highlighting(lines, filetype)
  end
  
  -- Format output
  local output_lines = M.format_output(highlighted_lines, {
    show_line_numbers = show_line_numbers,
    filepath = filepath,
    filetype = filetype
  })
  
  -- Display with paging if needed
  if paging_enabled and #output_lines > lines_per_page then
    M.display_paged(output_lines, lines_per_page, use_global_bg)
  else
    M.display_immediate(output_lines, use_global_bg)
  end
end

---Apply syntax highlighting to lines
---@param lines string[] File lines
---@param filetype string Detected filetype
---@return string[] Highlighted lines
function M.apply_syntax_highlighting(lines, filetype)
  -- For now, return lines as-is
  -- This will be implemented in highlight.lua
  local highlight = require("nvim-cat.highlight")
  return highlight.apply_syntax(lines, filetype)
end

---Format output lines with line numbers and other decorations
---@param lines string[] Content lines
---@param opts table Formatting options
---@return string[] Formatted lines
function M.format_output(lines, opts)
  local output = require("nvim-cat.output")
  return output.format_lines(lines, opts)
end

---Display lines immediately (no paging)
---@param lines string[] Lines to display
---@param use_global_bg? boolean Whether to use global background
function M.display_immediate(lines, use_global_bg)
  local output = require("nvim-cat.output")
  
  -- Optimized output with batched writes
  local display_lines = {}
  local terminal_width = use_global_bg and (tonumber(os.getenv("COLUMNS")) or 80) or nil
  
  -- Start global background if requested
  if use_global_bg then
    io.write(output.start_global_background())
  end
  
  -- Process all lines first, then batch write
  for _, line in ipairs(lines) do
    local display_line = line
    if use_global_bg then
      display_line = output.apply_line_background(line, terminal_width)
    end
    table.insert(display_lines, display_line)
  end
  
  -- Batch write for better performance
  io.write(table.concat(display_lines, "\n") .. "\n")
  
  -- End global background if used
  if use_global_bg then
    io.write(output.end_global_background())
  end
  
  io.flush()
end

---Display lines with paging
---@param lines string[] Lines to display
---@param lines_per_page number Lines per page
---@param use_global_bg? boolean Whether to use global background
function M.display_paged(lines, lines_per_page, use_global_bg)
  local output = require("nvim-cat.output")
  local total_lines = #lines
  local total_pages = math.ceil(total_lines / lines_per_page)
  local current_page = 1
  
  -- Get terminal width for background padding
  local terminal_width = tonumber(os.getenv("COLUMNS")) or 80
  
  -- Start global background if requested
  if use_global_bg then
    io.write(output.start_global_background())
  end
  
  while current_page <= total_pages do
    local start_line = (current_page - 1) * lines_per_page + 1
    local end_line = math.min(current_page * lines_per_page, total_lines)
    
    -- Display current page
    for i = start_line, end_line do
      local display_line = lines[i]
      if use_global_bg then
        display_line = output.apply_line_background(lines[i], terminal_width)
      end
      io.write(display_line .. "\n")
    end
    io.flush()
    
    -- Show paging info and wait for input
    if current_page < total_pages then
      -- Temporarily reset background for paging prompt
      if use_global_bg then
        io.write(output.end_global_background())
      end
      
      local progress = utils.progress_bar(current_page, total_pages, 20)
      io.write(string.format("\n%s Page %d/%d - Press ENTER for next page, 'q' to quit: ", 
        progress, current_page, total_pages))
      io.flush()
      
      local input = io.read()
      if input == "q" or input == "Q" then
        break
      end
      
      -- Restart background for next page
      if use_global_bg then
        io.write(output.start_global_background())
      end
      
      current_page = current_page + 1
    else
      current_page = current_page + 1
    end
  end
  
  -- End global background if used
  if use_global_bg then
    io.write(output.end_global_background())
  end
end

---Get version information
---@return string Version string
function M.version()
  return "nvim-cat v0.1.0"
end

---Get help information
---@return string Help text
function M.help()
  return [[
nvim-cat - Syntax-highlighted file viewer for Neovim

USAGE:
  :NvimCat <file|pattern>    View file(s) with syntax highlighting
  
EXAMPLES:
  :NvimCat init.lua          View single file
  :NvimCat *.js              View all JavaScript files
  :NvimCat lua/**/*.lua      View all Lua files recursively

CONFIGURATION:
  Call require('nvim-cat').setup({...}) in your init.lua

For more information, see :help nvim-cat
]]
end

return M