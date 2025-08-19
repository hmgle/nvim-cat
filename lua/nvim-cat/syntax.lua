---@class SyntaxEngine
---@field cache table<string, table> Cache for syntax highlighting results

local M = {}
local cache_manager = require("nvim-cat.cache")

-- Initialize managed cache
M.cache = cache_manager.create_cache("syntax", 1000, 300)

---Apply traditional Vim syntax highlighting to lines
---@param lines string[] File lines
---@param filetype string File type
---@return string[] Highlighted lines
function M.apply_vim_syntax_highlighting(lines, filetype)
  if not lines or #lines == 0 then
    return lines
  end
  
  -- Check managed cache first
  local cache_key = filetype .. ":" .. vim.fn.sha256(table.concat(lines, "\n"))
  local cached_result = cache_manager.get(M.cache, cache_key)
  
  if cached_result then
    return cached_result
  end
  
  -- Create temporary buffer for syntax highlighting
  local bufnr = vim.api.nvim_create_buf(false, true)
  if not bufnr or bufnr == 0 then
    return lines
  end
  
  local highlighted_lines = {}
  
  -- Set up buffer for syntax highlighting
  local success = pcall(function()
    -- Set buffer contents
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    
    -- Set filetype to trigger syntax highlighting
    vim.api.nvim_buf_set_option(bufnr, 'filetype', filetype)
    
    -- Enable syntax highlighting properly in headless mode
    vim.api.nvim_buf_call(bufnr, function()
      -- Ensure syntax is enabled globally
      vim.cmd("syntax enable")
      vim.cmd("syntax on")
      
      -- Force load syntax for the specific filetype
      if filetype and filetype ~= "" then
        pcall(vim.cmd, "runtime syntax/" .. filetype .. ".vim")
      end
    end)
    
    -- Wait a moment for syntax to be applied
    vim.cmd("redraw")
    
    -- Verify syntax is working by checking a sample position
    local syntax_working = false
    if #lines > 0 and #lines[1] > 0 then
      local test_syn_id = vim.fn.synID(1, 1, 1)
      local test_syn_name = vim.fn.synIDattr(test_syn_id, "name")
      syntax_working = (test_syn_name and test_syn_name ~= "")
    end
    
    -- If syntax isn't working, fall back to simple highlighting
    if not syntax_working then
      return nil -- Will trigger fallback to simple highlighting
    end
    
    -- Extract syntax highlighting information
    for i, line in ipairs(lines) do
      local highlighted_line = M.extract_syntax_highlights(bufnr, i - 1, line)
      table.insert(highlighted_lines, highlighted_line)
    end
  end)
  
  -- Cleanup
  pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  
  if not success or not highlighted_lines or #highlighted_lines == 0 then
    -- If syntax highlighting failed, return nil to trigger fallback
    return nil
  end
  
  -- Cache result using managed cache
  cache_manager.set(M.cache, cache_key, highlighted_lines, #highlighted_lines)
  
  return highlighted_lines
end

---Extract syntax highlighting from a line in a buffer
---@param bufnr number Buffer number
---@param line_idx number 0-indexed line number
---@param line string Original line content
---@return string Highlighted line
function M.extract_syntax_highlights(bufnr, line_idx, line)
  if not line or line == "" then
    return line
  end
  
  local output = require("nvim-cat.output")
  local result = ""
  local line_length = #line
  
  -- Optimized syntax highlighting using range detection
  local highlights = {}
  local processed_cols = {}
  
  -- Sample at word boundaries and syntax changes for better performance
  local sample_positions = M.get_sample_positions(line, line_length)
  
  for _, col in ipairs(sample_positions) do
    if not processed_cols[col] then
      local syn_id = vim.fn.synID(line_idx + 1, col + 1, 1)
      local syn_name = vim.fn.synIDattr(syn_id, "name")
      
      if syn_name and syn_name ~= "" then
        -- Use binary search to find syntax range boundaries
        local start_col, end_col = M.find_syntax_range(line_idx, col, syn_name, line_length)
        
        -- Mark all columns in this range as processed
        for c = start_col, end_col do
          processed_cols[c] = true
        end
        
        table.insert(highlights, {
          start_col = start_col,
          end_col = end_col,
          syn_name = syn_name,
        })
      end
    end
  end
  
  -- Remove duplicates and sort
  highlights = M.deduplicate_highlights(highlights)
  table.sort(highlights, function(a, b)
    return a.start_col < b.start_col
  end)
  
  -- Apply highlights
  local last_col = 0
  
  for _, hl in ipairs(highlights) do
    -- Add text before highlight
    if hl.start_col > last_col then
      result = result .. line:sub(last_col + 1, hl.start_col)
    end
    
    -- Add highlighted text
    local text = line:sub(hl.start_col + 1, hl.end_col + 1)
    local highlight_group = M.map_syntax_to_highlight_group(hl.syn_name)
    result = result .. output.format_token(text, highlight_group)
    
    last_col = hl.end_col + 1
  end
  
  -- Add remaining text
  if last_col < line_length then
    result = result .. line:sub(last_col + 1)
  end
  
  return result
end

---Remove duplicate highlights and merge overlapping ones
---@param highlights table[] Array of highlight information
---@return table[] Deduplicated highlights
function M.deduplicate_highlights(highlights)
  if not highlights or #highlights <= 1 then
    return highlights or {}
  end
  
  local deduplicated = {}
  local seen = {}
  
  for _, hl in ipairs(highlights) do
    local key = string.format("%d-%d-%s", hl.start_col, hl.end_col, hl.syn_name)
    if not seen[key] then
      table.insert(deduplicated, hl)
      seen[key] = true
    end
  end
  
  return deduplicated
end

---Get optimized sample positions for syntax analysis
---@param line string Line content
---@param line_length number Length of line
---@return number[] Sample positions
function M.get_sample_positions(line, line_length)
  local positions = {}
  
  -- Always sample first and last positions
  table.insert(positions, 0)
  if line_length > 1 then
    table.insert(positions, line_length - 1)
  end
  
  -- Sample at word boundaries and common syntax delimiters
  local delimiters = "[%s%p]"
  local pos = 1
  while pos <= line_length do
    local start_pos, end_pos = line:find("%S+", pos)
    if not start_pos then break end
    
    -- Add word start and end positions
    if start_pos > 1 then
      table.insert(positions, start_pos - 2) -- 0-indexed
    end
    table.insert(positions, start_pos - 1) -- 0-indexed
    table.insert(positions, end_pos - 1) -- 0-indexed
    
    pos = end_pos + 1
  end
  
  -- Remove duplicates and sort
  local unique_positions = {}
  local seen = {}
  for _, p in ipairs(positions) do
    if p >= 0 and p < line_length and not seen[p] then
      table.insert(unique_positions, p)
      seen[p] = true
    end
  end
  
  table.sort(unique_positions)
  return unique_positions
end

---Find syntax range using binary search for efficiency
---@param line_idx number 0-indexed line number
---@param col number Starting column (0-indexed)
---@param syn_name string Syntax name to match
---@param line_length number Total line length
---@return number, number start_col, end_col (0-indexed)
function M.find_syntax_range(line_idx, col, syn_name, line_length)
  -- Binary search for start boundary
  local start_col = col
  local left, right = 0, col
  while left < right do
    local mid = math.floor((left + right) / 2)
    local mid_syn_id = vim.fn.synID(line_idx + 1, mid + 1, 1)
    local mid_syn_name = vim.fn.synIDattr(mid_syn_id, "name")
    if mid_syn_name == syn_name then
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
    local mid_syn_id = vim.fn.synID(line_idx + 1, mid + 1, 1)
    local mid_syn_name = vim.fn.synIDattr(mid_syn_id, "name")
    if mid_syn_name == syn_name then
      left = mid
    else
      right = mid - 1
    end
  end
  end_col = left
  
  return start_col, end_col
end

---Map Vim syntax name to standard highlight group
---@param syn_name string Vim syntax name
---@return string Standard highlight group name
function M.map_syntax_to_highlight_group(syn_name)
  -- Direct mappings for common syntax names
  local direct_map = {
    -- Comments
    ["Comment"] = "Comment",
    ["SpecialComment"] = "SpecialComment",
    ["Todo"] = "Todo",
    
    -- Constants
    ["Constant"] = "Constant",
    ["String"] = "String",
    ["Character"] = "Character",
    ["Number"] = "Number",
    ["Boolean"] = "Boolean",
    ["Float"] = "Float",
    
    -- Identifiers
    ["Identifier"] = "Identifier",
    ["Function"] = "Function",
    
    -- Statements
    ["Statement"] = "Statement",
    ["Conditional"] = "Conditional",
    ["Repeat"] = "Repeat",
    ["Label"] = "Label",
    ["Operator"] = "Operator",
    ["Keyword"] = "Keyword",
    ["Exception"] = "Exception",
    
    -- PreProcessor
    ["PreProc"] = "PreProc",
    ["Include"] = "Include",
    ["Define"] = "Define",
    ["Macro"] = "Macro",
    ["PreCondit"] = "PreCondit",
    
    -- Type
    ["Type"] = "Type",
    ["StorageClass"] = "StorageClass",
    ["Structure"] = "Structure",
    ["Typedef"] = "Typedef",
    
    -- Special
    ["Special"] = "Special",
    ["SpecialChar"] = "SpecialChar",
    ["Tag"] = "Tag",
    ["Delimiter"] = "Delimiter",
    ["Debug"] = "Debug",
    
    -- Other
    ["Underlined"] = "Underlined",
    ["Ignore"] = "Ignore",
    ["Error"] = "Error",
  }
  
  -- Try direct mapping first
  if direct_map[syn_name] then
    return direct_map[syn_name]
  end
  
  -- Language-specific syntax name patterns
  local pattern_map = {
    -- Lua
    ["lua%w*Comment"] = "Comment",
    ["lua%w*String"] = "String",
    ["lua%w*Number"] = "Number",
    ["lua%w*Function"] = "Function",
    ["lua%w*Keyword"] = "Keyword",
    ["lua%w*Operator"] = "Operator",
    ["lua%w*Constant"] = "Constant",
    
    -- JavaScript/TypeScript
    ["javascript%w*Comment"] = "Comment",
    ["javascript%w*String"] = "String",
    ["javascript%w*Number"] = "Number",
    ["javascript%w*Function"] = "Function",
    ["javascript%w*Keyword"] = "Keyword",
    ["typescript%w*Comment"] = "Comment",
    ["typescript%w*String"] = "String",
    ["typescript%w*Type"] = "Type",
    
    -- Python
    ["python%w*Comment"] = "Comment",
    ["python%w*String"] = "String",
    ["python%w*Number"] = "Number",
    ["python%w*Function"] = "Function",
    ["python%w*Keyword"] = "Keyword",
    ["python%w*Builtin"] = "Function",
    
    -- Shell
    ["sh%w*Comment"] = "Comment",
    ["sh%w*String"] = "String",
    ["sh%w*Variable"] = "Identifier",
    ["sh%w*Function"] = "Function",
    ["sh%w*Keyword"] = "Keyword",
    
    -- C/C++
    ["c%w*Comment"] = "Comment",
    ["c%w*String"] = "String",
    ["c%w*Number"] = "Number",
    ["c%w*Type"] = "Type",
    ["c%w*Structure"] = "Structure",
    ["c%w*Keyword"] = "Keyword",
    ["cpp%w*Comment"] = "Comment",
    ["cpp%w*String"] = "String",
    ["cpp%w*Type"] = "Type",
    
    -- Generic patterns
    ["%w*Comment"] = "Comment",
    ["%w*String"] = "String", 
    ["%w*Number"] = "Number",
    ["%w*Function"] = "Function",
    ["%w*Keyword"] = "Keyword",
    ["%w*Type"] = "Type",
    ["%w*Constant"] = "Constant",
    ["%w*Operator"] = "Operator",
    ["%w*Identifier"] = "Identifier",
  }
  
  -- Try pattern matching
  for pattern, group in pairs(pattern_map) do
    if syn_name:match(pattern) then
      return group
    end
  end
  
  -- Fallback based on common naming conventions
  local lower_name = syn_name:lower()
  
  if lower_name:match("comment") then return "Comment"
  elseif lower_name:match("string") then return "String"
  elseif lower_name:match("number") or lower_name:match("digit") then return "Number"
  elseif lower_name:match("function") or lower_name:match("method") then return "Function"
  elseif lower_name:match("keyword") or lower_name:match("reserved") then return "Keyword"
  elseif lower_name:match("type") or lower_name:match("class") then return "Type"
  elseif lower_name:match("constant") or lower_name:match("const") then return "Constant"
  elseif lower_name:match("operator") then return "Operator"
  elseif lower_name:match("identifier") or lower_name:match("variable") then return "Identifier"
  elseif lower_name:match("preproc") or lower_name:match("include") then return "PreProc"
  elseif lower_name:match("special") then return "Special"
  elseif lower_name:match("error") then return "Error"
  elseif lower_name:match("todo") then return "Todo"
  end
  
  -- Ultimate fallback
  return "Normal"
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

---Clear syntax highlighting cache
function M.clear_cache()
  M.cache = {}
  M.cache_stats = { hits = 0, misses = 0, evictions = 0 }
end

---Get diagnostic information about syntax engine
---@return table Diagnostic information
function M.get_diagnostics()
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
    syntax_available = vim.fn.exists(":syntax") == 2,
    cache = {
      size = vim.tbl_count(M.cache),
      max_size = CACHE_MAX_SIZE,
      ttl_seconds = CACHE_TTL,
      hit_rate = string.format("%.1f%%", hit_rate),
      stats = M.cache_stats,
      estimated_memory_usage = cache_memory,
    },
  }
end

return M