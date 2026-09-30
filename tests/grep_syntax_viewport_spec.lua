local list_renderer = require('fff.picker_ui.list_renderer')
local renderer = require('fff.picker_ui.renderer')
local grep_renderer = require('fff.picker_ui.grep_renderer')
local state = require('fff.picker_ui.picker_ui_state').state
local ts = require('fff.treesitter_hl')
local config = require('fff.conf').get()
local buf, win, ns, original, calls

local function context(position)
  local items = {}
  for i = 1, 200 do
    items[i] = {
      name = 'main.lua',
      relative_path = i <= 20 and 'src/main.lua' or 'src/group_' .. math.ceil(i / 20) .. '/main.lua',
      directory = 'src',
      line_number = i,
      col = 0,
      line_content = 'local value_' .. i .. ' = require("fffλ")',
      match_ranges = { { 0, 5 } },
    }
  end
  return {
    config = config,
    items = items,
    cursor = 1,
    win_height = 10,
    win_width = 140,
    max_path_width = 138,
    prompt_position = position,
    display_start = 1,
    display_end = #items,
    iter_start = position == 'bottom' and #items or 1,
    iter_end = position == 'bottom' and 1 or #items,
    iter_step = position == 'bottom' and -1 or 1,
    renderer = grep_renderer,
    query = 'local',
    mode = 'grep',
    selected_files = {},
    selected_items = { ['src/main.lua:2:0'] = true },
    format_file_display = function(item) return item.name, item.directory end,
  }
end

local function view()
  return vim.api.nvim_win_call(win, function() return { vim.fn.line('w0'), vim.fn.line('w$') } end)
end

local function syntax_marks(buffer, namespace, first, last)
  local result = {}
  for _, mark in
    ipairs(vim.api.nvim_buf_get_extmarks(buffer, namespace, { first - 1, 0 }, { last - 1, -1 }, { details = true }))
  do
    if mark[4].priority == 120 then
      result[#result + 1] = vim.json.encode({ mark[2], mark[3], mark[4].end_col, mark[4].hl_group })
    end
  end
  table.sort(result)
  return result
end

local function assert_visible_syntax(ctx)
  local visible = view()
  local expected = {}
  for i, mapping in pairs(state.item_to_lines) do
    if mapping.last >= visible[1] and mapping.last <= visible[2] then
      assert.is_true(ctx._syntax_highlighted[i])
      local line = vim.api.nvim_buf_get_lines(buf, mapping.last - 1, mapping.last, false)[1]
      local content = ctx.items[i]._trimmed_content
      local offset = assert(line:find(content, 1, true)) - 1
      for _, hl in ipairs(original(content, 'lua')) do
        expected[#expected + 1] =
          vim.json.encode({ mapping.last - 1, offset + hl.col, offset + hl.end_col, hl.hl_group })
      end
    end
  end
  table.sort(expected)
  assert.is_true(#expected > 0)
  assert.are.same(expected, syntax_marks(buf, ns, visible[1], visible[2]))
end

describe('grep syntax viewport', function()
  before_each(function()
    vim.o.columns = 160
    vim.o.lines = 40
    buf = vim.api.nvim_create_buf(false, true)
    win = vim.api.nvim_open_win(buf, false, { relative = 'editor', row = 0, col = 0, width = 140, height = 10 })
    vim.api.nvim_set_option_value('wrap', false, { win = win })
    vim.api.nvim_set_option_value('scrolloff', 0, { win = win })
    ns = vim.api.nvim_create_namespace('fff-syntax-viewport')
    renderer.init({ state = { active = true } })
    state.list_buf, state.list_win, state.ns_id = buf, win, ns
    state.suggestion_source = nil
    original, calls = ts.get_line_highlights, 0
    ts.get_line_highlights = function(...)
      calls = calls + 1
      return original(...)
    end
    ts.cleanup()
  end)

  after_each(function()
    ts.get_line_highlights = original
    ts.cleanup()
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    state.last_render_ctx = nil
  end)

  for _, position in ipairs({ 'top', 'bottom' }) do
    it('parses only visible rows with a ' .. position .. ' prompt', function()
      local ctx = context(position)
      state.item_to_lines = list_renderer.render(ctx, buf, win, ns)
      local visible = view()
      local expected_calls = 0
      for i, mapping in pairs(state.item_to_lines) do
        if mapping.last >= visible[1] and mapping.last <= visible[2] then
          expected_calls = expected_calls + 1
        else
          assert.is_nil(ctx._syntax_highlighted[i])
        end
      end
      assert.are.equal(expected_calls, calls)
      assert.is_true(calls <= 10)
      assert_visible_syntax(ctx)
    end)

    it('fills syntax on navigation and scrolling with a ' .. position .. ' prompt', function()
      local ctx = context(position)
      state.filtered_items, state.last_render_ctx = ctx.items, ctx
      state.item_to_lines = list_renderer.render(ctx, buf, win, ns)
      state.cursor = 120
      assert.is_true(renderer.render_after_cursor_move(1))
      assert_visible_syntax(ctx)
      local before = calls
      renderer.highlight_visible_syntax()
      renderer.highlight_visible_syntax()
      assert.are.equal(before, calls)
      local visible = view()
      local target = position == 'top' and visible[2] + 5 or visible[1] - 5
      vim.api.nvim_win_call(win, function() vim.fn.winrestview({ topline = target }) end)
      renderer.highlight_visible_syntax()
      assert_visible_syntax(ctx)
      state.cursor = 2
      assert.is_true(renderer.render_after_cursor_move(120))
      assert_visible_syntax(ctx)
      local row = state.item_to_lines[2].last - 1
      local selected, matched = false, false
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })) do
        selected = selected or mark[4].priority == 1001
        matched = matched or mark[4].priority == 200
      end
      assert.is_true(selected)
      assert.is_true(matched)
    end)

    it('resets syntax tracking on redraw and resize with a ' .. position .. ' prompt', function()
      local ctx = context(position)
      state.item_to_lines = list_renderer.render(ctx, buf, win, ns)
      assert_visible_syntax(ctx)
      vim.api.nvim_win_set_height(win, 20)
      ctx.win_height = 20
      state.item_to_lines = list_renderer.render(ctx, buf, win, ns)
      assert_visible_syntax(ctx)
    end)
  end
end)
