vim.api.nvim_create_autocmd('PackChanged', {
  desc = 'Build native libs for plugins that need them',
  callback = function(ev)
    local spec = ev.data.spec
    local kind = ev.data.kind -- 'install' | 'update' | 'delete'
    if kind == 'delete' then return end

    -- blink.cmp Rust fuzzy matcher
    if spec.name == 'blink.cmp' then
      if vim.fn.executable 'cargo' ~= 1 then
        vim.notify('blink.cmp: cargo not found; using Lua fuzzy fallback', vim.log.levels.WARN)
        return
      end
      vim.notify('Building blink.cmp fuzzy lib...', vim.log.levels.INFO)
      vim.system({ 'cargo', 'build', '--release' }, { cwd = ev.data.path }):wait()
    end
  end,
})

local function ensure_blink_built()
  local blink_dir = vim.fn.stdpath 'data' .. '/site/pack/core/opt/blink.cmp'
  if vim.fn.isdirectory(blink_dir) ~= 1 then return end
  local hits = vim.fn.glob(blink_dir .. '/target/release/libblink_cmp_fuzzy.*', false, true)
  if #hits > 0 then return end -- already built
  if vim.fn.executable 'cargo' ~= 1 then
    vim.notify('blink.cmp: cargo not found; skipping build', vim.log.levels.WARN)
    return
  end
  vim.notify('Building blink.cmp fuzzy lib...', vim.log.levels.INFO)
  vim.system({ 'cargo', 'build', '--release' }, { cwd = blink_dir }):wait()
end

ensure_blink_built()
