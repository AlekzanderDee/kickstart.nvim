-- Scratch buffers in /tmp for ad-hoc payload inspection.
--
-- Each keymap opens (or creates) a single well-known file. `:edit` on a
-- non-existent path opens an empty buffer pointing at that path; the file
-- is materialised on disk the first time you `:w`.

local map = vim.keymap.set

local function open_scratch(path)
  return function() vim.cmd.edit(path) end
end

map('n', '<leader>jj', open_scratch('/tmp/just.json'), { desc = '[J]ust scratch: [J]SON (/tmp/just.json)' })
map('n', '<leader>jx', open_scratch('/tmp/just.xml'),  { desc = '[J]ust scratch: [X]ML  (/tmp/just.xml)' })
map('n', '<leader>jf', open_scratch('/tmp/just.txt'),  { desc = '[J]ust scratch: [F]ile (/tmp/just.txt)' })
