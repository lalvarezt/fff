local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(vim.env.MINI_DIR or (root .. '/../mini.nvim'))
local child = require('mini.test').new_child_neovim()
child.start({ '--clean', '-n', '-i', 'NONE' })
child.o.columns = 160
child.o.lines = 48
child.lua(string.format(
  [[
  vim.opt.runtimepath:prepend(%q)
  vim.cmd('cd ' .. vim.fn.fnameescape(%q))
  if vim.env.FFF_BENCH_REF then
    for _, module in ipairs({ 'fff.picker_ui.grep_renderer', 'fff.picker_ui.list_renderer',
      'fff.picker_ui.renderer', 'fff.picker_ui.ui_creator' }) do
      local source = vim.system({ 'git', 'show', vim.env.FFF_BENCH_REF .. ':lua/' ..
        module:gsub('%%.', '/') .. '.lua' }, { text = true }):wait()
      assert(source.code == 0, source.stderr)
      package.preload[module] = assert(loadstring(source.stdout))
    end
  end
  vim.g.fff = { logging = { enabled = false }, suggestions = { enabled = false },
    frecency = { enabled = false }, history = { enabled = false } }
  require('fff.core').ensure_initialized()
  require('fff.rust').wait_for_initial_scan(8000)
  local picker = require('fff.picker_ui.picker_ui')
  _G.fff_input_metrics = {}
  local function instrument(module, key, label)
    local original = module[key]
    module[key] = function(...)
      local start = vim.uv.hrtime()
      local result = original(...)
      local entry = _G.fff_input_metrics[label] or { count = 0, ms = 0 }
      entry.count = entry.count + 1
      entry.ms = entry.ms + (vim.uv.hrtime() - start) / 1e6
      _G.fff_input_metrics[label] = entry
      return result
    end
  end
  instrument(require('fff.file_picker'), 'search_files_paginated', 'file_search')
  instrument(require('fff.fuzzy'), 'live_grep', 'grep_search')
  instrument(picker, 'render_list', 'render')
  instrument(picker, 'update_preview', 'preview_update')
  instrument(require('fff.file_picker.preview'), 'preview_file', 'preview_load')
  instrument(require('fff.treesitter_hl'), 'lang_from_filename', 'ts_language')
  instrument(require('fff.treesitter_hl'), 'get_line_highlights', 'ts_highlights')
]],
  root,
  root
))

local function snapshot(label)
  child.lua('vim.wait(80)')
  local metrics = child.lua_get('fff_input_metrics')
  local fields = { label }
  for _, key in ipairs({
    'file_search',
    'grep_search',
    'render',
    'preview_update',
    'preview_load',
    'ts_language',
    'ts_highlights',
  }) do
    local entry = metrics[key] or { count = 0, ms = 0 }
    fields[#fields + 1] = string.format('%s=%d/%.3fms', key, entry.count, entry.ms)
  end
  fields[#fields + 1] = 'query=' .. child.lua_get('require("fff.picker_ui.picker_ui").state.query')
  print(table.concat(fields, ' '))
end

for _, position in ipairs({ 'top', 'bottom' }) do
  for _, kind in ipairs({ 'files', 'plain', 'regex', 'fuzzy' }) do
    local mode = kind == 'files' and 'files' or 'grep'
    child.lua('fff_input_metrics = {}')
    child.lua(
      string.format(
        [[
      require('fff.picker_ui.picker_ui').open({ mode = %q,
        renderer = %s, grep_config = { modes = { %q } }, layout = { prompt_position = %q } })
    ]],
        mode == 'grep' and 'grep' or 'files',
        mode == 'grep' and "require('fff.picker_ui.grep_renderer')" or 'nil',
        kind,
        position
      )
    )
    snapshot(kind .. '/' .. position .. '/open')
    child.lua('fff_input_metrics = {}')
    child.type_keys('m')
    snapshot(kind .. '/' .. position .. '/first_key')
    child.lua('fff_input_metrics = {}')
    child.type_keys('ain')
    snapshot(kind .. '/' .. position .. '/burst')
    child.type_keys('<Esc>')
    child.lua('require("fff.picker_ui.picker_ui").close(); vim.wait(50)')
    child.lua('fff_input_metrics = {}')
    child.lua(
      string.format(
        [[
      require('fff.picker_ui.picker_ui').open({ mode = %q, query = 'main',
        renderer = %s, grep_config = { modes = { %q } }, layout = { prompt_position = %q } })
    ]],
        mode == 'grep' and 'grep' or 'files',
        mode == 'grep' and "require('fff.picker_ui.grep_renderer')" or 'nil',
        kind,
        position
      )
    )
    snapshot(kind .. '/' .. position .. '/prefilled')
    child.type_keys('<Esc>')
    child.lua('require("fff.picker_ui.picker_ui").close(); vim.wait(50)')
  end
end
child.stop()
