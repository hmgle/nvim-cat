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

local function resolve_display_options(opts)
  local cfg = config.get()
  return {
    show_line_numbers = opts.show_line_numbers ~= nil and opts.show_line_numbers or cfg.show_line_numbers,
    paging_enabled = opts.paging ~= nil and opts.paging or cfg.paging.enabled,
    lines_per_page = opts.lines_per_page or cfg.paging.lines_per_page,
    use_global_background = opts.use_global_background ~= nil and opts.use_global_background or cfg.use_global_background,
  }
end

local function build_file_output(filepath, opts, display_opts)
  display_opts = display_opts or resolve_display_options(opts)

  local lines, err = utils.read_file(filepath)
  if not lines then
    local message = err or ("Error reading file: " .. filepath)
    return nil, message
  end

  local filetype = filedetect.detect_filetype(filepath)

  local highlighted_lines = lines
  if filetype and filedetect.supports_highlighting(filetype) then
    highlighted_lines = M.apply_syntax_highlighting(lines, filetype)
  end

  local format_opts = {
    show_line_numbers = display_opts.show_line_numbers,
    filepath = filepath,
    filetype = filetype,
  }

  if opts.show_header then
    format_opts.show_header = true
  end

  local formatted_lines = M.format_output(highlighted_lines, format_opts)

  return {
    filepath = filepath,
    filetype = filetype,
    lines = formatted_lines,
    display_line_count = #formatted_lines,
    source_line_count = #lines,
  }
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
---@param pattern string|string[] File path, glob pattern, or list of entries
---@param opts? table Additional options for this call
---@return boolean success True when processing completed without an early quit
function M.cat(pattern, opts)
  opts = opts or {}
  
  local patterns = {}
  if type(pattern) == "table" then
    for _, value in ipairs(pattern) do
      table.insert(patterns, value)
    end
  elseif type(pattern) == "string" then
    table.insert(patterns, pattern)
  else
    vim.notify("Invalid pattern type for nvim-cat", vim.log.levels.ERROR)
    return false
  end

  -- Expand provided entries into concrete files while preserving order
  local files = {}
  local seen = {}
  local had_error = false
  local entries = {}
  local error_messages = {}

  local function record_error(message)
    had_error = true
    table.insert(entries, {
      type = "error",
      message = message,
    })
    table.insert(error_messages, message)
  end

  for _, entry in ipairs(patterns) do
    local resolved
    local stat = vim.loop.fs_stat(entry)

    if stat then
      if stat.type == "file" then
        resolved = { entry }
      elseif stat.type == "directory" then
        record_error("Cannot cat a directory: " .. entry)
      end
    end

    if not resolved then
      local expanded = utils.expand_glob(entry)
      if #expanded == 0 then
        record_error("No files found matching pattern: " .. entry)
      else
        resolved = expanded
      end
    end

    if resolved then
      for _, filepath in ipairs(resolved) do
        if not seen[filepath] then
          seen[filepath] = true
          table.insert(files, filepath)
          table.insert(entries, {
            type = "file",
            filepath = filepath,
          })
        end
      end
    end
  end

  local total_files = #files
  local total_errors = #error_messages

  if total_files == 0 then
    for _, entry in ipairs(entries) do
      if entry.type == "error" then
        vim.notify(entry.message, vim.log.levels.ERROR)
      end
    end
    return false
  end

  if total_files == 1 and total_errors == 0 then
    M.cat_single_file(files[1], opts)
    return true
  end

  local display_opts = resolve_display_options(opts)
  local aggregated_lines = {}
  local segments = {}
  local current_line = 0
  local previous_segment
  local file_index = 0
  local show_file_headers = total_files > 1

  local function append_separator()
    if previous_segment then
      table.insert(aggregated_lines, "")
      current_line = current_line + 1
      previous_segment.end_line = current_line
    end
  end

  for _, entry in ipairs(entries) do
    if entry.type == "file" then
      local file_output, read_err = build_file_output(entry.filepath, opts, display_opts)
      if file_output then
        if file_index > 0 or previous_segment then
          append_separator()
        end

        file_index = file_index + 1

        local start_line = current_line + 1
        if show_file_headers then
          table.insert(aggregated_lines, string.format("==> %s <==", file_output.filepath))
          current_line = current_line + 1
        end

        local content_start = current_line + 1
        for _, line in ipairs(file_output.lines) do
          table.insert(aggregated_lines, line)
          current_line = current_line + 1
        end

        local content_end = current_line
        local segment = {
          kind = "file",
          index = #segments + 1,
          filepath = file_output.filepath,
          filetype = file_output.filetype,
          start_line = start_line,
          end_line = content_end,
          content_start = content_start,
          content_end = content_end >= content_start and content_end or content_start,
          content_length = file_output.display_line_count,
          file_index = file_index,
        }

        segments[#segments + 1] = segment
        previous_segment = segment
      else
        had_error = true
        local message = read_err or ("Error reading file: " .. entry.filepath)
        local message_lines = { "[error] " .. message }
        local start_line = current_line + 1
        for _, line in ipairs(message_lines) do
          table.insert(aggregated_lines, line)
          current_line = current_line + 1
        end
        local segment = {
          kind = "error",
          index = #segments + 1,
          label = message,
          start_line = start_line,
          end_line = current_line,
          content_start = start_line,
          content_end = current_line,
          content_length = #message_lines,
          file_index = file_index,
        }
        segments[#segments + 1] = segment
        previous_segment = segment
      end
    elseif entry.type == "error" then
      local message = entry.message
      if message and message ~= "" then
        local message_lines = { "[error] " .. message }
        local start_line = current_line + 1
        for _, line in ipairs(message_lines) do
          table.insert(aggregated_lines, line)
          current_line = current_line + 1
        end
        local segment = {
          kind = "error",
          index = #segments + 1,
          label = message,
          start_line = start_line,
          end_line = current_line,
          content_start = start_line,
          content_end = current_line,
          content_length = #message_lines,
          file_index = file_index,
        }
        segments[#segments + 1] = segment
        previous_segment = segment
      end
    end
  end

  if #segments == 0 then
    for _, message in ipairs(error_messages) do
      vim.notify(message, vim.log.levels.ERROR)
    end
    return false
  end

  local total_lines = #aggregated_lines
  if display_opts.paging_enabled and total_lines > (term_dimensions.lines - 1) then
    M.display_paged_interactive(aggregated_lines, {
      entries = segments,
      file_count = file_index,
      use_global_background = display_opts.use_global_background,
    })
  else
    M.display_immediate(aggregated_lines, display_opts.use_global_background)
  end

  return not had_error
end

---Display a single file with syntax highlighting
---@param filepath string Path to the file
---@param opts? table Additional options
---@return string|nil action Pager action when interactive ("next", "prev", "quit")
function M.cat_single_file(filepath, opts)
  opts = opts or {}

  local display_opts = resolve_display_options(opts)
  local file_output, read_err = build_file_output(filepath, opts, display_opts)
  if not file_output then
    if read_err and read_err ~= "" then
      vim.notify(read_err, vim.log.levels.ERROR)
    end
    return nil
  end

  local output_lines = file_output.lines

  if display_opts.paging_enabled and #output_lines > (term_dimensions.lines - 1) then
    local segments = {
      {
        kind = "file",
        index = 1,
        filepath = file_output.filepath,
        filetype = file_output.filetype,
        start_line = 1,
        end_line = #output_lines,
        content_start = 1,
        content_end = #output_lines,
        content_length = #output_lines,
        file_index = 1,
      },
    }
    return M.display_paged_interactive(output_lines, {
      entries = segments,
      use_global_background = display_opts.use_global_background,
    })
  else
    M.display_immediate(output_lines, display_opts.use_global_background)
  end

  return nil
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


---Display lines with interactive paging
---@param lines string[] Lines to display
---@param opts table Display options including filepath
---@return string action Pager control action for the caller
function M.display_paged_interactive(lines, opts)
  opts = opts or {}
  local output = require("nvim-cat.output")
  local total_lines = #lines
  local top_line = 1
  local use_global_bg = opts.use_global_background ~= false

  local items = {}
  local file_items = {}

  local function normalise_item(item, idx)
    item.index = item.index or idx
    item.kind = item.kind or "file"
    item.start_line = item.start_line or 1
    item.end_line = item.end_line or total_lines
    item.content_start = item.content_start or item.start_line
    item.content_end = item.content_end or item.end_line
    if item.content_end < item.content_start then
      item.content_end = item.content_start
    end
    local length = item.content_length
    if not length or length <= 0 then
      length = item.content_end - item.content_start + 1
    end
    if length <= 0 then
      length = 1
    end
    item.content_length = length
    return item
  end

  if opts.entries and #opts.entries > 0 then
    for idx, entry in ipairs(opts.entries) do
      local item = normalise_item(entry, idx)
      if item.kind == "file" and not item.file_index then
        item.file_index = #file_items + 1
      end
      items[#items + 1] = item
      if item.kind == "file" then
        file_items[#file_items + 1] = item
      end
    end
  else
    local default_item = normalise_item({
      kind = "file",
      filepath = opts.filepath or "nvim-cat",
      filetype = opts.filetype,
      start_line = 1,
      end_line = total_lines,
      content_start = 1,
      content_end = total_lines > 0 and total_lines or 1,
      content_length = total_lines > 0 and total_lines or 1,
      file_index = 1,
    }, 1)
    items = { default_item }
    file_items = { default_item }
  end

  if #items == 0 then
    return "quit"
  end

  if #file_items == 0 then
    for idx, item in ipairs(items) do
      item.file_index = idx
      file_items[idx] = item
    end
  end

  local total_files = #file_items
  local has_multiple_files = total_files > 1
  local active_item = items[1]
  local active_file_item = file_items[1]

  -- Get terminal dimensions
  local view_height = (tonumber(term_dimensions.lines) or 24) - 1 -- Account for status bar
  if view_height < 1 then
    view_height = 1
  end
  local view_width = tonumber(term_dimensions.cols) or 80
  local max_top = math.max(1, total_lines - view_height + 1)

  local function clamp_top(line)
    if total_lines <= view_height then
      return 1
    end
    if line < 1 then
      return 1
    end
    if line > max_top then
      return max_top
    end
    return line
  end

  local function find_item_for_line(line)
    for _, item in ipairs(items) do
      if line >= item.start_line and line <= item.end_line then
        return item
      end
    end
    return items[#items]
  end

  local function find_file_for_line(line)
    if #file_items == 0 then
      return nil
    end
    local candidate = file_items[1]
    for _, item in ipairs(file_items) do
      if line >= item.start_line then
        candidate = item
      end
      if line <= item.end_line then
        return item
      end
    end
    return candidate
  end

  -- Terminal state management for safe recovery
  local saved_terminal_state

  local function capture_terminal_state()
    if saved_terminal_state then
      return true
    end

    local handle = io.popen("stty -g 2>/dev/null", "r")
    if not handle then
      return false
    end

    local state = handle:read("*a")
    handle:close()

    if not state then
      return false
    end

    state = state:gsub("%s+$", "")
    if state == "" then
      return false
    end

    saved_terminal_state = state
    return true
  end

  local function restore_terminal_state()
    if saved_terminal_state and saved_terminal_state ~= "" then
      os.execute("stty " .. saved_terminal_state .. " 2>/dev/null")
    else
      os.execute("stty -raw echo 2>/dev/null")
    end
  end

  local function enter_raw_mode()
    capture_terminal_state()
    os.execute("stty raw -echo 2>/dev/null")
  end

  local function exit_raw_mode()
    restore_terminal_state()
  end

  -- Set up cleanup helper that restores the terminal and clears the screen
  local function cleanup()
    restore_terminal_state()
    io.write("\27[2J\27[H") -- Clear screen
    io.flush()
    return "quit"
  end

  local function redraw()
    -- Clear screen
    io.write("\27[2J\27[H")
    io.flush()

    -- Determine visible lines
    local end_line = total_lines > 0 and math.min(top_line + view_height - 1, total_lines) or 0
    local mid_line = total_lines > 0 and math.min(top_line + math.floor(view_height / 2), total_lines) or 1
    if mid_line < 1 then
      mid_line = 1
    end
    active_item = find_item_for_line(mid_line)
    active_file_item = find_file_for_line(mid_line) or active_file_item

    local file_label = active_item.label or active_item.filepath or opts.filepath or "nvim-cat"

    local content_start = active_item.content_start or active_item.start_line
    local content_end = active_item.content_end or active_item.end_line
    if content_end < content_start then
      content_end = content_start
    end
    local segment_total = active_item.content_length or (content_end - content_start + 1)
    if segment_total <= 0 then
      segment_total = 1
    end

    local visible_start = math.max(top_line, content_start)
    if visible_start > content_end then
      visible_start = content_end
    end
    local visible_end = math.min(end_line, content_end)
    if visible_end < visible_start then
      visible_end = visible_start
    end

    local relative_start = visible_start - content_start + 1
    local relative_end = visible_end - content_start + 1
    if relative_start < 1 then
      relative_start = 1
    end
    if relative_end < relative_start then
      relative_end = relative_start
    end
    if relative_end > segment_total then
      relative_end = segment_total
    end
    if relative_start > segment_total then
      relative_start = segment_total
    end
    local percentage = math.floor((relative_end / segment_total) * 100)

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
    local file_prefix = ""
    if has_multiple_files then
      if active_item.kind == "file" and active_item.file_index then
        file_prefix = string.format("[%d/%d] ", active_item.file_index, total_files)
      elseif active_file_item and active_file_item.file_index then
        file_prefix = string.format("[~%d/%d] ", active_file_item.file_index, total_files)
      else
        file_prefix = "[error] "
      end
    elseif active_item.kind == "error" then
      file_prefix = "[error] "
    end
    local controls = "j/k, space/f/b, g/G, q to quit"
    if has_multiple_files then
      controls = "n/p jump files, " .. controls
    end

    local status_text = string.format(
      " %s%s | %d-%d/%d (%d%%) | %s ",
      file_prefix,
      file_label,
      relative_start,
      relative_end,
      segment_total,
      percentage,
      controls
    )

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
    return clamp_top(top_line + view_height)
  end

  local function safe_page_up()
    return clamp_top(top_line - view_height)
  end

  local function safe_line_down()
    if total_lines <= view_height then
      -- Content fits in one screen, no need to scroll
      return top_line
    end
    return clamp_top(top_line + 1)
  end

  local function safe_line_up()
    return clamp_top(top_line - 1)
  end

  -- Initial draw
  redraw()

  -- Main input loop
  while true do
    enter_raw_mode()

    local char = io.read(1)
    local seq1, seq2

    if char == '\27' then
      seq1 = io.read(1)
      seq2 = io.read(1)
    end

    exit_raw_mode()

    if not char or char == '' then
      char = 'q'
    end

    if char == 'q' or char == 'Q' then
      return cleanup()
    elseif has_multiple_files and (char == 'n' or char == 'N') then
      if active_file_item and active_file_item.file_index < total_files then
        local target = file_items[active_file_item.file_index + 1].start_line
        top_line = clamp_top(target)
        redraw()
      end
    elseif has_multiple_files and (char == 'p' or char == 'P') then
      if active_file_item and active_file_item.file_index > 1 then
        local target = file_items[active_file_item.file_index - 1].start_line
        top_line = clamp_top(target)
        redraw()
      end
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
      top_line = clamp_top(1)
      redraw()
    elseif char == 'G' then -- Go to bottom
      top_line = clamp_top(total_lines - view_height + 1)
      redraw()
    elseif char == '\27' then -- ESC key
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
  return cleanup()
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
