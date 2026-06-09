-- Custom neo-tree config — replaces kickstart/plugins/neo-tree.lua.
--
-- This file copies the upstream kickstart config verbatim and adds:
--   * `Y` mapping inside neo-tree → prompts to copy any of several path
--     variants (absolute / cwd-relative / home-relative / filename / etc.)
--     to the system clipboard. Adapted from
--     https://github.com/nvim-neo-tree/neo-tree.nvim/discussions/370#discussioncomment-14442475
--     The original snippet uses `snacks.picker.select`; we use `vim.ui.select`
--     (kickstart already routes that through telescope-ui-select).
--
-- The corresponding `require 'kickstart.plugins.neo-tree'` line in init.lua
-- has been commented out so this is the only neo-tree config that runs.

local plugins = {
  { src = 'https://github.com/nvim-neo-tree/neo-tree.nvim', version = vim.version.range '*' },
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/MunifTanjim/nui.nvim',
}

if vim.g.have_nerd_font then
  table.insert(plugins, 'https://github.com/nvim-tree/nvim-web-devicons')
end

vim.pack.add(plugins)

vim.keymap.set('n', '\\', '<Cmd>Neotree reveal<CR>', { desc = 'NeoTree reveal', silent = true })

-- Inline action: copy a chosen flavour of the node's path to clipboard.
local function copy_path_to_clipboard(state)
  local node = state.tree:get_node()
  if not node or not node.id then
    vim.notify('No node selected.', vim.log.levels.WARN)
    return
  end

  if vim.fn.has 'clipboard' == 0 then
    vim.notify('System clipboard is not available.', vim.log.levels.ERROR)
    return
  end

  local filepath = node:get_id()
  local filename = node.name
  local modify = vim.fn.fnamemodify

  local choices = {
    { label = 'Absolute path',              value = filepath },
    { label = 'Path relative to CWD',       value = modify(filepath, ':.') },
    { label = 'Path relative to HOME',      value = modify(filepath, ':~') },
    { label = 'Filename',                   value = filename },
    { label = 'Filename without extension', value = modify(filename, ':r') },
    { label = 'Extension of the filename',  value = modify(filename, ':e') },
  }

  vim.ui.select(choices, {
    prompt = 'Choose to copy to clipboard:',
    format_item = function(item)
      return string.format('%-30s %s', item.label, item.value)
    end,
  }, function(choice)
    if not choice then
      vim.notify('Copy cancelled.', vim.log.levels.INFO)
      return
    end
    vim.fn.setreg('+', choice.value)
    vim.notify('Copied to clipboard: ' .. choice.value)
  end)
end

require('neo-tree').setup {
  filesystem = {
    follow_current_file = {
      enabled = true, -- focus the active file in the tree when it changes
      leave_dirs_open = false, -- close auto-expanded dirs on the way (false = collapse them)
    },
    window = {
      mappings = {
        ['\\'] = 'close_window',
        ['Y'] = copy_path_to_clipboard,
      },
    },
  },
  buffers = {
    follow_current_file = {
      enabled = true,
      leave_dirs_open = false,
    },
  },
}
