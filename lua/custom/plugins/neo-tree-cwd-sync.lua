-- Sync Neovim's global cwd with neo-tree's displayed root.
--
-- Why: neo-tree by default only updates its own view when you navigate
-- (`.` = set as root, `<BS>` = up, `:Neotree dir=…`). Telescope and any
-- other tool that reads the OS cwd (`vim.uv.cwd()`) doesn't see those
-- changes, so file/grep searches stay anchored to the directory you
-- launched nvim from. This module reads neo-tree's filesystem-source
-- state after every render and runs `:cd` whenever the displayed root
-- differs from the OS cwd.

local DEBUG = false -- flip to true to see what fires

local function dbg(...)
  if DEBUG then vim.notify('[neo-tree-cwd-sync] ' .. table.concat({ ... }, ' '), vim.log.levels.INFO) end
end

local function sync()
  local ok_mgr, manager = pcall(require, 'neo-tree.sources.manager')
  if not ok_mgr then
    dbg('manager not available')
    return
  end
  local ok_state, state = pcall(manager.get_state, 'filesystem')
  if not ok_state or not state or not state.path then
    dbg('no filesystem state or state.path')
    return
  end
  local target = vim.fs.normalize(state.path)
  if vim.fn.isdirectory(target) ~= 1 then
    dbg('not a directory:', target)
    return
  end
  local current = vim.fs.normalize(vim.uv.cwd() or '')
  if current == target then
    dbg('already in sync:', current)
    return
  end
  dbg('cd from', current, 'to', target)
  vim.cmd('cd ' .. vim.fn.fnameescape(target))
end

local function register()
  local ok, events = pcall(require, 'neo-tree.events')
  if not ok then return false end
  events.subscribe { event = events.AFTER_RENDER, handler = sync }
  return true
end

if not register() then vim.schedule(register) end
