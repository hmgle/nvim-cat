---@class CacheManager
---@field caches table<string, table> All managed caches
---@field stats table Cache performance statistics

local M = {}

-- Global cache management
M.caches = {}
M.stats = {
  total_hits = 0,
  total_misses = 0,
  total_evictions = 0,
  cache_count = 0
}

-- Cache configuration
local DEFAULT_MAX_SIZE = 1000
local DEFAULT_TTL = 300 -- 5 minutes
local CLEANUP_INTERVAL = 60 -- Cleanup every minute
local MEMORY_PRESSURE_THRESHOLD = 0.8 -- Start aggressive cleanup at 80% capacity

---Create a new managed cache
---@param name string Cache identifier
---@param max_size? number Maximum cache entries (default: 1000)
---@param ttl? number Time to live in seconds (default: 300)
---@return table Cache instance
function M.create_cache(name, max_size, ttl)
  max_size = max_size or DEFAULT_MAX_SIZE
  ttl = ttl or DEFAULT_TTL
  
  local cache = {
    name = name,
    data = {},
    stats = { hits = 0, misses = 0, evictions = 0 },
    max_size = max_size,
    ttl = ttl,
    last_cleanup = os.time(),
  }
  
  M.caches[name] = cache
  M.stats.cache_count = M.stats.cache_count + 1
  
  return cache
end

---Get cache entry with automatic cleanup
---@param cache table Cache instance
---@param key string Cache key
---@return any|nil Cached value or nil if not found/expired
function M.get(cache, key)
  -- Periodic cleanup
  local now = os.time()
  if now - cache.last_cleanup > CLEANUP_INTERVAL then
    M.cleanup_cache(cache)
    cache.last_cleanup = now
  end
  
  local entry = cache.data[key]
  if not entry then
    cache.stats.misses = cache.stats.misses + 1
    M.stats.total_misses = M.stats.total_misses + 1
    return nil
  end
  
  -- Check TTL
  if now - entry.timestamp > cache.ttl then
    cache.data[key] = nil
    cache.stats.misses = cache.stats.misses + 1
    M.stats.total_misses = M.stats.total_misses + 1
    return nil
  end
  
  -- Update access time for LRU
  entry.last_access = now
  cache.stats.hits = cache.stats.hits + 1
  M.stats.total_hits = M.stats.total_hits + 1
  
  return entry.value
end

---Set cache entry with intelligent eviction
---@param cache table Cache instance
---@param key string Cache key
---@param value any Value to cache
---@param size? number Estimated memory size of entry
function M.set(cache, key, value, size)
  local now = os.time()
  
  -- Check if we need to make space
  local current_size = vim.tbl_count(cache.data)
  if current_size >= cache.max_size then
    M.evict_entries(cache, math.floor(cache.max_size * 0.2)) -- Evict 20%
  end
  
  cache.data[key] = {
    value = value,
    timestamp = now,
    last_access = now,
    size = size or 1,
  }
end

---Intelligent cache eviction using LRU + TTL
---@param cache table Cache instance
---@param count number Number of entries to evict
function M.evict_entries(cache, count)
  local entries = {}
  local now = os.time()
  
  -- Collect entries with metadata
  for key, entry in pairs(cache.data) do
    table.insert(entries, {
      key = key,
      entry = entry,
      age = now - entry.timestamp,
      last_access_age = now - entry.last_access,
      expired = (now - entry.timestamp) > cache.ttl,
    })
  end
  
  -- Sort by eviction priority: expired first, then LRU
  table.sort(entries, function(a, b)
    if a.expired ~= b.expired then
      return a.expired -- Expired entries first
    end
    return a.last_access_age > b.last_access_age -- Then LRU
  end)
  
  -- Evict entries
  local evicted = 0
  for i = 1, math.min(count, #entries) do
    cache.data[entries[i].key] = nil
    evicted = evicted + 1
  end
  
  cache.stats.evictions = cache.stats.evictions + evicted
  M.stats.total_evictions = M.stats.total_evictions + evicted
end

---Clean up expired entries in cache
---@param cache table Cache instance
function M.cleanup_cache(cache)
  local now = os.time()
  local expired_keys = {}
  
  for key, entry in pairs(cache.data) do
    if now - entry.timestamp > cache.ttl then
      table.insert(expired_keys, key)
    end
  end
  
  for _, key in ipairs(expired_keys) do
    cache.data[key] = nil
  end
  
  if #expired_keys > 0 then
    cache.stats.evictions = cache.stats.evictions + #expired_keys
    M.stats.total_evictions = M.stats.total_evictions + #expired_keys
  end
end

---Clear all caches
function M.clear_all_caches()
  for _, cache in pairs(M.caches) do
    cache.data = {}
    cache.stats = { hits = 0, misses = 0, evictions = 0 }
  end
  
  M.stats = {
    total_hits = 0,
    total_misses = 0,
    total_evictions = 0,
    cache_count = vim.tbl_count(M.caches)
  }
end

---Get comprehensive cache diagnostics
---@return table Diagnostic information
function M.get_diagnostics()
  local total_entries = 0
  local total_memory = 0
  local cache_details = {}
  
  for name, cache in pairs(M.caches) do
    local entries = vim.tbl_count(cache.data)
    local memory = 0
    
    for _, entry in pairs(cache.data) do
      memory = memory + (entry.size or 1)
    end
    
    total_entries = total_entries + entries
    total_memory = total_memory + memory
    
    local hit_rate = 0
    local total_requests = cache.stats.hits + cache.stats.misses
    if total_requests > 0 then
      hit_rate = cache.stats.hits / total_requests * 100
    end
    
    cache_details[name] = {
      entries = entries,
      max_size = cache.max_size,
      utilization = string.format("%.1f%%", entries / cache.max_size * 100),
      hit_rate = string.format("%.1f%%", hit_rate),
      stats = cache.stats,
      estimated_memory = memory,
      ttl_seconds = cache.ttl,
    }
  end
  
  -- Calculate global hit rate
  local global_total = M.stats.total_hits + M.stats.total_misses
  local global_hit_rate = global_total > 0 and (M.stats.total_hits / global_total * 100) or 0
  
  return {
    global_stats = {
      total_caches = M.stats.cache_count,
      total_entries = total_entries,
      total_memory_estimate = total_memory,
      global_hit_rate = string.format("%.1f%%", global_hit_rate),
      stats = M.stats,
    },
    caches = cache_details,
    memory_pressure = total_entries > (DEFAULT_MAX_SIZE * M.stats.cache_count * MEMORY_PRESSURE_THRESHOLD),
  }
end

---Start automatic cache maintenance
function M.start_maintenance()
  -- This would be called periodically in a real implementation
  -- For now, it's just a placeholder for future automatic cleanup
  for _, cache in pairs(M.caches) do
    M.cleanup_cache(cache)
  end
end

return M