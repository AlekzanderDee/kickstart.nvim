vim.pack.add { 'https://github.com/akinsho/toggleterm.nvim' }
require('toggleterm').setup {
  open_mapping = [[<c-\>]], -- one key to toggle (try Ctrl-\)
  direction = 'float',
  float_opts = { border = 'rounded' },
}
