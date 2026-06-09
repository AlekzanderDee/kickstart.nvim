-- Treesitter-based code folding.
--
-- Kept as a custom plugin so updates to upstream init.lua don't conflict with
-- our fold preferences. Loaded automatically by `custom/plugins/init.lua`.

-- Compute folds from the buffer's treesitter tree. For buffers without an
-- active treesitter parser, `vim.treesitter.foldexpr` returns "0" (no fold),
-- so setting this globally is safe.
vim.opt.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
vim.opt.foldmethod = 'expr'

-- Open files with every fold expanded by default. Fold on demand with `zc`
-- (close one) / `zM` (close all). Without this, treesitter folding starts
-- everything collapsed, which is jarring on file open.
vim.o.foldlevelstart = 99

-- Drop the "···············" padding on the line a fold collapses to.
-- `:append` preserves any other fillchars set elsewhere in the config.
vim.opt.fillchars:append { fold = ' ' }
