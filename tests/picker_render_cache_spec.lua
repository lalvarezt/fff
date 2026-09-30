local list_renderer = require('fff.picker_ui.list_renderer')
local renderer = require('fff.picker_ui.renderer')
local state = require('fff.picker_ui.picker_ui_state').state
local ts = require('fff.treesitter_hl')
local config = require('fff.conf').get()
local buf, win, ns

local function extmarks()
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  local normalized = {}
  for _, mark in ipairs(marks) do
    local details = {}
    for key, value in pairs(mark[4]) do
      details[#details + 1] = { key, value }
    end
    table.sort(details, function(a, b) return a[1] < b[1] end)
    normalized[#normalized + 1] = vim.json.encode({ mark[2], mark[3], details })
  end
  table.sort(normalized)
  return normalized
end

local function context(mode, position, width)
  local items = {}
  for i = 1, 3 do
    items[i] = {
      name = 'main.lua',
      extension = 'lua',
      relative_path = 'src/main.lua',
      directory = 'src',
      line_number = i,
      col = 6,
      line_content = 'local value_' .. i .. ' = require("fff")',
      match_ranges = { { 6, 11 } },
    }
  end
  return {
    config = config,
    items = items,
    cursor = 1,
    win_height = 10,
    win_width = width,
    max_path_width = width - 2,
    prompt_position = position,
    display_start = 1,
    display_end = #items,
    iter_start = position == 'bottom' and #items or 1,
    iter_end = position == 'bottom' and 1 or #items,
    iter_step = position == 'bottom' and -1 or 1,
    renderer = mode == 'grep' and require('fff.picker_ui.grep_renderer') or nil,
    query = 'value',
    mode = mode,
    selected_files = { ['src/main.lua'] = true },
    selected_items = { ['src/main.lua:2:6'] = true },
    format_file_display = function(item) return item.name, item.directory end,
  }
end

describe('cached picker rendering', function()
  before_each(function()
    vim.o.columns = 160
    vim.o.lines = 40
    buf = vim.api.nvim_create_buf(false, true)
    win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 140, height = 10 })
    vim.api.nvim_set_option_value('wrap', false, { win = win })
    ns = vim.api.nvim_create_namespace('fff-render-cache-test')
    renderer.init({ state = { active = true } })
    state.list_buf, state.list_win, state.ns_id = buf, win, ns
    state.suggestion_source = nil
    ts.cleanup()
  end)

  after_each(function()
    ts.cleanup()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    state.last_render_ctx = nil
  end)

  for _, position in ipairs({ 'top', 'bottom' }) do
    for _, mode in ipairs({ 'files', 'grep' }) do
      it('preserves ' .. mode .. ' rows, selection and highlights with a ' .. position .. ' prompt', function()
        local ctx = context(mode, position, 140)
        state.filtered_items = ctx.items
        state.last_render_ctx = ctx
        state.item_to_lines = list_renderer.render(ctx, buf, win, ns)
        state.cursor = 2
        assert.is_true(renderer.render_after_cursor_move(1))
        local expected_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local expected_marks = extmarks()
        local expected_cursor = vim.api.nvim_win_get_cursor(win)
        ts.cleanup()
        local fresh = context(mode, position, 140)
        fresh.cursor = 2
        list_renderer.render(fresh, buf, win, ns)
        assert.are.same(expected_lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        assert.are.same(expected_marks, extmarks())
        assert.are.same(expected_cursor, vim.api.nvim_win_get_cursor(win))

        local narrow = context(mode, position, 25)
        list_renderer.render(narrow, buf, win, ns)
        local narrow_marks = extmarks()
        ts.cleanup()
        list_renderer.render(context(mode, position, 25), buf, win, ns)
        assert.are.same(narrow_marks, extmarks())
      end)
    end
  end
end)
