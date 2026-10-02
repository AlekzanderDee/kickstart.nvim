vim.pack.add { 'https://github.com/akinsho/toggleterm.nvim' }

require('toggleterm').setup {
  open_mapping = [[<c-\>]], -- quick float toggle (unchanged)
  direction = 'float',
  float_opts = { border = 'rounded' },
  size = function(term)
    if term.direction == 'horizontal' then
      return 15
    end
  end,
}

-- Toggle the overlay (float) terminal; pressing again hides/closes it.
-- Shares the default terminal (count 1) with the <C-\> mapping above.
vim.keymap.set('n', '<leader>tto', '<Cmd>ToggleTerm direction=float<CR>',
  { desc = '[T]erminal [T]oggle [O]verlay (float)' })

-- Toggle an independent horizontal split terminal (count 2); pressing again hides/closes it.
vim.keymap.set('n', '<leader>tth', '<Cmd>2ToggleTerm direction=horizontal<CR>',
  { desc = '[T]erminal [T]oggle [H]orizontal' })
