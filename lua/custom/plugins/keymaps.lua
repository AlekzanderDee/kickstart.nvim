-- Pretty-print JSON / XML for the current buffer or visual selection.
local map = vim.keymap.set

-- <leader>fj  (format JSON) — works in normal & visual
map('n', '<leader>fj', ':%!jq .<CR>', { desc = 'Format JSON (buffer)' })
map('v', '<leader>fj', ':!jq .<CR>', { desc = 'Format JSON (selection)' })

map('n', '<leader>fx', ':%!xmllint --format -<CR>', { desc = 'Format XML (buffer)' })
map('v', '<leader>fx', ':!xmllint --format -<CR>', { desc = 'Format XML (selection)' })
