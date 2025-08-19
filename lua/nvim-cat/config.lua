---@class NvimCatConfig
---@field show_line_numbers boolean
---@field show_git_status boolean
---@field paging NvimCatPagingConfig
---@field theme string
---@field colorscheme string|nil
---@field filetype_mappings table<string, string>

---@class NvimCatPagingConfig
---@field enabled boolean
---@field lines_per_page number

local M = {}

---@type NvimCatConfig
M.defaults = {
  show_line_numbers = true,
  show_git_status = false,
  
  paging = {
    enabled = true,
    lines_per_page = 50
  },
  
  theme = "auto",
  colorscheme = nil, -- Auto-detect user's colorscheme
  use_global_background = true, -- Use Normal background for entire output
  
  filetype_mappings = {
    [".conf"] = "config",
    [".env"] = "sh",
    [".zshrc"] = "sh",
    [".bashrc"] = "sh",
    [".vimrc"] = "vim",
    [".gitignore"] = "gitignore",
    [".gitconfig"] = "gitconfig",
    ["Dockerfile"] = "dockerfile",
    ["docker-compose.yml"] = "yaml",
    ["docker-compose.yaml"] = "yaml",
  }
}

---@type NvimCatConfig
M.config = {}

---Initialize configuration with user options
---@param opts? NvimCatConfig User configuration options
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.defaults, opts or {})
  
  -- Validate configuration
  M.validate()
end

---Validate configuration values
function M.validate()
  local config = M.config
  
  -- Validate theme
  if config.theme ~= "auto" and config.theme ~= "dark" and config.theme ~= "light" then
    -- Check if it's a valid colorscheme name
    local available_colorschemes = vim.fn.getcompletion("", "color")
    local is_valid_theme = false
    for _, scheme in ipairs(available_colorschemes) do
      if scheme == config.theme then
        is_valid_theme = true
        break
      end
    end
    
    if not is_valid_theme then
      vim.notify(
        string.format("Invalid theme '%s', falling back to 'auto'", config.theme),
        vim.log.levels.WARN
      )
      config.theme = "auto"
    end
  end
  
  -- Validate paging
  if config.paging.lines_per_page <= 0 then
    vim.notify(
      "lines_per_page must be positive, setting to default (50)",
      vim.log.levels.WARN
    )
    config.paging.lines_per_page = 50
  end
end

---Get current configuration
---@return NvimCatConfig
function M.get()
  return M.config
end

---Get a specific configuration value
---@param key string Configuration key (supports dot notation)
---@return any
function M.get_option(key)
  local keys = vim.split(key, ".", { plain = true })
  local value = M.config
  
  for _, k in ipairs(keys) do
    if type(value) == "table" and value[k] ~= nil then
      value = value[k]
    else
      return nil
    end
  end
  
  return value
end

---Set a specific configuration value
---@param key string Configuration key (supports dot notation)
---@param value any Value to set
function M.set_option(key, value)
  local keys = vim.split(key, ".", { plain = true })
  local config = M.config
  
  for i = 1, #keys - 1 do
    local k = keys[i]
    if type(config[k]) ~= "table" then
      config[k] = {}
    end
    config = config[k]
  end
  
  config[keys[#keys]] = value
end

return M