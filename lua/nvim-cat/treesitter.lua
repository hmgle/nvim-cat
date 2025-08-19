---@class TreesitterEngine
---@field cache table<string, table> Cache for parsed syntax data
---@field temp_buffers table<number, boolean> Track temporary buffers

local M = {}
local cache_manager = require("nvim-cat.cache")

-- Initialize managed cache
M.cache = cache_manager.create_cache("treesitter", 2000, 600)
M.temp_buffers = {}

-- Namespace for nvim-cat highlights
M.ns_id = vim.api.nvim_create_namespace('nvim-cat-treesitter')

---Check if treesitter is available and has parser for filetype
---@param filetype string File type to check
---@return boolean Whether treesitter parser is available
function M.has_parser(filetype)
  local has_treesitter, parsers = pcall(require, "nvim-treesitter.parsers")
  if not has_treesitter then
    return false
  end
  
  return parsers.has_parser(filetype)
end

---Ensure highlight queries are loaded for the given filetype
---@param filetype string File type
function M.ensure_queries_loaded(filetype)
  pcall(function()
    local has_vim_ts, vim_ts = pcall(require, "vim.treesitter")
    if not has_vim_ts then
      return
    end
    
    -- Try to get and cache the highlight query
    local query = vim_ts.query.get(filetype, 'highlights')
    if not query then
      -- Try loading from runtime path
      vim.cmd("runtime queries/" .. filetype .. "/highlights.scm")
      query = vim_ts.query.get(filetype, 'highlights')
    end
    
    -- Verify we have a working query
    if query and query.captures then
      return true
    end
    
    return false
  end)
end

---Verify that treesitter is actually working for the buffer
---@param bufnr number Buffer number
---@return boolean Whether treesitter is working
function M.verify_treesitter_working(bufnr)
  local ok, result = pcall(function()
    local has_ts, ts = pcall(require, "vim.treesitter")
    if not has_ts then
      return false
    end
    
    -- Try to get parser
    local parser = ts.get_parser(bufnr)
    if not parser then
      return false
    end
    
    -- Try to parse
    parser:parse()
    
    -- Try to get language tree
    local tree = parser:language_for_range({ 0, 0, 0, 1 })
    if not tree then
      return false
    end
    
    -- Try to get query
    local query = vim.treesitter.query.get(tree:lang(), 'highlights')
    if not query or not query.captures then
      return false
    end
    
    return true
  end)
  
  return ok and result
end

---Create a temporary buffer for syntax parsing
---@param lines string[] File lines
---@param filetype string File type
---@return number|nil Buffer number or nil on failure
function M.create_temp_buffer(lines, filetype)
  if not lines or #lines == 0 then
    return nil
  end
  
  -- Create an unlisted, temporary buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  if not bufnr or bufnr == 0 then
    return nil
  end
  
  -- Set buffer contents
  local ok = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, lines)
  if not ok then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return nil
  end
  
  -- Set filetype to trigger syntax highlighting
  ok = pcall(vim.api.nvim_buf_set_option, bufnr, 'filetype', filetype)
  if not ok then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return nil
  end
  
  -- Ensure treesitter is properly initialized for this buffer
  if M.has_parser(filetype) then
    pcall(function()
      -- Try multiple initialization approaches for better compatibility
      
      -- Approach 1: Use nvim-treesitter configs if available
      local has_ts_configs, ts_configs = pcall(require, "nvim-treesitter.configs")
      if has_ts_configs then
        -- Get the highlight config
        local highlight_config = ts_configs.get_module("highlight")
        if highlight_config and highlight_config.attach then
          highlight_config.attach(bufnr, filetype)
        end
        
        -- Try the attach_module approach as well
        if ts_configs.attach_module then
          ts_configs.attach_module("highlight", bufnr)
        end
      end
      
      -- Approach 2: Direct vim.treesitter initialization
      local has_vim_ts, vim_ts = pcall(require, "vim.treesitter")
      if has_vim_ts then
        -- Ensure parser is loaded for this buffer
        vim_ts.get_parser(bufnr, filetype)
        
        -- Force syntax to be applied
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd("TSBufEnable highlight")
        end)
      end
      
      -- Approach 3: Manual query loading and setup
      M.ensure_queries_loaded(filetype)
    end)
  end
  
  -- Track this buffer for cleanup
  M.temp_buffers[bufnr] = true
  
  return bufnr
end

---Get highlight captures at specific position using treesitter
---@param bufnr number Buffer number
---@param row number 0-indexed row
---@param col number 0-indexed column
---@return table[] List of capture information
function M.get_captures_at_pos(bufnr, row, col)
  local captures = {}
  
  -- Try modern vim.treesitter.get_captures_at_pos (Neovim 0.9+)
  local has_modern_api, result = pcall(vim.treesitter.get_captures_at_pos, bufnr, row, col)
  if has_modern_api and result then
    for _, capture_info in ipairs(result) do
      table.insert(captures, {
        capture = capture_info.capture,
        lang = capture_info.lang,
        metadata = capture_info.metadata or {},
      })
    end
    return captures
  end
  
  -- Fallback: try older API or manual query
  local has_ts, ts = pcall(require, "vim.treesitter")
  if not has_ts then
    return captures
  end
  
  -- Get parser for buffer
  local ok, parser = pcall(ts.get_parser, bufnr)
  if not ok or not parser then
    return captures
  end
  
  -- Parse if needed
  pcall(function()
    parser:parse()
  end)
  
  -- Get language tree
  local tree = parser:language_for_range({ row, col, row, col })
  if not tree then
    return captures
  end
  
  -- Try to get captures using manual query approach
  pcall(function()
    local query = vim.treesitter.query.get(tree:lang(), 'highlights')
    if query then
      for capture_id, node in query:iter_captures(tree:trees()[1]:root(), bufnr, row, row + 1) do
        local capture_name = query.captures[capture_id]
        if capture_name and ts.is_in_node_range(node, row, col) then
          table.insert(captures, {
            capture = capture_name,
            lang = tree:lang(),
            metadata = {},
          })
        end
      end
    end
  end)
  
  return captures
end

---Get all syntax highlights for a line using treesitter (optimized)
---@param bufnr number Buffer number
---@param line_idx number 0-indexed line number
---@return table[] Array of highlight segments {start_col, end_col, capture}
function M.get_line_highlights(bufnr, line_idx)
  local highlights = {}
  
  -- Get line content for length calculation
  local lines = vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)
  if not lines or #lines == 0 then
    return highlights
  end
  
  local line_length = #lines[1]
  if line_length == 0 then
    return highlights
  end
  
  -- Try optimized range-based query approach first
  local range_highlights = M.get_line_highlights_optimized(bufnr, line_idx, line_length)
  if #range_highlights > 0 then
    return range_highlights
  end
  
  -- Verify treesitter is actually working for this buffer
  if not M.verify_treesitter_working(bufnr) then
    return {} -- Return empty to trigger fallback
  end
  
  -- Fallback to character-by-character scanning (less efficient)
  return M.get_line_highlights_fallback(bufnr, line_idx, line_length)
end

---Get highlights using optimized range-based queries
---@param bufnr number Buffer number
---@param line_idx number 0-indexed line number
---@param line_length number Length of the line
---@return table[] Array of highlight segments
function M.get_line_highlights_optimized(bufnr, line_idx, line_length)
  local highlights = {}
  
  -- Try to get treesitter parser and query
  local has_ts, ts = pcall(require, "vim.treesitter")
  if not has_ts then
    return highlights
  end
  
  local ok, parser = pcall(ts.get_parser, bufnr)
  if not ok or not parser then
    return highlights
  end
  
  -- Parse if needed
  pcall(function()
    parser:parse()
  end)
  
  -- Get language tree for this line
  local tree = parser:language_for_range({ line_idx, 0, line_idx, line_length })
  if not tree then
    return highlights
  end
  
  -- Get highlights query
  local query = vim.treesitter.query.get(tree:lang(), 'highlights')
  if not query then
    -- Try alternative language names
    local alt_langs = { lua = "lua", javascript = "javascript", python = "python" }
    local alt_lang = alt_langs[tree:lang()]
    if alt_lang then
      query = vim.treesitter.query.get(alt_lang, 'highlights')
    end
    
    if not query then
      return highlights
    end
  end
  
  -- Process captures for this line range
  pcall(function()
    for capture_id, node, metadata in query:iter_captures(tree:trees()[1]:root(), bufnr, line_idx, line_idx + 1) do
      local capture_name = query.captures[capture_id]
      if capture_name then
        local start_row, start_col, end_row, end_col = node:range()
        
        -- Only process nodes that intersect with our target line
        if start_row <= line_idx and end_row >= line_idx then
          -- Clamp coordinates to the current line
          local actual_start_col = (start_row == line_idx) and start_col or 0
          local actual_end_col = (end_row == line_idx) and end_col or line_length
          
          -- Ensure we don't exceed line bounds
          actual_end_col = math.min(actual_end_col, line_length)
          
          if actual_start_col < actual_end_col then
            table.insert(highlights, {
              start_col = actual_start_col,
              end_col = actual_end_col - 1, -- Convert to inclusive end
              capture = capture_name,
              priority = metadata.priority or 100,
            })
          end
        end
      end
    end
  end)
  
  -- Sort by start position, then by priority
  table.sort(highlights, function(a, b)
    if a.start_col == b.start_col then
      return (a.priority or 100) > (b.priority or 100)
    end
    return a.start_col < b.start_col
  end)
  
  -- Remove overlapping highlights
  highlights = M.resolve_highlight_overlaps(highlights)
  
  return highlights
end

---Optimized fallback using intelligent sampling and range detection
---@param bufnr number Buffer number
---@param line_idx number 0-indexed line number
---@param line_length number Length of the line
---@return table[] Array of highlight segments
function M.get_line_highlights_fallback(bufnr, line_idx, line_length)
  local highlights = {}
  local processed_ranges = {}
  
  -- Get line content for intelligent sampling
  local lines = vim.api.nvim_buf_get_lines(bufnr, line_idx, line_idx + 1, false)
  if not lines or #lines == 0 then
    return highlights
  end
  local line = lines[1]
  
  -- Use word boundaries and syntax change points for sampling
  local sample_positions = M.get_intelligent_sample_positions(line, line_length)
  
  for _, col in ipairs(sample_positions) do
    local captures = M.get_captures_at_pos(bufnr, line_idx, col)
    
    if #captures > 0 then
      local capture = captures[1].capture
      
      -- Use binary search to find range boundaries efficiently
      local start_col, end_col = M.find_treesitter_range(bufnr, line_idx, col, capture, line_length)
      
      -- Check if this range was already processed
      local range_key = string.format("%d-%d-%s", start_col, end_col, capture)
      if not processed_ranges[range_key] then
        table.insert(highlights, {
          start_col = start_col,
          end_col = end_col,
          capture = capture,
        })
        processed_ranges[range_key] = true
      end
    end
  end
  
  -- Sort highlights by start position
  table.sort(highlights, function(a, b)
    return a.start_col < b.start_col
  end)
  
  return highlights
end

---Get intelligent sample positions based on line content
---@param line string Line content
---@param line_length number Line length
---@return number[] Sample positions
function M.get_intelligent_sample_positions(line, line_length)
  local positions = {}
  
  -- Always sample boundaries
  table.insert(positions, 0)
  if line_length > 1 then
    table.insert(positions, line_length - 1)
  end
  
  -- Sample at word boundaries, quotes, and common delimiters
  for i = 1, #line do
    local char = line:sub(i, i)
    local prev_char = i > 1 and line:sub(i-1, i-1) or ""
    
    -- Transition points likely to have syntax changes
    if char:match("[%w_]") and not prev_char:match("[%w_]") then
      table.insert(positions, i - 1) -- Word start (0-indexed)
    elseif not char:match("[%w_]") and prev_char:match("[%w_]") then
      table.insert(positions, i - 2) -- Word end (0-indexed)
    elseif char:match('["\'"`(){}%[%]]') then
      table.insert(positions, i - 1) -- Quote/bracket positions (0-indexed)
    end
  end
  
  -- Remove duplicates and clamp to valid range
  local unique_positions = {}
  local seen = {}
  for _, p in ipairs(positions) do
    p = math.max(0, math.min(p, line_length - 1))
    if not seen[p] then
      table.insert(unique_positions, p)
      seen[p] = true
    end
  end
  
  table.sort(unique_positions)
  return unique_positions
end

---Find treesitter capture range using binary search
---@param bufnr number Buffer number
---@param line_idx number Line index
---@param col number Starting column
---@param capture string Capture name to match
---@param line_length number Line length
---@return number, number start_col, end_col
function M.find_treesitter_range(bufnr, line_idx, col, capture, line_length)
  -- Binary search for start boundary
  local start_col = col
  local left, right = 0, col
  while left < right do
    local mid = math.floor((left + right) / 2)
    local captures = M.get_captures_at_pos(bufnr, line_idx, mid)
    if #captures > 0 and captures[1].capture == capture then
      right = mid
    else
      left = mid + 1
    end
  end
  start_col = left
  
  -- Binary search for end boundary
  local end_col = col
  left, right = col, line_length - 1
  while left < right do
    local mid = math.ceil((left + right) / 2)
    local captures = M.get_captures_at_pos(bufnr, line_idx, mid)
    if #captures > 0 and captures[1].capture == capture then
      left = mid
    else
      right = mid - 1
    end
  end
  end_col = left
  
  return start_col, end_col
end

---Resolve overlapping highlights by keeping higher priority ones
---@param highlights table[] Array of highlight segments
---@return table[] Non-overlapping highlights
function M.resolve_highlight_overlaps(highlights)
  if #highlights <= 1 then
    return highlights
  end
  
  local result = {}
  local last_end = -1
  
  for _, hl in ipairs(highlights) do
    if hl.start_col > last_end then
      -- No overlap, add this highlight
      table.insert(result, hl)
      last_end = hl.end_col
    elseif hl.end_col > last_end then
      -- Partial overlap, truncate the start
      hl.start_col = last_end + 1
      if hl.start_col <= hl.end_col then
        table.insert(result, hl)
        last_end = hl.end_col
      end
    end
    -- If completely overlapped, skip this highlight
  end
  
  return result
end

---Check if cache entry is still valid
---@param entry table Cache entry with timestamp
---@return boolean Whether the entry is valid
function M.is_cache_valid(entry)
  if not entry or not entry.timestamp then
    return false
  end
  return (os.time() - entry.timestamp) < CACHE_TTL
end

---Evict old cache entries if cache is too large
function M.evict_cache_if_needed()
  local count = 0
  for _ in pairs(M.cache) do
    count = count + 1
  end
  
  if count < CACHE_MAX_SIZE then
    return
  end
  
  -- Remove oldest entries or expired entries
  local entries_to_remove = {}
  local current_time = os.time()
  
  for key, entry in pairs(M.cache) do
    if not M.is_cache_valid(entry) then
      table.insert(entries_to_remove, key)
    end
  end
  
  -- If not enough expired entries, remove oldest ones
  if #entries_to_remove < (CACHE_MAX_SIZE * 0.2) then -- Remove 20% when full
    local sorted_entries = {}
    for key, entry in pairs(M.cache) do
      table.insert(sorted_entries, { key = key, timestamp = entry.timestamp })
    end
    
    table.sort(sorted_entries, function(a, b)
      return a.timestamp < b.timestamp
    end)
    
    for i = 1, math.floor(CACHE_MAX_SIZE * 0.2) do
      if sorted_entries[i] then
        table.insert(entries_to_remove, sorted_entries[i].key)
      end
    end
  end
  
  -- Remove entries
  for _, key in ipairs(entries_to_remove) do
    M.cache[key] = nil
    M.cache_stats.evictions = M.cache_stats.evictions + 1
  end
end

---Apply treesitter-based syntax highlighting to lines
---@param lines string[] File lines
---@param filetype string File type
---@return string[] Highlighted lines
function M.apply_treesitter_highlighting(lines, filetype)
  if not lines or #lines == 0 then
    return lines
  end
  
  -- Check managed cache first
  local cache_key = filetype .. ":" .. vim.fn.sha256(table.concat(lines, "\n"))
  local cached_result = cache_manager.get(M.cache, cache_key)
  
  if cached_result then
    return cached_result
  end
  
  -- Create temporary buffer
  local bufnr = M.create_temp_buffer(lines, filetype)
  if not bufnr then
    return lines
  end
  
  local highlighted_lines = {}
  
  -- Process each line
  for i, line in ipairs(lines) do
    local line_highlights = M.get_line_highlights(bufnr, i - 1) -- Convert to 0-indexed
    
    if #line_highlights == 0 then
      -- No highlights found, use original line
      table.insert(highlighted_lines, line)
    else
      -- Apply highlights to line
      local highlighted_line = M.apply_highlights_to_line(line, line_highlights)
      table.insert(highlighted_lines, highlighted_line)
    end
  end
  
  -- Cleanup temporary buffer
  M.cleanup_temp_buffer(bufnr)
  
  -- Cache result using managed cache
  cache_manager.set(M.cache, cache_key, highlighted_lines, #highlighted_lines)
  
  return highlighted_lines
end

---Apply highlights to a single line
---@param line string Original line
---@param highlights table[] Highlight segments
---@return string Highlighted line
function M.apply_highlights_to_line(line, highlights)
  if not highlights or #highlights == 0 then
    return line
  end
  
  local output = require("nvim-cat.output")
  local result = ""
  local last_col = 0
  
  for _, hl in ipairs(highlights) do
    -- Add text before highlight
    if hl.start_col > last_col then
      result = result .. line:sub(last_col + 1, hl.start_col)
    end
    
    -- Add highlighted text
    local text = line:sub(hl.start_col + 1, hl.end_col + 1)
    local highlight_group = M.map_capture_to_highlight_group(hl.capture)
    result = result .. output.format_token(text, highlight_group)
    
    last_col = hl.end_col + 1
  end
  
  -- Add remaining text
  if last_col < #line then
    result = result .. line:sub(last_col + 1)
  end
  
  return result
end

---Map treesitter capture to Neovim highlight group
---@param capture string Treesitter capture name (e.g., "@keyword", "@string")
---@return string Neovim highlight group name
function M.map_capture_to_highlight_group(capture)
  -- Handle modern treesitter captures (with @)
  if capture:match("^@") then
    -- Remove @ prefix and convert to highlight group
    local base_name = capture:sub(2)
    
    -- Common treesitter -> highlight group mappings
    local treesitter_map = {
      -- Keywords and control flow
      ["keyword"] = "Keyword",
      ["keyword.function"] = "Keyword", 
      ["keyword.operator"] = "Operator",
      ["keyword.return"] = "Keyword",
      ["conditional"] = "Conditional",
      ["repeat"] = "Repeat",
      ["exception"] = "Exception",
      
      -- Functions and identifiers
      ["function"] = "Function",
      ["function.call"] = "Function",
      ["function.builtin"] = "Function",
      ["method"] = "Function",
      ["method.call"] = "Function",
      ["constructor"] = "Function",
      
      -- Variables and identifiers
      ["variable"] = "Identifier",
      ["variable.builtin"] = "Identifier",
      ["parameter"] = "Identifier",
      ["field"] = "Identifier",
      ["property"] = "Identifier",
      
      -- Types
      ["type"] = "Type",
      ["type.builtin"] = "Type",
      ["type.definition"] = "Typedef",
      
      -- Constants and literals
      ["constant"] = "Constant",
      ["constant.builtin"] = "Constant",
      ["string"] = "String",
      ["character"] = "Character",
      ["number"] = "Number",
      ["boolean"] = "Boolean",
      ["float"] = "Float",
      
      -- Comments
      ["comment"] = "Comment",
      ["comment.documentation"] = "SpecialComment",
      
      -- Punctuation and operators
      ["punctuation.delimiter"] = "Delimiter",
      ["punctuation.bracket"] = "Delimiter",
      ["operator"] = "Operator",
      
      -- Preprocessor
      ["preproc"] = "PreProc",
      ["include"] = "Include",
      ["define"] = "Define",
      ["macro"] = "Macro",
      
      -- Special
      ["tag"] = "Tag",
      ["attribute"] = "Identifier",
      ["namespace"] = "Identifier",
      ["label"] = "Label",
      
      -- Markup (for documentation)
      ["text.emphasis"] = "Italic",
      ["text.strong"] = "Bold",
      ["text.title"] = "Title",
      ["text.uri"] = "Underlined",
    }
    
    -- Try exact match first
    if treesitter_map[base_name] then
      return treesitter_map[base_name]
    end
    
    -- Try partial matches for complex captures like "keyword.function.lua"
    for pattern, group in pairs(treesitter_map) do
      if base_name:match("^" .. pattern:gsub("%.", "%%.")) then
        return group
      end
    end
    
    -- Fallback: try to guess from the base name
    if base_name:match("keyword") then return "Keyword"
    elseif base_name:match("function") then return "Function"
    elseif base_name:match("string") then return "String"
    elseif base_name:match("comment") then return "Comment"
    elseif base_name:match("number") then return "Number"
    elseif base_name:match("type") then return "Type"
    end
  end
  
  -- Fallback for unknown captures
  return "Normal"
end

---Cleanup temporary buffer
---@param bufnr number Buffer number to cleanup
function M.cleanup_temp_buffer(bufnr)
  if M.temp_buffers[bufnr] then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    M.temp_buffers[bufnr] = nil
  end
end

---Clear all caches and cleanup all temporary buffers
function M.clear_cache()
  M.cache = {}
  
  -- Cleanup all temporary buffers
  for bufnr, _ in pairs(M.temp_buffers) do
    M.cleanup_temp_buffer(bufnr)
  end
  M.temp_buffers = {}
end

---Get diagnostic information about treesitter integration
---@return table Diagnostic information
function M.get_diagnostics()
  local has_treesitter, parsers = pcall(require, "nvim-treesitter.parsers")
  local available_parsers = {}
  
  if has_treesitter then
    for lang, _ in pairs(parsers.get_parser_configs()) do
      if parsers.has_parser(lang) then
        table.insert(available_parsers, lang)
      end
    end
  end
  
  -- Calculate cache hit rate
  local total_requests = M.cache_stats.hits + M.cache_stats.misses
  local hit_rate = total_requests > 0 and (M.cache_stats.hits / total_requests * 100) or 0
  
  -- Calculate cache memory usage estimate
  local cache_memory = 0
  for _, entry in pairs(M.cache) do
    if entry.size then
      cache_memory = cache_memory + entry.size
    end
  end
  
  return {
    treesitter_available = has_treesitter,
    available_parsers = available_parsers,
    cache = {
      size = vim.tbl_count(M.cache),
      max_size = CACHE_MAX_SIZE,
      ttl_seconds = CACHE_TTL,
      hit_rate = string.format("%.1f%%", hit_rate),
      stats = M.cache_stats,
      estimated_memory_usage = cache_memory,
    },
    temp_buffers_count = vim.tbl_count(M.temp_buffers),
    namespace_id = M.ns_id,
  }
end

return M