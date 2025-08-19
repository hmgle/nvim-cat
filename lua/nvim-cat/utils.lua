local M = {}

---Check if a file exists and is readable
---@param filepath string Path to the file
---@return boolean
function M.file_exists(filepath)
  local stat = vim.loop.fs_stat(filepath)
  return stat ~= nil and stat.type == "file"
end

---Check if a path is a directory
---@param path string Path to check
---@return boolean
function M.is_directory(path)
  local stat = vim.loop.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

---Read file contents with optimized buffering
---@param filepath string Path to the file
---@return string[]|nil lines File lines or nil on error
---@return string|nil error Error message if any
function M.read_file(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil, "Could not open file: " .. filepath
  end
  
  -- Check file size to optimize reading strategy
  local file_size = file:seek("end")
  file:seek("set", 0)
  
  local lines = {}
  
  if file_size < 1024 * 1024 then -- Files smaller than 1MB
    -- Read entire file for small files
    local content = file:read("*all")
    if content then
      for line in content:gmatch("([^\n]*)\n?") do
        if line ~= "" or content:sub(-1) == "\n" then
          table.insert(lines, line)
        end
      end
    end
  else
    -- Use buffered reading for large files
    local buffer_size = 8192
    local buffer = ""
    
    while true do
      local chunk = file:read(buffer_size)
      if not chunk then break end
      
      buffer = buffer .. chunk
      
      -- Process complete lines from buffer
      while true do
        local line_end = buffer:find("\n")
        if not line_end then break end
        
        local line = buffer:sub(1, line_end - 1)
        table.insert(lines, line)
        buffer = buffer:sub(line_end + 1)
      end
    end
    
    -- Add remaining buffer as last line if not empty
    if buffer ~= "" then
      table.insert(lines, buffer)
    end
  end
  
  file:close()
  return lines
end

---Expand glob patterns to file list with caching
---@param pattern string Glob pattern
---@return string[] List of matching files
function M.expand_glob(pattern)
  -- Cache glob results for repeated patterns
  if not M._glob_cache then
    M._glob_cache = {}
  end
  
  if M._glob_cache[pattern] then
    return M._glob_cache[pattern]
  end
  
  local expanded = vim.fn.glob(pattern, false, true)
  
  -- Filter out directories efficiently using batch stat calls
  local files = {}
  local stat_results = {}
  
  -- Batch file existence checks
  for _, path in ipairs(expanded) do
    local stat = vim.loop.fs_stat(path)
    stat_results[path] = stat
  end
  
  -- Process results
  for _, path in ipairs(expanded) do
    local stat = stat_results[path]
    if stat and stat.type == "file" then
      table.insert(files, path)
    end
  end
  
  -- Cache result (limit cache size)
  if vim.tbl_count(M._glob_cache) < 100 then
    M._glob_cache[pattern] = files
  end
  
  return files
end

---Get file extension from filepath
---@param filepath string Path to the file
---@return string File extension (including the dot)
function M.get_extension(filepath)
  local basename = vim.fn.fnamemodify(filepath, ":t")
  local dot_index = basename:match("^.*()%.")
  
  if dot_index then
    return basename:sub(dot_index - 1)
  else
    return ""
  end
end

---Get filename without extension
---@param filepath string Path to the file
---@return string Filename without extension
function M.get_basename(filepath)
  return vim.fn.fnamemodify(filepath, ":t:r")
end

---Get directory path from filepath
---@param filepath string Path to the file
---@return string Directory path
function M.get_dirname(filepath)
  return vim.fn.fnamemodify(filepath, ":h")
end

---Split string by delimiter
---@param str string String to split
---@param delimiter string Delimiter
---@return string[] Split parts
function M.split(str, delimiter)
  local result = {}
  local pattern = string.format("([^%s]+)", delimiter)
  
  for match in str:gmatch(pattern) do
    table.insert(result, match)
  end
  
  return result
end

---Trim whitespace from string
---@param str string String to trim
---@return string Trimmed string
function M.trim(str)
  return str:match("^%s*(.-)%s*$")
end

---Check if string starts with prefix
---@param str string String to check
---@param prefix string Prefix to look for
---@return boolean
function M.starts_with(str, prefix)
  return str:sub(1, #prefix) == prefix
end

---Check if string ends with suffix
---@param str string String to check
---@param suffix string Suffix to look for
---@return boolean
function M.ends_with(str, suffix)
  return suffix == "" or str:sub(-#suffix) == suffix
end

---Get terminal width
---@return number Terminal width in columns
function M.get_terminal_width()
  return vim.o.columns or 80
end

---Get terminal height
---@return number Terminal height in rows
function M.get_terminal_height()
  return vim.o.lines or 24
end

---Format number with padding
---@param num number Number to format
---@param width number Width for padding
---@return string Formatted number
function M.pad_number(num, width)
  return string.format("%" .. width .. "d", num)
end

---Create a progress indicator
---@param current number Current value
---@param total number Total value
---@param width? number Width of progress bar (default: 20)
---@return string Progress bar string
function M.progress_bar(current, total, width)
  width = width or 20
  local percentage = math.min(current / total, 1.0)
  local filled = math.floor(percentage * width)
  local empty = width - filled
  
  return string.format("[%s%s] %d%%", 
    string.rep("=", filled),
    string.rep("-", empty),
    math.floor(percentage * 100)
  )
end

---Debounce function calls
---@param fn function Function to debounce
---@param delay number Delay in milliseconds
---@return function Debounced function
function M.debounce(fn, delay)
  local timer = nil
  
  return function(...)
    local args = { ... }
    
    if timer then
      vim.fn.timer_stop(timer)
    end
    
    timer = vim.fn.timer_start(delay, function()
      fn(unpack(args))
      timer = nil
    end)
  end
end

---Deep copy a table with cycle detection for safety
---@param orig table Original table
---@param seen? table Internal cycle detection table
---@return table Copied table
function M.deep_copy(orig, seen)
  if type(orig) ~= "table" then
    return orig
  end
  
  seen = seen or {}
  if seen[orig] then
    return seen[orig] -- Prevent infinite recursion
  end
  
  local copy = {}
  seen[orig] = copy
  
  for orig_key, orig_value in next, orig, nil do
    copy[M.deep_copy(orig_key, seen)] = M.deep_copy(orig_value, seen)
  end
  
  setmetatable(copy, M.deep_copy(getmetatable(orig), seen))
  return copy
end

---Clear internal caches to free memory
function M.clear_caches()
  M._glob_cache = nil
end

-- Initialize glob cache
M._glob_cache = {}

return M