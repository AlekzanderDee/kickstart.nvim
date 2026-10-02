-- ============================================================================
-- lsp-java.lua — Eclipse JDT Language Server (jdtls) for the mb3-streams monorepo
-- ============================================================================
--
-- WHY nvim-jdtls INSTEAD OF THE PLAIN vim.lsp.enable('jdtls') PATTERN
--   gopls/pyright are one server per workspace, so init.lua wires them through
--   its `servers` table (vim.lsp.config + vim.lsp.enable). jdtls is different:
--   it is *stateful* — it keeps an on-disk workspace/index. mb3-streams is a
--   multi-build monorepo: every `streams/<svc>` has its own settings.gradle +
--   gradlew, and the builds cross-reference each other's directories as
--   composite sub-projects. We therefore run ONE jdtls rooted at the REPO root
--   (see find_root below) so jdt.ls imports every build into a single shared
--   workspace — the same model VSCode uses. mfussenegger/nvim-jdtls provides
--   start_or_attach (reuses the one client), DAP + JUnit bundles, the Lombok
--   agent, and extended refactor commands. jdtls is kept OUT of init.lua's
--   `servers` table so it is not double-started.
--
-- REQUIREMENTS (declared in custom/plugins/mason.lua → ensure_installed)
--   jdtls, java-debug-adapter, java-test.
--   Plus a JDK to RUN jdtls (needs >= 21; Homebrew openjdk 23 is fine).
--   The project TARGETS Java 19 (Gradle toolchain). jdtls analyses at the source
--   level Gradle reports regardless of the JVM it runs on, but Gradle IMPORT
--   still wants a real JDK 19 — if `./gradlew` fails for you without one,
--   `brew install openjdk@19` and it will be picked up automatically (see
--   detect_runtimes below). Lombok is used across nearly every service; see the
--   find_lombok note for how the agent jar is located.

local function gh(repo) return 'https://github.com/' .. repo end
vim.pack.add { gh 'mfussenegger/nvim-jdtls' }

local data = vim.fn.stdpath 'data'
local mason = data .. '/mason'

-- Mason's latest `java-test` (0.43.1) requires the asm bundle in [9.9.0,9.10.0),
-- but the latest `jdtls` ships asm 9.10.1 — so the JUnit test plugin fails to
-- load (OSGi BundleException) and spams the LSP log, and no currently-available
-- java-test version matches asm 9.10.1. Keep the runner OFF until those versions
-- realign; DEBUGGING via java-debug-adapter is unaffected. Flip to true to
-- re-enable the java-test bundle + the <leader>Jt/<leader>Jn maps.
local JAVA_TEST = false

-- Mason's `jdtls` wrapper handles the equinox launcher jar, the OS-specific
-- `-configuration` dir, and locating java for us — we only add `-data` + agents.
local jdtls_bin = mason .. '/bin/jdtls'
if vim.fn.executable(jdtls_bin) == 0 then jdtls_bin = vim.fn.exepath 'jdtls' end

-- ---------------------------------------------------------------------------
-- Detect installed JDKs (cheap: glob a few known dirs, read each `release`
-- file). Used to (a) run jdtls on a modern JDK and (b) advertise runtimes so
-- jdtls can match the project's Java 19 target once a JDK 19 exists.
-- ---------------------------------------------------------------------------
local function jdk_major(home)
  local f = io.open(home .. '/release', 'r')
  if not f then return nil end
  local content = f:read '*a'
  f:close()
  local ver = content:match 'JAVA_VERSION="([^"]+)"'
  if not ver then return nil end
  local major = ver:match '^1%.(%d+)' or ver:match '^(%d+)' -- "1.8"->8, "19.0.2"->19
  return major and tonumber(major) or nil
end

local function detect_runtimes()
  local seen, runtimes = {}, {}
  local globs = {
    '/opt/homebrew/opt/openjdk*/libexec/openjdk.jdk/Contents/Home',
    '/usr/local/opt/openjdk*/libexec/openjdk.jdk/Contents/Home',
    '/Library/Java/JavaVirtualMachines/*/Contents/Home',
    (vim.env.HOME or '') .. '/.local/jdks/*/Contents/Home', -- manually-extracted JDKs (e.g. Temurin 19)
    (vim.env.HOME or '') .. '/.sdkman/candidates/java/*',
  }
  if vim.env.JAVA_HOME and vim.env.JAVA_HOME ~= '' then table.insert(globs, 1, vim.env.JAVA_HOME) end
  for _, g in ipairs(globs) do
    for _, home in ipairs(vim.fn.glob(g, true, true)) do
      home = vim.fn.resolve(home)
      if not seen[home] and vim.uv.fs_stat(home .. '/bin/java') then
        seen[home] = true
        local major = jdk_major(home)
        if major then
          runtimes[#runtimes + 1] = { name = major == 8 and 'JavaSE-1.8' or ('JavaSE-' .. major), path = home, major = major }
        end
      end
    end
  end
  return runtimes
end

local runtimes = detect_runtimes()

-- JDK to RUN jdtls on: newest detected that is >= 21 (jdtls's own requirement).
local run_java_home
for _, rt in ipairs(runtimes) do
  if rt.major >= 21 and (not run_java_home or rt.major > run_java_home.major) then run_java_home = rt end
end

-- JVM for Gradle IMPORT (separate from the one jdtls runs on). This repo's
-- wrapper is Gradle 8.10, which only *runs* on Java <= 22, and the build pins a
-- Java 19 toolchain. So run Gradle on JDK 19 if present, else the newest
-- detected JDK in [17,22]. If NONE is installed (e.g. only JDK 23 here), the key
-- is left unset: Gradle then runs on jdtls's own JVM (23), which usually still
-- imports but only after an "Unsupported Java runtime" warning and can misbehave
-- on compile/test tasks. Install a JDK 19 (e.g. `sdk install java 19.0.2-tem`)
-- for a clean, toolchain-matched import — detect_runtimes picks it up on restart.
local gradle_java_home
for _, rt in ipairs(runtimes) do
  if rt.major == 19 then gradle_java_home = rt end
end
if not gradle_java_home then
  for _, rt in ipairs(runtimes) do
    if rt.major >= 17 and rt.major <= 22 and (not gradle_java_home or rt.major > gradle_java_home.major) then gradle_java_home = rt end
  end
end

-- Strip the helper `major` field before handing runtimes to jdtls.
local jdtls_runtimes = vim.tbl_map(function(rt) return { name = rt.name, path = rt.path } end, runtimes)

-- ---------------------------------------------------------------------------
-- Lombok javaagent. Nearly every service uses Lombok; without the agent jdtls
-- reports phantom "cannot resolve getX()/builder()" errors on generated members.
-- Resolution order (jdtls still starts if none is found — with a one-time hint):
--   1) $LOMBOK_JAR   2) <nvim-data>/lombok.jar (a stable copy you control)
--   3) the newest lombok-*.jar already in the Gradle cache (present after you
--      run ./gradlew build in any service).
-- ---------------------------------------------------------------------------
local function find_lombok()
  local candidates = {}
  if vim.env.LOMBOK_JAR and vim.env.LOMBOK_JAR ~= '' then candidates[#candidates + 1] = vim.env.LOMBOK_JAR end
  candidates[#candidates + 1] = data .. '/lombok.jar'
  for _, c in ipairs(candidates) do
    if vim.uv.fs_stat(c) then return c end
  end
  local cache = vim.fn.glob((vim.env.HOME or '') .. '/.gradle/caches/modules-2/files-2.1/org.projectlombok/lombok/**/lombok-*.jar', true, true)
  local best
  for _, jar in ipairs(cache) do
    if not jar:match 'sources' and not jar:match 'javadoc' then best = jar end -- last ≈ newest
  end
  return best
end
local lombok_jar = find_lombok()
local lombok_warned = false

-- Project root for jdtls: the GIT REPO ROOT — one jdtls for the whole repo,
-- which is exactly what VSCode's Java extension does (it opens the workspace
-- folder and jdt.ls scans it for every Gradle build and imports them all into
-- ONE Eclipse workspace). Rooting per-service (the previous approach) spawns a
-- separate jdtls per service; because the services share sub-project
-- directories (../../shared/observability etc.), multiple clients fight over
-- the same .project/.classpath metadata and corrupt each other — that was the
-- source of the recurring "classpathprovider does not exist" / red-imports
-- breakage when working across services. One client = no fights, and
-- cross-service go-to-definition resolves to source.
local function find_root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local dir = name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
  local git_root = vim.fs.root(dir, '.git')
  if git_root then return git_root end
  -- Non-git fallback: nearest build marker.
  local marker = vim.fs.find(
    { 'settings.gradle', 'settings.gradle.kts', 'gradlew', 'build.gradle', 'build.gradle.kts', 'pom.xml', 'mvnw' },
    { upward = true, path = dir, type = 'file' }
  )[1]
  return marker and vim.fs.dirname(marker) or dir
end

-- ---------------------------------------------------------------------------
-- Start (or attach) jdtls for the current buffer's Gradle root.
-- ---------------------------------------------------------------------------
local function start_jdtls(bufnr)
  local root = find_root(bufnr)

  -- orders/clients/models REPEAT across services → key the workspace on the
  -- full path, not the basename, so jdtls never mixes two projects' indexes.
  local project = root:gsub('^' .. vim.pesc(vim.env.HOME or ''), ''):gsub('^/', ''):gsub('[/\\: ]', '_')
  local workspace = data .. '/jdtls-workspace/' .. project

  local bundles = vim.fn.glob(mason .. '/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar', true, true)
  if JAVA_TEST then
    vim.list_extend(bundles, vim.fn.glob(mason .. '/packages/java-test/extension/server/*.jar', true, true))
  end

  local cmd = { jdtls_bin, '-data', workspace }
  if lombok_jar then
    table.insert(cmd, '--jvm-arg=-javaagent:' .. lombok_jar)
  elseif not lombok_warned then
    lombok_warned = true
    vim.notify('[lsp-java] No lombok.jar found — Lombok-generated members may show as errors.\nRun ./gradlew build once, or drop a jar at ' .. data .. '/lombok.jar', vim.log.levels.INFO)
  end

  require('jdtls').start_or_attach {
    cmd = cmd,
    cmd_env = run_java_home and { JAVA_HOME = run_java_home.path } or nil,
    root_dir = root,
    init_options = { bundles = bundles },
    settings = {
      java = {
        configuration = { runtimes = jdtls_runtimes, updateBuildConfiguration = 'interactive' },
        -- Eclipse autobuild OFF. With it on, jdtls re-builds in the background and
        -- re-publishes STALE diagnostics onto already-open buffers — that's why red
        -- import errors kept reappearing and you had to `:e` to clear them. Off,
        -- diagnostics are computed when a file is opened/changed (correct) and are
        -- NOT churned by background rebuilds. Flip back to true only if you find
        -- diagnostics going stale the other way (edits not reflected until reopen).
        autobuild = { enabled = false },
        import = {
          -- Keep jdtls's Eclipse metadata (.project/.classpath/.factorypath/.settings/)
          -- inside the workspace -data dir instead of scattering it through the repo
          -- source tree (otherwise every imported Gradle project gets these untracked
          -- files, which is what was polluting `git status`).
          generatesMetadataFilesAtProjectRoot = false,
          gradle = { enabled = true, wrapper = { enabled = true }, java = gradle_java_home and { home = gradle_java_home.path } or nil },
        },
        -- Source attachment for dependencies. jdtls has NO gradle-specific
        -- downloadSources key (only these two exist); Buildship honors
        -- eclipse.downloadSources for Gradle projects. With the dep's -sources.jar
        -- present, go-to-definition opens the REAL source (e.g. KStream.peek at its
        -- true line) instead of an empty jdt:// buffer ("Invalid cursor line").
        eclipse = { downloadSources = true },
        maven = { downloadSources = true },
        signatureHelp = { enabled = true },
        -- NOTE: no `contentProvider.preferred = 'fernflower'` — mason's jdtls ships
        -- only the fernflower *engine* jar, not a content-provider registered under
        -- that id, so selecting it returned EMPTY class contents. Left at jdtls's
        -- default; with gradle.downloadSources above, real sources are used anyway.
        completion = {
          favoriteStaticMembers = {
            'org.assertj.core.api.Assertions.*',
            'org.junit.jupiter.api.Assertions.*',
            'org.junit.jupiter.api.Assumptions.*',
            'org.mockito.Mockito.*',
            'org.mockito.ArgumentMatchers.*',
          },
        },
        inlayHints = { parameterNames = { enabled = 'all' } },
      },
    },
    on_attach = function(_, b)
      local jdtls = require 'jdtls'
      -- DAP: attach the JUnit runner + discover main-class launch configs. These
      -- feed nvim-dap (set up in custom/plugins/dap.lua), so <leader>dc etc. and
      -- the <leader>Jt/<leader>Jn test maps below work in Java buffers.
      pcall(jdtls.setup_dap, { hotcodereplace = 'auto' })
      pcall(function() require('jdtls.dap').setup_dap_main_class_configs() end)

      local map = function(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { buffer = b, desc = desc }) end
      map('n', '<leader>Jo', jdtls.organize_imports, 'Java: Organize imports')
      map('n', '<leader>Jv', jdtls.extract_variable, 'Java: Extract variable')
      map('n', '<leader>Jc', jdtls.extract_constant, 'Java: Extract constant')
      map('v', '<leader>Jv', function() jdtls.extract_variable(true) end, 'Java: Extract variable (visual)')
      map('v', '<leader>Jm', function() jdtls.extract_method(true) end, 'Java: Extract method (visual)')
      if JAVA_TEST then
        map('n', '<leader>Jt', jdtls.test_class, 'Java: Test class')
        map('n', '<leader>Jn', jdtls.test_nearest_method, 'Java: Test nearest method')
      end
      map('n', '<leader>JR', function() pcall(vim.cmd, 'JdtUpdateConfig') end, 'Java: Re-import Gradle (update project config)')
    end,
  }
end

-- ---------------------------------------------------------------------------
-- Wire it up: start jdtls for every Java buffer.
-- ---------------------------------------------------------------------------
if jdtls_bin == '' then
  vim.schedule(function()
    vim.notify('[lsp-java] jdtls not found — open :Mason and install jdtls (+ java-debug-adapter, java-test)', vim.log.levels.WARN)
  end)
else
  local group = vim.api.nvim_create_augroup('custom_jdtls', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'java',
    desc = "Start jdtls for the buffer's Gradle project root",
    callback = function(args) start_jdtls(args.buf) end,
  })
  -- FileType already fired for any Java buffer opened before this file loaded.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'java' then start_jdtls(buf) end
  end
end
