-- ============================================================================
-- autoread.lua — auto-reload open buffers when files change on disk
-- ============================================================================
--
-- WHY THIS FILE EXISTS
--   `vim.opt.autoread = true` is already set in init.lua, but autoread only
--   reloads a buffer when Neovim actually *notices* the file's mtime changed.
--   Neovim only re-checks that mtime on a handful of triggers (essentially
--   `:checktime` and a raw terminal focus event). So after you switch git
--   branches in another terminal, an already-open buffer keeps showing the OLD
--   contents until something forces a check — which is exactly why alt-tabbing
--   away and back "fixed" it earlier (that fired FocusGained).
--
--   This file wires `:checktime` to the everyday events where a stale buffer is
--   most annoying, so the reload happens automatically without alt-tabbing.
--
-- PERFORMANCE
--   `:checktime` is a single stat() syscall per loaded buffer to compare
--   mtimes, and only triggers a reload when the file genuinely changed. It is
--   microsecond-scale and purely event-driven (NOT a polling loop), so it has
--   no measurable effect on typing latency. It does not block the main loop and
--   is unrelated to any keymap-timeout / input-lag behaviour.
--
-- MERGE / CONFLICT SAFETY
--   Lives entirely under lua/custom/plugins/ (kickstart's "no merge conflicts"
--   area). It only ADDS autocmds inside its own augroup and never touches
--   init.lua. `vim.opt.autoread` stays exactly as init.lua set it; this file
--   just supplies the missing trigger.

-- Own augroup with clear = true → re-sourcing this file replaces these autocmds
-- instead of stacking duplicates. Can't collide with kickstart's groups.
local group = vim.api.nvim_create_augroup('custom_autoread', { clear = true })

-- Check for on-disk changes on the events where a stale buffer hurts most:
--   FocusGained          — came back to nvim after a git checkout in a terminal
--   BufEnter             — switched to a buffer whose file changed underneath it
--   CursorHold           — idle pause (respects 'updatetime')
--   TermClose/TermLeave  — finished running something (e.g. git) in :terminal
vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter', 'CursorHold', 'TermClose', 'TermLeave' }, {
  group = group,
  desc = 'Reload buffer if its file changed on disk (autoread trigger)',
  callback = function()
    -- Skip while typing a command-line (`:` / `/`) or inside the cmdline-window,
    -- where :checktime can raise E11 or interrupt input.
    if vim.fn.mode() ~= 'c' and vim.fn.getcmdwintype() == '' then
      vim.cmd 'checktime'
    end
  end,
})

-- Optional, quiet heads-up so you know a buffer was swapped out from under you
-- (handy right after a branch switch). Delete this block if it feels noisy —
-- on a branch switch with several buffers open you'll get one message each.
vim.api.nvim_create_autocmd('FileChangedShellPost', {
  group = group,
  desc = 'Notify when a buffer was reloaded from disk',
  callback = function()
    vim.notify('Buffer reloaded — file changed on disk', vim.log.levels.INFO)
  end,
})
