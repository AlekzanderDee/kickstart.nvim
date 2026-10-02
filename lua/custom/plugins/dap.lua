local function gh(repo) return 'https://github.com/' .. repo end

vim.pack.add {
  gh 'mfussenegger/nvim-dap',
  gh 'rcarriga/nvim-dap-ui',
  gh 'nvim-neotest/nvim-nio',
  gh 'leoluz/nvim-dap-go',
  gh 'theHamsta/nvim-dap-virtual-text',
}

local dap = require 'dap'
local dapui = require 'dapui'

dapui.setup {
  icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
  controls = {
    icons = {
      pause = '⏸',
      play = '▶',
      step_into = '⏎',
      step_over = '⏭',
      step_out = '⏮',
      step_back = 'b',
      run_last = '▶▶',
      terminate = '⏹',
      disconnect = '⏏',
    },
  },
}

dap.listeners.after.event_initialized['dapui_config'] = dapui.open
dap.listeners.before.event_terminated['dapui_config'] = dapui.close
dap.listeners.before.event_exited['dapui_config'] = dapui.close

require('nvim-dap-virtual-text').setup()

require('dap-go').setup {
  delve = {
    path = (function()
      local mason_delve = vim.fn.stdpath 'data' .. '/mason/bin/dlv'
      if vim.fn.executable(mason_delve) == 1 then return mason_delve end
      return vim.fn.exepath 'dlv' ~= '' and vim.fn.exepath 'dlv' or 'dlv'
    end)(),
    output_mode = 'remote',
  },
}

-- Python: host debugpy with the project's own .venv interpreter, so each repo
-- debugs against the dependencies it actually declares. `config.cwd` comes from
-- launch.json; fall back to walking up from nvim's cwd, then to PATH.
local function python_for(config)
  local start = (config and config.cwd) or vim.fn.getcwd()
  local venv = vim.fs.find('.venv', { upward = true, type = 'directory', path = start })[1]
  if venv then
    local py = venv .. '/bin/python'
    if vim.fn.executable(py) == 1 then return py end
  end
  return vim.fn.exepath 'python3'
end

dap.adapters.python = function(cb, config)
  cb {
    type = 'executable',
    command = python_for(config),
    args = { '-m', 'debugpy.adapter' },
  }
end
dap.adapters.debugpy = dap.adapters.python

-- Override nvim-dap's built-in launch.json provider so it walks UPWARD
-- from the current cwd instead of only checking `<cwd>/.vscode/launch.json`.
-- This makes `<leader>dc` find configs after `:cd`-ing into a sub-package.
dap.providers.configs['dap.launch.json'] = function()
  local launchjs = vim.fs.find('.vscode/launch.json', { upward = true, type = 'file' })[1]
  if not launchjs then return {} end
  local ok, configs = pcall(require('dap.ext.vscode').getconfigs, launchjs)
  if not ok then
    vim.notify('Failed to parse ' .. launchjs .. ': ' .. tostring(configs), vim.log.levels.WARN)
    return {}
  end
  -- nvim-dap expands `${workspaceFolder}` to nvim's cwd, which is wrong the
  -- moment you `:cd` into a sub-package -- the very case this upward walk
  -- exists for. `${projectRoot}` is the directory holding `.vscode/`, so it
  -- stays correct from anywhere in the tree. Metatables are preserved because
  -- nvim-dap hangs `${input:...}` resolution off them.
  local root = vim.fs.dirname(vim.fs.dirname(launchjs))
  local function subst(value)
    if type(value) == 'string' then return (value:gsub('%${projectRoot}', root)) end
    if type(value) == 'table' then
      local out = {}
      for k, v in pairs(value) do out[k] = subst(v) end
      return setmetatable(out, getmetatable(value))
    end
    return value
  end
  return subst(configs)
end

-- keymaps (lazy.nvim's `keys =` doesn't exist under vim.pack — bind directly)
local map = vim.keymap.set
map('n', '<leader>dc', function() dap.continue() end, { desc = 'Debug: Continue' })
map('n', '<leader>db', function() dap.toggle_breakpoint() end, { desc = 'Debug: Breakpoint' })
map('n', '<leader>dB', function() dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ') end, { desc = 'Debug: Conditional breakpoint' })
map('n', '<leader>di', function() dap.step_into() end, { desc = 'Debug: Step Into' })
map('n', '<leader>do', function() dap.step_over() end, { desc = 'Debug: Step Over' })
map('n', '<leader>dO', function() dap.step_out() end, { desc = 'Debug: Step Out' })
map('n', '<leader>dr', function() dap.run_last() end, { desc = 'Debug: Run Last' })
map('n', '<leader>du', function() dapui.toggle() end, { desc = 'Debug: Toggle UI' })
map('n', '<leader>dq', function() dap.terminate() end, { desc = 'Debug: Terminate (quit)' })
map('n', '<leader>dR', function() dap.restart() end, { desc = 'Debug: Restart' })
