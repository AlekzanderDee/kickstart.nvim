-- Pretty-print JSON / XML for the current buffer or visual selection.
local map = vim.keymap.set

-- <leader>fj  (format JSON) — works in normal & visual
map('n', '<leader>fj', ':%!jq .<CR>', { desc = 'Format JSON (buffer)' })
map('v', '<leader>fj', ':!jq .<CR>', { desc = 'Format JSON (selection)' })

map('n', '<leader>fx', ':%!xmllint --format -<CR>', { desc = 'Format XML (buffer)' })
map('v', '<leader>fx', ':!xmllint --format -<CR>', { desc = 'Format XML (selection)' })

-- Move the visual selection up / down, re-indenting it to the new nesting level.
--   :m '>+1 / :m '<-2  → move the selected block one line down / up
--   gv                 → reselect the moved block
--   =                  → re-indent it via the filetype's indent rules (the
--                        "respect nesting" part — solid for Go/Lua, fine for most)
--   gv                 → reselect again so you can keep pressing J / K to repeat
-- NOTE: this overrides visual-mode J (join lines) and K (hover/keywordprg).
map('v', 'J', ":m '>+1<CR>gv=gv", { desc = 'Move selection down (re-indent)' })
map('v', 'K', ":m '<-2<CR>gv=gv", { desc = 'Move selection up (re-indent)' })
