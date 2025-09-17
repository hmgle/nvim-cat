---@class NvimCat
---@field config NvimCatConfig
local M = {}

local config = require("nvim-cat.config")
local utils = require("nvim-cat.utils")
local filedetect = require("nvim-cat.filedetect")
local colorscheme = require("nvim-cat.colorscheme")

local term_dimensions = {
  lines = 24,
  cols = 80,
}

---Set terminal dimensions from the calling script
---@param lines number Terminal height
---@param cols number Terminal width
function M.set_term_dimensions(lines, cols)
  term_dimensions.lines = lines or term_dimensions.lines
  term_dimensions.cols = cols or term_dimensions.cols
end


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
  -- Page if content height is greater than terminal height (minus 1 for status bar)
  if paging_enabled and #output_lines > (term_dimensions.lines - 1) then
    M.display_paged_interactive(output_lines, {
      filepath = filepath,
      use_global_background = use_global_bg,
    })
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
  local terminal_width
  if use_global_bg then
    terminal_width = tonumber(term_dimensions.cols) or 80
  end
  
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


--Display lines with interactive paging
---@param lines string[] Lines to display
---@param opts table Display options including filepath
function M.display_paged_interactive(lines, opts)
  opts = opts or {}
  local output = require("nvim-cat.output")
  local total_lines = #lines
  local top_line = 1
  local use_global_bg = opts.use_global_background ~= false

  -- Get terminal dimensions
  local view_height = (tonumber(term_dimensions.lines) or 24) - 1 -- Account for status bar
  if view_height < 1 then
    view_height = 1
  end
  local view_width = tonumber(term_dimensions.cols) or 80

  -- Terminal state management for safe recovery
  local terminal_state_saved = false
  local function save_terminal_state()
    if not terminal_state_saved then
      os.execute("stty -g > /tmp/nvim-cat-stty-$$.save 2>/dev/null")
      terminal_state_saved = true
    end
  end

  local function restore_terminal_state()
    if terminal_state_saved then
      os.execute("stty $(cat /tmp/nvim-cat-stty-$$.save 2>/dev/null) 2>/dev/null")
      os.execute("rm -f /tmp/nvim-cat-stty-$$.save 2>/dev/null")
      terminal_state_saved = false
    end
  end

  -- Set up signal handler for cleanup
  local function cleanup_and_exit()
    restore_terminal_state()
    io.write("\27[2J\27[H") -- Clear screen
    io.flush()
    os.exit(0)
  end

  local function redraw()
    -- Clear screen
    io.write("\27[2J\27[H")
    io.flush()

    -- Determine visible lines
    local end_line = total_lines > 0 and math.min(top_line + view_height - 1, total_lines) or 0

    if use_global_bg then
      io.write(output.start_global_background())
    end

    -- Display lines with optional background fill
    for offset = 0, view_height - 1 do
      local index = top_line + offset
      local line = lines[index] or ""
      if use_global_bg then
        line = output.apply_line_background(line, view_width)
      end
      io.write(line .. "\n")
    end

    if use_global_bg then
      io.write(output.end_global_background())
    end
    io.flush()

    -- Draw status bar
    local percentage = total_lines > 0 and math.floor((end_line / total_lines) * 100) or 0
    local status_text = string.format(" %s | %d-%d/%d (%d%%) | j/k, space/f/b, g/G, q to quit ",
      opts.filepath or "nvim-cat", top_line, end_line, total_lines, percentage)

    -- Pad status bar to full width
    local padding = view_width - #status_text
    if padding > 0 then
      status_text = status_text .. string.rep(" ", padding)
    end

    -- Inverse video for status bar
    io.write("\27[7m" .. status_text .. "\27[0m")
    io.flush()
  end

  -- Calculate safe boundaries for paging
  local function safe_page_down()
    if total_lines <= view_height then
      -- Content fits in one screen, no need to scroll
      return top_line
    end
    return math.min(top_line + view_height, math.max(1, total_lines - view_height + 1))
  end

  local function safe_page_up()
    return math.max(top_line - view_height, 1)
  end

  local function safe_line_down()
    if total_lines <= view_height then
      -- Content fits in one screen, no need to scroll
      return top_line
    end
    return math.min(top_line + 1, math.max(1, total_lines - view_height + 1))
  end

  local function safe_line_up()
    return math.max(top_line - 1, 1)
  end

  -- Initial draw
  redraw()

  -- Save terminal state before entering raw mode
  save_terminal_state()

  -- Main input loop
  while true do
    -- Set terminal to raw mode with error handling
    local ok = os.execute("stty raw -echo 2>/dev/null")
    local char = ok and io.read(1) or 'q'
    -- Restore terminal mode with error handling
    os.execute("stty -raw echo 2>/dev/null")

    if char == 'q' or char == 'Q' then
      -- Restore terminal and exit cleanly
      restore_terminal_state()
      cleanup_and_exit()
      break
    elseif char == 'j' then
      top_line = safe_line_down()
      redraw()
    elseif char == 'k' then
      top_line = safe_line_up()
      redraw()
    elseif char == ' ' or char == 'f' then -- Page down
      top_line = safe_page_down()
      redraw()
    elseif char == 'b' then -- Page up
      top_line = safe_page_up()
      redraw()
    elseif char == 'g' then -- Go to top
      top_line = 1
      redraw()
    elseif char == 'G' then -- Go to bottom
      top_line = math.max(1, total_lines - view_height + 1)
      redraw()
    elseif char == '\27' then -- ESC key
      -- Read potential arrow key sequence
      local seq1 = io.read(1)
      local seq2 = io.read(1)
      if seq1 == '[' then
        if seq2 == 'A' then -- Up arrow
          top_line = safe_line_up()
          redraw()
        elseif seq2 == 'B' then -- Down arrow
          top_line = safe_line_down()
          redraw()
        elseif seq2 == 'C' then -- Right arrow (page down)
          top_line = safe_page_down()
          redraw()
        elseif seq2 == 'D' then -- Left arrow (page up)
          top_line = safe_page_up()
          redraw()
        end
      end
    end
  end

  -- Ensure terminal state is restored on normal exit
  restore_terminal_state()
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
