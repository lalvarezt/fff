---@diagnostic disable: undefined-field, missing-fields
-- Integration tests for grep mode file-group jump shortcuts.
local picker_ui
local state_mod

local plugin_dir = vim.fn.fnamemodify(vim.fn.resolve(debug.getinfo(1, 'S').source:sub(2)), ':h:h')

local function make_item(path, line, col)
  return { relative_path = path, line_number = line, col = col, line_content = '' }
end

local function reset_state(items, cursor)
  local S = state_mod.state
  S.active = true
  S.mode = 'grep'
  S.filtered_items = items
  S.items = items
  S.cursor = cursor or 1
  S.pagination = S.pagination or {}
  S.pagination.page_size = #items
  S.pagination.page_index = 0
  S.pagination.total_matched = #items
  S.pagination.grep_file_offsets = { 0 }
  S.pagination.grep_next_file_offset = 0
end

local stubs_installed = false
local function install_stubs()
  if stubs_installed then return end
  -- Mock UI updates called by submodules
  picker_ui.render_after_cursor_move = function() return true end
  picker_ui.update_status = function() end
  picker_ui.update_preview_debounced = function() end
  stubs_installed = true
end

describe('grep_jump_to_next_file / grep_jump_to_prev_file', function()
  before_each(function()
    vim.g.fff = {}

    local fff_rust = require('fff.rust')
    local file_picker = require('fff.file_picker')

    -- Initialize core components and background worker threads
    file_picker.setup()
    fff_rust.init_file_picker(plugin_dir)

    -- Resolve to the correct coordinator path inside the submodules directory
    picker_ui = require('fff.picker_ui.picker_ui')
    state_mod = require('fff.picker_ui.picker_ui_state')

    install_stubs()
  end)

  after_each(function()
    local fff_rust = require('fff.rust')
    pcall(fff_rust.stop_background_monitor)
    pcall(fff_rust.cleanup_file_picker)
    vim.g.fff = nil
  end)

  it('jumps to first match of the next file group', function()
    local items = {
      make_item('a.lua', 1, 1),
      make_item('a.lua', 5, 3),
      make_item('a.lua', 9, 1),
      make_item('b.lua', 2, 1),
      make_item('b.lua', 7, 1),
      make_item('c.lua', 4, 2),
    }
    reset_state(items, 1)

    picker_ui.grep_jump_to_next_file()
    assert.are.equal(4, state_mod.state.cursor)

    picker_ui.grep_jump_to_next_file()
    assert.are.equal(6, state_mod.state.cursor)
  end)

  it('jumps to first match of the previous file group', function()
    local items = {
      make_item('a.lua', 1, 1),
      make_item('a.lua', 5, 3),
      make_item('b.lua', 2, 1),
      make_item('b.lua', 7, 1),
      make_item('c.lua', 4, 2),
    }
    reset_state(items, 5)

    picker_ui.grep_jump_to_prev_file()
    assert.are.equal(3, state_mod.state.cursor)

    picker_ui.grep_jump_to_prev_file()
    assert.are.equal(1, state_mod.state.cursor)
  end)

  it('is a no-op when not in grep mode', function()
    local items = { make_item('a.lua', 1, 1), make_item('b.lua', 1, 1) }
    reset_state(items, 1)
    state_mod.state.mode = nil

    picker_ui.grep_jump_to_next_file()
    assert.are.equal(1, state_mod.state.cursor)
  end)

  it('loads next page when no later file group exists on current page', function()
    local page1 = {
      make_item('a.lua', 1, 1),
      make_item('a.lua', 2, 1),
    }
    local page2 = {
      make_item('b.lua', 1, 1),
      make_item('b.lua', 4, 1),
    }
    reset_state(page1, 2)
    state_mod.state.pagination.grep_next_file_offset = 1

    local called = false
    local original_load_next = picker_ui.load_next_page

    picker_ui.load_next_page = function()
      called = true
      state_mod.state.filtered_items = page2
      state_mod.state.items = page2
      state_mod.state.cursor = 1
      state_mod.state.pagination.page_index = 1
      return true
    end

    picker_ui.grep_jump_to_next_file()
    assert.is_true(called, 'expected load_next_page to be invoked')
    assert.are.equal(1, state_mod.state.cursor)
    assert.are.equal('b.lua', state_mod.state.filtered_items[state_mod.state.cursor].relative_path)

    picker_ui.load_next_page = original_load_next
  end)
end)

local function wait_for_picker_work(predicate)
  assert.is_true(vim.wait(1000, predicate, 10), 'scheduled picker work did not complete')
end

local function flush_picker_work()
  vim.wait(30, function() return false end, 10)
end

for _, prompt_position in ipairs({ 'top', 'bottom' }) do
  describe('picker input coalescing (' .. prompt_position .. ')', function()
    local buffers
    local queries
    local original
    local input_conf
    local input_search_manager
    local input_ui_creator

    local function new_buffer(lines)
      local S = state_mod.state
      local buf = vim.api.nvim_create_buf(false, true)
      table.insert(buffers, buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { S.config.prompt })
      return buf
    end

    local function attach_input(buf)
      state_mod.state.input_buf = buf
      input_ui_creator.init(picker_ui)
      input_ui_creator.setup_keymaps()
    end

    before_each(function()
      picker_ui = require('fff.picker_ui.picker_ui')
      state_mod = require('fff.picker_ui.picker_ui_state')
      input_conf = require('fff.conf')
      input_search_manager = require('fff.picker_ui.search_manager')
      input_ui_creator = require('fff.picker_ui.ui_creator')

      local S = state_mod.state
      buffers = {}
      queries = {}
      original = {
        active = S.active,
        config = S.config,
        input_buf = S.input_buf,
        input_win = S.input_win,
        list_buf = S.list_buf,
        preview_buf = S.preview_buf,
        query = S.query,
        on_input_change = picker_ui.on_input_change,
        update_results_sync = input_search_manager.update_results_sync,
      }

      S.config = vim.deepcopy(input_conf.get())
      S.config.layout.prompt_position = prompt_position
      S.config.prompt_vim_mode = false
      S.active = true
      S.query = ''
      S.input_win = nil
      S.preview_buf = nil
      S.list_buf = new_buffer({ '' })

      input_search_manager.update_results_sync = function() table.insert(queries, S.query) end
      attach_input(new_buffer())
    end)

    after_each(function()
      local S = state_mod.state
      S.active = false
      S.input_buf = nil
      S.list_buf = nil
      flush_picker_work()

      picker_ui.on_input_change = original.on_input_change
      input_search_manager.update_results_sync = original.update_results_sync
      S.active = original.active
      S.config = original.config
      S.input_buf = original.input_buf
      S.input_win = original.input_win
      S.list_buf = original.list_buf
      S.preview_buf = original.preview_buf
      S.query = original.query

      for _, buf in ipairs(buffers) do
        if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
      end
    end)

    it('searches only the final same-tick buffer state', function()
      local S = state_mod.state
      local prompt = S.config.prompt
      vim.api.nvim_buf_set_lines(S.input_buf, 0, -1, false, { prompt .. 'a' })
      vim.api.nvim_buf_set_lines(S.input_buf, 0, -1, false, { prompt .. 'ab' })
      vim.api.nvim_buf_set_lines(S.input_buf, 0, -1, false, { prompt .. 'abc' })

      wait_for_picker_work(function() return #queries == 1 end)
      assert.are.same({ 'abc' }, queries)
    end)

    it('coalesces a rapid edit burst', function()
      local S = state_mod.state
      local line = S.config.prompt
      for char in ('rapid_input_burst'):gmatch('.') do
        vim.api.nvim_buf_set_text(S.input_buf, 0, #line, 0, #line, { char })
        line = line .. char
      end

      wait_for_picker_work(function() return S.query == 'rapid_input_burst' end)
      assert.are.same({ 'rapid_input_burst' }, queries)
    end)

    it('processes changes from separate event-loop turns', function()
      local S = state_mod.state
      local prompt = S.config.prompt
      vim.api.nvim_buf_set_lines(S.input_buf, 0, -1, false, { prompt .. 'a' })
      wait_for_picker_work(function() return #queries == 1 end)

      vim.api.nvim_buf_set_lines(S.input_buf, 0, -1, false, { prompt .. 'ab' })
      wait_for_picker_work(function() return #queries == 2 end)
      assert.are.same({ 'a', 'ab' }, queries)
    end)

    it('does not reschedule after prompt normalization', function()
      local S = state_mod.state
      local prompt = S.config.prompt
      vim.api.nvim_buf_set_lines(S.input_buf, 0, -1, false, { prompt .. '  alpha', ' beta  ' })

      wait_for_picker_work(function() return #queries == 1 end)
      flush_picker_work()
      assert.are.same({ 'alpha beta' }, queries)
      assert.are.same({ prompt .. 'alpha beta' }, vim.api.nvim_buf_get_lines(S.input_buf, 0, -1, false))
    end)

    it('ignores work for a picker closed before the callback', function()
      local S = state_mod.state
      vim.api.nvim_buf_set_lines(S.input_buf, 0, -1, false, { S.config.prompt .. 'stale' })
      S.active = false
      S.input_buf = nil

      flush_picker_work()
      assert.are.same({}, queries)
    end)

    it('ignores stale work after reopening with a new buffer', function()
      local S = state_mod.state
      vim.api.nvim_buf_set_lines(S.input_buf, 0, -1, false, { S.config.prompt .. 'stale' })
      S.active = false
      S.input_buf = nil

      local replacement = new_buffer()
      S.active = true
      attach_input(replacement)
      vim.api.nvim_buf_set_lines(replacement, 0, -1, false, { S.config.prompt .. 'fresh' })

      wait_for_picker_work(function() return #queries == 1 end)
      assert.are.same({ 'fresh' }, queries)
    end)

    it('refreshes an unchanged restored query once', function()
      local S = state_mod.state
      S.query = 'restored'
      vim.api.nvim_buf_set_lines(S.input_buf, 0, -1, false, { S.config.prompt .. 'restored' })

      wait_for_picker_work(function() return #queries == 1 end)
      assert.are.same({ 'restored' }, queries)
    end)
  end)
end

describe('picker render coalescing', function()
  local buffers
  local original
  local rendered_buffers
  local previews
  local statuses

  local function new_buffer()
    local buf = vim.api.nvim_create_buf(false, true)
    table.insert(buffers, buf)
    return buf
  end

  before_each(function()
    picker_ui = require('fff.picker_ui.picker_ui')
    state_mod = require('fff.picker_ui.picker_ui_state')

    local S = state_mod.state
    buffers = {}
    rendered_buffers = {}
    previews = 0
    statuses = 0
    original = {
      active = S.active,
      list_buf = S.list_buf,
      render_list = picker_ui.render_list,
      update_preview = picker_ui.update_preview,
      update_status = picker_ui.update_status,
    }

    S.active = true
    S.list_buf = new_buffer()
    picker_ui.render_list = function() table.insert(rendered_buffers, S.list_buf) end
    picker_ui.update_preview = function() previews = previews + 1 end
    picker_ui.update_status = function() statuses = statuses + 1 end
  end)

  after_each(function()
    local S = state_mod.state
    S.active = false
    S.list_buf = nil
    flush_picker_work()

    picker_ui.render_list = original.render_list
    picker_ui.update_preview = original.update_preview
    picker_ui.update_status = original.update_status
    S.active = original.active
    S.list_buf = original.list_buf

    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
  end)

  it('renders once for repeated requests on one buffer', function()
    local expected_buf = state_mod.state.list_buf
    picker_ui.render_debounced()
    picker_ui.render_debounced()
    picker_ui.render_debounced()

    wait_for_picker_work(function() return #rendered_buffers == 1 end)
    assert.are.same({ expected_buf }, rendered_buffers)
    assert.are.equal(1, previews)
    assert.are.equal(1, statuses)
  end)

  it('skips stale work and renders a replacement buffer', function()
    local S = state_mod.state
    local old_buf = S.list_buf
    picker_ui.render_debounced()

    local replacement = new_buffer()
    S.list_buf = replacement
    picker_ui.render_debounced()

    wait_for_picker_work(function() return #rendered_buffers == 1 end)
    assert.are.same({ replacement }, rendered_buffers)
    assert.are_not.equal(old_buf, rendered_buffers[1])
    assert.are.equal(1, previews)
    assert.are.equal(1, statuses)
  end)
end)
