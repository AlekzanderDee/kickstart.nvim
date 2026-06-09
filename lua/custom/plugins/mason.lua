local function gh(repo) return 'https://github.com/' .. repo end
-- add to plugin list
vim.pack.add { gh 'WhoIsSethDaniel/mason-tool-installer.nvim' }

require('mason-tool-installer').setup {
  ensure_installed = {
    -- Go
    'goimports',
    'goimports-reviser',
    'delve',
    'gopls',
    -- Python
    'pyright', -- types, navigation, errors. Swap to 'basedpyright' for a stricter fork.
    'ruff', -- fast linter + formatter, exposed as LSP for live diagnostics
    -- Lua
    'lua-language-server',
    'stylua',
    -- Other
    'efm',
    'postgres-language-server',
    'prettier',
  },
}
