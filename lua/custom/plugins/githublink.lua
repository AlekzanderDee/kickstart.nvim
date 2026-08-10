-- Copy a GitHub permalink to the current line/selection — no plugins, just git.
-- Auto-loaded at startup by lua/custom/plugins/init.lua.
--
-- Usage:
--   <leader>cg  (normal) → copies …/blob/<sha>/path#L42
--   <leader>cg  (visual) → copies …/blob/<sha>/path#L10-L20
--   :GitLink             → same, and accepts an explicit range (:10,20GitLink)
--
-- The link is pinned to the current commit (HEAD's SHA), so it never drifts.
-- Note: the commit must be pushed to GitHub for the link to resolve, and the
-- line body reflects the committed version — uncommitted edits above the cursor
-- can make the line number and the shown code drift apart.

local function github_url(line1, line2)
  local file = vim.fn.expand '%:p'
  if file == '' then
    vim.notify('GitLink: no file in buffer', vim.log.levels.WARN)
    return nil
  end
  local dir = vim.fn.fnamemodify(file, ':h')
  local function git(...)
    local out = vim.fn.system { 'git', '-C', dir, ... }
    return vim.v.shell_error == 0 and vim.trim(out) or nil
  end

  local root, remote, sha = git('rev-parse', '--show-toplevel'), git('remote', 'get-url', 'origin'), git('rev-parse', 'HEAD')
  if not (root and remote and sha) then
    vim.notify('GitLink: not a git repo, or no origin remote', vim.log.levels.WARN)
    return nil
  end

  -- Normalize remote (git@host:owner/repo.git or https://…) to an https base URL.
  local base = remote:gsub('^git@([^:]+):', 'https://%1/'):gsub('%.git$', ''):gsub('/$', '')
  local rel = file:sub(#root + 2) -- strip "root/"
  local frag = (line2 and line2 ~= line1) and ('#L%d-L%d'):format(line1, line2) or ('#L%d'):format(line1)
  return ('%s/blob/%s/%s%s'):format(base, sha, rel, frag)
end

vim.api.nvim_create_user_command('GitLink', function(opts)
  local url = github_url(opts.line1, opts.line2)
  if url then
    vim.fn.setreg('+', url)
    vim.notify('Copied: ' .. url)
  end
end, { range = true, desc = 'Copy GitHub permalink to clipboard' })

local map = vim.keymap.set
map('n', '<leader>cg', ':GitLink<CR>', { desc = 'Copy [G]itHub link', silent = true })
map('v', '<leader>cg', ':GitLink<CR>', { desc = 'Copy [G]itHub link', silent = true })
