vim.opt.wrap = false

-- better movement in wrapped text
vim.keymap.set('n', 'j', function() return vim.v.count == 0 and 'gj' or 'j' end, { expr = true, silent = true, desc = 'Down (wrap-aware)' })
vim.keymap.set('n', 'k', function() return vim.v.count == 0 and 'gk' or 'k' end, { expr = true, silent = true, desc = 'Up (wrap-aware)' })

-- Re-enable wrapping for files where horizontal scrolling is painful
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'json', 'xml', 'text', 'markdown' },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true -- break at word/space boundaries, not mid-word
    vim.opt_local.breakindent = true -- preserve indentation on continuation lines
  end,
})
