-- Copy the current buffer's path to the clipboard — no plugins, just vim.fn.
-- Auto-loaded at startup by lua/custom/plugins/init.lua.
--
-- Usage:
--   <leader>cp  → path relative to the current working directory (:pwd)
--   <leader>cr  → path relative to the git repo root (portable across polyrepos)
--   :CopyPath          → same as <leader>cp
--   :CopyPathFromRoot  → same as <leader>cr
--
-- cwd-relative uses the ':.' filename modifier; root-relative asks git for the
-- toplevel of the file's own directory, so it works regardless of :pwd.

local function abs_path()
  local abs = vim.fn.expand '%:p'
  if abs == '' then
    vim.notify('CopyPath: no file in buffer', vim.log.levels.WARN)
    return nil
  end
  return abs
end

local function copy(path)
  vim.fn.setreg('+', path)
  vim.notify('Copied: ' .. path)
end

-- Path relative to Neovim's current working directory.
local function cwd_relative()
  local abs = abs_path()
  return abs and vim.fn.fnamemodify(abs, ':.') or nil
end

-- Path relative to the git repo that owns the file.
local function root_relative()
  local abs = abs_path()
  if not abs then
    return nil
  end
  local dir = vim.fn.fnamemodify(abs, ':h')
  local out = vim.fn.system { 'git', '-C', dir, 'rev-parse', '--show-toplevel' }
  if vim.v.shell_error ~= 0 then
    vim.notify('CopyPath: not inside a git repo', vim.log.levels.WARN)
    return nil
  end
  local root = vim.trim(out)
  return abs:sub(#root + 2) -- strip "root/"
end

vim.api.nvim_create_user_command('CopyPath', function()
  local p = cwd_relative()
  if p then
    copy(p)
  end
end, { desc = 'Copy buffer path (relative to cwd) to clipboard' })

vim.api.nvim_create_user_command('CopyPathFromRoot', function()
  local p = root_relative()
  if p then
    copy(p)
  end
end, { desc = 'Copy buffer path (relative to git root) to clipboard' })

vim.keymap.set('n', '<leader>cp', '<cmd>CopyPath<CR>', { desc = 'Copy relative [P]ath (cwd)', silent = true })
vim.keymap.set('n', '<leader>cr', '<cmd>CopyPathFromRoot<CR>', { desc = 'Copy path from git [R]oot', silent = true })
