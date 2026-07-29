-- ============================================================================
-- lsp-go.lua — keep gopls in sync when you switch git branches
-- ============================================================================
--
-- THE PROBLEM THIS SOLVES
--   gopls keeps an in-memory snapshot of the workspace. For OPEN buffers it
--   tracks edits live; for files you have NOT opened it relies on file-watch
--   notifications to learn they changed on disk. When you `git checkout`, dozens
--   of files swap at once, and Neovim's file watcher (libuv fs-events on macOS)
--   can miss that bulk change. Result: gopls keeps the OLD version of, say, a
--   function's signature and reports phantom errors at the call site — until you
--   open the file that defines it (which forces gopls to re-read it). That's the
--   "errors appear after a branch switch, then vanish when I visit the
--   definition" behaviour.
--
-- THE FIX
--   When we detect that git HEAD changed (i.e. a branch switch / pull / rebase)
--   while there's Go code open, restart gopls so it re-reads the new tree from a
--   clean slate. Plus a manual <leader>gr for when you just want to force it.
--
-- WHY WE DON'T TOUCH gopls' LSP CONFIG / CAPABILITIES HERE
--   It's tempting to re-assert the `didChangeWatchedFiles` capability, but on
--   Neovim 0.11+ that capability is already advertised by default, AND adding a
--   `vim.lsp.config('gopls', { capabilities = ... })` here would deep-merge with
--   (and, since a named config wins over the '*' config, potentially OVERRIDE)
--   blink.cmp's completion capabilities. To honour "merge, don't overwrite", we
--   deliberately do NOT redefine gopls. init.lua already does
--   `vim.lsp.config('gopls', {})` + `vim.lsp.enable('gopls')`; we simply *use*
--   that client. This file only adds its own augroup + one keymap.
--
-- PERFORMANCE
--   The detection is a couple of cheap file reads (.git/HEAD and the ref it
--   points at) when you return to your code (see the autocmd events below) —
--   no spawned git process, no polling loop, no main-loop blocking. If HEAD is
--   unchanged it's just those reads and a cached compare; nothing else runs.
--   The only heavy action, a gopls restart (re-index), runs
--   ONLY when HEAD actually changed and a Go buffer is open. If even that feels
--   too heavy on this monorepo, set AUTO_RESTART = false below and rely on the
--   manual <leader>gr instead.

local AUTO_RESTART = true -- false → detect nothing automatically; use <leader>gr only

-- ---------------------------------------------------------------------------
-- Restart gopls and re-attach it to its buffers.
-- ---------------------------------------------------------------------------
-- nvim-lspconfig (loaded in init.lua) provides :LspRestart, which stops the
-- client and reattaches it to all previously-attached buffers WITHOUT re-running
-- unrelated FileType autocmds. We prefer it; the fallback only matters if that
-- command is ever absent.
local function resync_gopls(reason)
  if reason then
    vim.notify('gopls re-sync: ' .. reason, vim.log.levels.INFO)
  end
  if vim.fn.exists ':LspRestart' == 2 then
    vim.cmd 'LspRestart gopls'
    return
  end
  -- Fallback: stop gopls; init.lua's vim.lsp.enable('gopls') re-attaches on the
  -- next Go buffer event.
  for _, client in ipairs(vim.lsp.get_clients { name = 'gopls' }) do
    client:stop(true)
  end
end

-- Manual escape hatch: reload changed buffers, then hard-restart gopls.
-- Use this any time gopls looks confused. <leader> is <space>.
vim.keymap.set('n', '<leader>gr', function()
  vim.cmd 'checktime' -- pull in on-disk buffer changes first
  resync_gopls 'manual (<leader>gr)'
end, { desc = '[G]opls [R]e-sync (reload buffers + restart gopls)' })

-- ---------------------------------------------------------------------------
-- Branch-switch detection (only used when AUTO_RESTART is true).
-- ---------------------------------------------------------------------------
if AUTO_RESTART then
  -- root -> last-seen HEAD identity. Lets us tell "HEAD changed" from "first
  -- time we've looked", so priming the cache never triggers a restart.
  local head_cache = {}

  -- Return a stable identity for the current HEAD using only file reads:
  --   * resolves the worktree/submodule case where `.git` is a FILE
  --   * follows `ref: refs/heads/x` to the commit so a pull/rebase on the SAME
  --     branch is still detected (the ref's hash changes even when HEAD's text
  --     doesn't); falls back to the ref name for packed-refs / worktree refs.
  local function git_head_id(root)
    local dotgit = root .. '/.git'
    local st = vim.uv.fs_stat(dotgit)
    if not st then
      return nil
    end

    local gitdir = dotgit
    if st.type == 'file' then -- linked worktree / submodule: "gitdir: <path>"
      local f = io.open(dotgit, 'r')
      if not f then
        return nil
      end
      local line = f:read '*l'
      f:close()
      local p = line and line:match '^gitdir:%s*(.+)$'
      if not p then
        return nil
      end
      gitdir = (p:sub(1, 1) == '/') and p or (root .. '/' .. p)
    end

    local hf = io.open(gitdir .. '/HEAD', 'r')
    if not hf then
      return nil
    end
    local head = hf:read '*l'
    hf:close()
    if not head then
      return nil
    end

    local ref = head:match '^ref:%s*(.+)$'
    if not ref then
      return head -- detached HEAD: this is already the commit hash
    end
    local rf = io.open(gitdir .. '/' .. ref, 'r')
    if rf then
      local id = rf:read '*l'
      rf:close()
      if id then
        return ref .. ':' .. id
      end
    end
    return ref -- packed-refs / worktree ref: fall back to the branch name
  end

  -- Restart gopls only if HEAD changed AND there's actually Go code open.
  local function maybe_resync()
    -- Find a loaded Go buffer; if none, restarting gopls would be pointless.
    local go_buf
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'go' then
        go_buf = buf
        break
      end
    end
    if not go_buf then
      return
    end

    local root = vim.fs.root(go_buf, '.git')
    if not root then
      return
    end

    local id = git_head_id(root)
    if not id then
      return
    end

    local prev = head_cache[root]
    head_cache[root] = id
    if prev == nil or prev == id then
      return -- first sighting, or unchanged → nothing to do
    end

    -- Defer the restart so it runs cleanly *after* the triggering event settles
    -- (e.g. after toggleterm finishes closing its float window on TermLeave),
    -- rather than mid-teardown.
    vim.schedule(function()
      resync_gopls 'git HEAD changed (branch switch)'
    end)
  end

  local group = vim.api.nvim_create_augroup('custom_gopls_branch_sync', { clear = true })

  -- Triggers cover both ways you might switch branches:
  --   TermLeave  — you ran `git checkout` in the toggleterm float (<C-\>) and
  --                toggled back to your code. THIS is the one for your workflow
  --                (nvim keeps OS focus, so FocusGained never fires here).
  --   TermClose  — the embedded shell actually exited.
  --   FocusGained— you switched branches in a *separate* terminal and alt-tabbed
  --                back (kept as a fallback for that case).
  --   DirChanged — primes the cache for a new project after :cd (records the
  --                baseline; no restart).
  vim.api.nvim_create_autocmd({ 'TermLeave', 'TermClose', 'FocusGained', 'DirChanged' }, {
    group = group,
    desc = 'Restart gopls when git HEAD changed (e.g. branch switch in toggleterm)',
    callback = maybe_resync,
  })

  -- Prime the cache once after startup so the FIRST branch switch is detected
  -- (otherwise the first FocusGained would only record the baseline and skip it).
  vim.schedule(function()
    local root = vim.fs.root(0, '.git') or vim.fs.root(vim.fn.getcwd(), '.git')
    if root then
      head_cache[root] = git_head_id(root)
    end
  end)
end
