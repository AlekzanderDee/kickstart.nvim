-- Python LSP setup.
--
-- Two complementary servers attach to every Python buffer:
--   * pyright — types, go-to-definition, find-references, hover, completion,
--               and "undefined variable" / wrong-type style errors.
--   * ruff    — fast linter (PEP 8 / pyflakes / pycodestyle / bugbear etc.),
--               surfaced as LSP diagnostics in real time, plus organize-imports
--               code actions. Formatting via ruff is handled by conform.nvim,
--               not this LSP, so we tell ruff to stay out of formatting.
--
-- Mason install is declared in custom/plugins/mason.lua (ensure_installed),
-- so the binaries appear automatically on a fresh machine.

-- Keep pyright's hover; let ruff own diagnostics it has better insight into
-- (line length, unused imports, etc.). pyright still gives you type errors.
vim.lsp.config('pyright', {
  settings = {
    pyright = {
      -- ruff handles unused imports better than pyright; defer to it.
      disableOrganizeImports = true,
    },
    python = {
      analysis = {
        -- 'openFilesOnly' is faster for huge monorepos.
        -- Switch to 'workspace' if you want diagnostics for files you haven't
        -- opened (slower, more memory).
        diagnosticMode = 'openFilesOnly',
        typeCheckingMode = 'basic', -- 'off' | 'basic' | 'strict'
        autoImportCompletions = true,
        useLibraryCodeForTypes = true,
      },
    },
  },
})

-- Ruff: lint-only. Hover/definition stay with pyright.
-- Project-level config (line length, rule selection, etc.) belongs in
-- pyproject.toml / ruff.toml at the repo root, not here — so no init_options.
vim.lsp.config('ruff', {
  on_attach = function(client)
    -- Avoid duplicate hover popups (pyright handles hover).
    client.server_capabilities.hoverProvider = false
  end,
})

vim.lsp.enable('pyright')
vim.lsp.enable('ruff')
