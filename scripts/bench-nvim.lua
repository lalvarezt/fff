local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
vim.o.columns = 160
vim.o.lines = 60

if vim.env.FFF_BENCH_REF then
  for _, module in ipairs({
    'fff.treesitter_hl',
    'fff.picker_ui.file_renderer',
    'fff.picker_ui.grep_renderer',
    'fff.picker_ui.list_renderer',
    'fff.picker_ui.renderer',
    'fff.file_picker.preview',
  }) do
    local source = vim
      .system(
        { 'git', 'show', vim.env.FFF_BENCH_REF .. ':lua/' .. module:gsub('%.', '/') .. '.lua' },
        { cwd = root, text = true }
      )
      :wait()
    assert(source.code == 0, source.stderr)
    package.preload[module] = assert(loadstring(source.stdout))
  end
end

local list_renderer = require('fff.picker_ui.list_renderer')
local renderer = require('fff.picker_ui.renderer')
local state = require('fff.picker_ui.picker_ui_state').state
local rust = require('fff.rust')
local ts = require('fff.treesitter_hl')
local config = require('fff.conf').get()
local iterations = tonumber(vim.env.FFF_BENCH_ITERATIONS) or 300
local samples = tonumber(vim.env.FFF_BENCH_SAMPLES) or 7
local buf = vim.api.nvim_create_buf(false, true)
local win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 150, height = 50 })
vim.api.nvim_set_option_value('wrap', false, { win = win })
local ns = vim.api.nvim_create_namespace('fff-bench')
local lang = ts.lang_from_filename('main.lua')
assert(lang, 'The Lua Tree-sitter parser is required')
renderer.init({ state = { active = true } })
state.list_buf, state.list_win, state.ns_id = buf, win, ns

local function measure(fn)
  for _ = 1, 20 do
    fn()
  end
  local times = {}
  for sample = 1, samples do
    collectgarbage('collect')
    local start = vim.uv.hrtime()
    for _ = 1, iterations do
      fn()
    end
    times[sample] = (vim.uv.hrtime() - start) / iterations / 1e6
  end
  table.sort(times)
  return times[math.ceil(#times / 2)]
end

local function context(mode, position)
  local items = {}
  for i = 1, tonumber(vim.env.FFF_BENCH_ROWS) or 40 do
    items[i] = {
      name = 'main.lua',
      extension = 'lua',
      directory = 'src/components/module_' .. math.ceil(i / 4),
      relative_path = 'src/components/module_' .. math.ceil(i / 4) .. '/main.lua',
      line_number = i,
      col = 6,
      line_content = string.format('local value_%d = require("fff.picker_ui.renderer")', i),
      match_ranges = { { 6, 11 } },
    }
  end
  return {
    config = config,
    items = items,
    cursor = 1,
    win_height = 50,
    win_width = 150,
    max_path_width = 148,
    prompt_position = position,
    display_start = 1,
    display_end = #items,
    iter_start = position == 'bottom' and #items or 1,
    iter_end = position == 'bottom' and 1 or #items,
    iter_step = position == 'bottom' and -1 or 1,
    renderer = mode == 'grep' and require('fff.picker_ui.grep_renderer') or nil,
    query = 'value',
    mode = mode,
    selected_files = {},
    format_file_display = function(item, width)
      local available = math.max(width - vim.fn.strdisplaywidth(item.name) - 1, 0)
      return item.name, rust.shorten_path(item.directory, available, 'middle_number')
    end,
  }
end

for _, position in ipairs({ 'top', 'bottom' }) do
  for _, mode in ipairs({ 'files', 'grep' }) do
    local ctx = context(mode, position)
    local function full_render()
      local fresh = vim.tbl_extend('force', ctx, {})
      fresh._ts_lang_cache = nil
      fresh._file_name_layouts = nil
      return list_renderer.render(fresh, buf, win, ns)
    end
    local full_ms = measure(full_render)
    local uncached_ms
    if mode == 'grep' then
      local generation = 0
      uncached_ms = measure(function()
        generation = generation + 1
        for i, item in ipairs(ctx.items) do
          item.line_content = string.format('local value_%d = require("fff.picker_ui.renderer") -- %d', i, generation)
        end
        full_render()
      end)
    end
    state.filtered_items = ctx.items
    state.last_render_ctx = ctx
    state.suggestion_source = nil
    state.item_to_lines = list_renderer.render(ctx, buf, win, ns)
    state.cursor = 1
    local cursor_ms = measure(function()
      local old = state.cursor
      state.cursor = old == 1 and 2 or 1
      assert(renderer.render_after_cursor_move(old))
    end)
    print(
      string.format(
        '%s %s full_render_ms=%.4f cursor_move_ms=%.4f%s',
        mode,
        position,
        full_ms,
        cursor_ms,
        uncached_ms and string.format(' uncached_render_ms=%.4f', uncached_ms) or ''
      )
    )
  end
end

ts.cleanup()
vim.api.nvim_win_close(win, true)
vim.api.nvim_buf_delete(buf, { force = true })

local preview = require('fff.file_picker.preview')
local lookup
for i = 1, 30 do
  local name, value = debug.getupvalue(preview.preview_file, i)
  if name == 'find_existing_buffer' then
    lookup = value
    break
  end
end
assert(lookup, 'Preview buffer lookup was not found')

for _, count in ipairs({ 1, 200, 1000 }) do
  local buffers = {}
  for i = 1, count do
    local buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buffer, vim.fn.tempname() .. '.lua')
    buffers[#buffers + 1] = buffer
  end
  local path = root .. '/lua/fff/core.lua'
  local target = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(target, path)
  local loaded_ms = measure(function() assert(lookup(path) == target) end)
  local missing_ms = measure(function() assert(lookup(path .. '.missing') == nil) end)
  print(
    string.format('preview buffers=%d loaded_lookup_ms=%.4f missing_lookup_ms=%.4f', count + 1, loaded_ms, missing_ms)
  )
  vim.api.nvim_buf_delete(target, { force = true })
  for _, buffer in ipairs(buffers) do
    vim.api.nvim_buf_delete(buffer, { force = true })
  end
end
