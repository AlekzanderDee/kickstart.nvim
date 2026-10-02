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
    -- Java (jdtls itself is started by custom/plugins/lsp-java.lua via
    -- nvim-jdtls, NOT via vim.lsp.enable — see that file for why. These three
    -- are just the binaries it needs: the language server plus the DAP +
    -- JUnit bundles that give debugging and test-running in Java buffers.)
    'jdtls',
    'java-debug-adapter',
    'java-test',
    -- Lua
    'lua-language-server',
    'stylua',
    -- Other
    'efm',
    'postgres-language-server',
    'pgformatter', -- SQL formatter (pg_format binary), used by conform for sql
    'prettier',
  },
}
