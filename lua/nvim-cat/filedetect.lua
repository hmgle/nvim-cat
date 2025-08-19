local config = require("nvim-cat.config")
local utils = require("nvim-cat.utils")

local M = {}

---Detect filetype for a given file
---@param filepath string Path to the file
---@return string|nil Detected filetype
function M.detect_filetype(filepath)
  -- First check custom mappings
  local extension = utils.get_extension(filepath)
  local basename = utils.get_basename(filepath)
  local filename = vim.fn.fnamemodify(filepath, ":t")
  
  local mappings = config.get_option("filetype_mappings") or {}
  
  -- Check exact filename match first
  if mappings[filename] then
    return mappings[filename]
  end
  
  -- Check extension mapping
  if extension ~= "" and mappings[extension] then
    return mappings[extension]
  end
  
  -- Use Neovim's built-in filetype detection
  local bufnr = vim.fn.bufnr(filepath, true)
  if bufnr and bufnr ~= -1 then
    local ft = vim.api.nvim_buf_get_option(bufnr, "filetype")
    if ft and ft ~= "" then
      return ft
    end
  end
  
  -- Fallback to vim.filetype.match
  local detected = vim.filetype.match({ filename = filepath })
  if detected then
    return detected
  end
  
  -- Manual detection for common cases
  return M.manual_detect(filepath, extension, filename)
end

---Manual filetype detection for edge cases
---@param filepath string File path
---@param extension string File extension
---@param filename string Base filename
---@return string|nil Detected filetype
function M.manual_detect(filepath, extension, filename)
  -- Shebang detection
  local first_line = M.get_first_line(filepath)
  if first_line then
    local shebang_ft = M.detect_by_shebang(first_line)
    if shebang_ft then
      return shebang_ft
    end
  end
  
  -- Extension-based detection
  local ext_map = {
    [".js"] = "javascript",
    [".ts"] = "typescript",
    [".jsx"] = "javascriptreact",
    [".tsx"] = "typescriptreact",
    [".py"] = "python",
    [".rb"] = "ruby",
    [".php"] = "php",
    [".go"] = "go",
    [".rs"] = "rust",
    [".c"] = "c",
    [".cpp"] = "cpp",
    [".cc"] = "cpp",
    [".cxx"] = "cpp",
    [".h"] = "c",
    [".hpp"] = "cpp",
    [".java"] = "java",
    [".kt"] = "kotlin",
    [".swift"] = "swift",
    [".cs"] = "cs",
    [".fs"] = "fsharp",
    [".scala"] = "scala",
    [".clj"] = "clojure",
    [".hs"] = "haskell",
    [".ml"] = "ocaml",
    [".lua"] = "lua",
    [".vim"] = "vim",
    [".sh"] = "sh",
    [".bash"] = "bash",
    [".zsh"] = "zsh",
    [".fish"] = "fish",
    [".ps1"] = "ps1",
    [".bat"] = "dosbatch",
    [".cmd"] = "dosbatch",
    [".html"] = "html",
    [".htm"] = "html",
    [".xml"] = "xml",
    [".css"] = "css",
    [".scss"] = "scss",
    [".sass"] = "sass",
    [".less"] = "less",
    [".json"] = "json",
    [".yaml"] = "yaml",
    [".yml"] = "yaml",
    [".toml"] = "toml",
    [".ini"] = "dosini",
    [".cfg"] = "cfg",
    [".conf"] = "conf",
    [".md"] = "markdown",
    [".tex"] = "tex",
    [".sql"] = "sql",
    [".r"] = "r",
    [".R"] = "r",
    [".m"] = "objc",
    [".mm"] = "objcpp",
    [".pl"] = "perl",
    [".pm"] = "perl",
    [".tcl"] = "tcl",
    [".makefile"] = "make",
    [".cmake"] = "cmake",
    [".dockerfile"] = "dockerfile",
  }
  
  if ext_map[extension] then
    return ext_map[extension]
  end
  
  -- Filename-based detection
  local filename_map = {
    ["Makefile"] = "make",
    ["makefile"] = "make",
    ["Dockerfile"] = "dockerfile",
    ["Vagrantfile"] = "ruby",
    ["Rakefile"] = "ruby",
    ["Gemfile"] = "ruby",
    ["CMakeLists.txt"] = "cmake",
    [".gitignore"] = "gitignore",
    [".gitconfig"] = "gitconfig",
    [".bashrc"] = "bash",
    [".bash_profile"] = "bash",
    [".zshrc"] = "zsh",
    [".vimrc"] = "vim",
    [".tmux.conf"] = "tmux",
  }
  
  if filename_map[filename] then
    return filename_map[filename]
  end
  
  return nil
end

---Get the first line of a file for shebang detection
---@param filepath string Path to the file
---@return string|nil First line content
function M.get_first_line(filepath)
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end
  
  local first_line = file:read("*line")
  file:close()
  
  return first_line
end

---Detect filetype by shebang
---@param line string First line of file
---@return string|nil Detected filetype
function M.detect_by_shebang(line)
  if not utils.starts_with(line, "#!") then
    return nil
  end
  
  local shebang_map = {
    ["python"] = "python",
    ["python3"] = "python",
    ["python2"] = "python",
    ["node"] = "javascript",
    ["ruby"] = "ruby",
    ["perl"] = "perl",
    ["php"] = "php",
    ["bash"] = "bash",
    ["sh"] = "sh",
    ["zsh"] = "zsh",
    ["fish"] = "fish",
    ["lua"] = "lua",
    ["env python"] = "python",
    ["env node"] = "javascript",
    ["env ruby"] = "ruby",
    ["env bash"] = "bash",
  }
  
  for pattern, filetype in pairs(shebang_map) do
    if line:find(pattern, 1, true) then
      return filetype
    end
  end
  
  return nil
end

---Check if filetype supports syntax highlighting
---@param filetype string Filetype to check
---@return boolean Whether syntax highlighting is supported
function M.supports_highlighting(filetype)
  if not filetype or filetype == "" then
    return false
  end
  
  -- Check if syntax file exists
  local syntax_files = vim.api.nvim_get_runtime_file("syntax/" .. filetype .. ".vim", false)
  if #syntax_files > 0 then
    return true
  end
  
  -- Check for treesitter parser
  local has_treesitter, parsers = pcall(require, "nvim-treesitter.parsers")
  if has_treesitter and parsers.has_parser(filetype) then
    return true
  end
  
  return false
end

---Get list of available syntax highlighting languages
---@return string[] List of supported languages
function M.get_supported_languages()
  local languages = {}
  
  -- Get syntax files
  local syntax_files = vim.api.nvim_get_runtime_file("syntax/*.vim", true)
  for _, file in ipairs(syntax_files) do
    local name = vim.fn.fnamemodify(file, ":t:r")
    if name ~= "syntax" and name ~= "nosyntax" then
      table.insert(languages, name)
    end
  end
  
  -- Get treesitter parsers
  local has_treesitter, parsers = pcall(require, "nvim-treesitter.parsers")
  if has_treesitter then
    for lang, _ in pairs(parsers.get_parser_configs()) do
      if not vim.tbl_contains(languages, lang) then
        table.insert(languages, lang)
      end
    end
  end
  
  table.sort(languages)
  return languages
end

return M