-- nvim-cat plugin initialization
-- This file is loaded automatically when Neovim starts

-- Prevent loading if already loaded
if vim.g.loaded_nvim_cat then
  return
end
vim.g.loaded_nvim_cat = 1

-- Check Neovim version requirement
if vim.fn.has('nvim-0.9') == 0 then
  vim.api.nvim_err_writeln('nvim-cat requires Neovim 0.9 or later')
  return
end

-- Create the main command
vim.api.nvim_create_user_command('NvimCat', function(args)
  local nvim_cat = require('nvim-cat')
  
  if args.args == '' then
    print(nvim_cat.help())
    return
  end
  
  local pattern = args.args
  
  -- Parse any options from the command line
  local opts = {}
  
  -- Check for flags in the pattern
  if pattern:match('^%-%-help') or pattern:match('^%-h') then
    print(nvim_cat.help())
    return
  end
  
  if pattern:match('^%-%-version') or pattern:match('^%-v') then
    print(nvim_cat.version())
    return
  end
  
  -- Extract options and clean pattern
  local clean_pattern = pattern
  
  -- Simple flag parsing (can be enhanced later)
  if pattern:match('%-%-no%-line%-numbers') then
    opts.show_line_numbers = false
    clean_pattern = pattern:gsub('%s*%-%-no%-line%-numbers%s*', ' '):gsub('^%s*', ''):gsub('%s*$', '')
  end
  
  if pattern:match('%-%-no%-paging') then
    opts.paging = false
    clean_pattern = pattern:gsub('%s*%-%-no%-paging%s*', ' '):gsub('^%s*', ''):gsub('%s*$', '')
  end
  
  -- Call the main cat function
  nvim_cat.cat(clean_pattern, opts)
end, {
  nargs = '*',
  complete = 'file',
  desc = 'Display file(s) with syntax highlighting'
})

-- Create completion for NvimCat command
vim.api.nvim_create_autocmd('CmdlineEnter', {
  pattern = '*',
  callback = function()
    -- This could be enhanced to provide better completion
    -- Currently uses built-in file completion
  end
})

-- Optional: Create some convenience commands
vim.api.nvim_create_user_command('NvimCatHelp', function()
  local nvim_cat = require('nvim-cat')
  print(nvim_cat.help())
end, {
  desc = 'Show nvim-cat help'
})

vim.api.nvim_create_user_command('NvimCatVersion', function()
  local nvim_cat = require('nvim-cat')
  print(nvim_cat.version())
end, {
  desc = 'Show nvim-cat version'
})

-- Set up default configuration
-- Users can override this by calling require('nvim-cat').setup() in their config
require('nvim-cat.config').setup()