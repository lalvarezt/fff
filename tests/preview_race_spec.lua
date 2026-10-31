local preview = require('fff.file_picker.preview')
local picker = require('fff.picker_ui.picker_ui')
local manager = require('fff.picker_ui.preview_manager')
local state = picker.state
local root, buf, win, release, original, operation

describe('preview callbacks after results become empty', function()
  before_each(function()
    vim.o.columns = 120
    vim.o.lines = 80
    root = vim.fn.tempname()
    vim.fn.mkdir(root, 'p')
    vim.fn.writefile({ 'return "stale file content"' }, root .. '/source.lua')
    buf = vim.api.nvim_create_buf(false, true)
    state.active = true
    state.preview_visible = true
    state.preview_buf = buf
    state.file_info_buf = nil
    state.filtered_items = {}
    state.cursor = 1
    preview.setup(require('fff.conf').get().preview)
  end)

  after_each(function()
    if original then vim.uv[operation] = original end
    if release then release() end
    vim.wait(30)
    preview.clear()
    manager.close_preview_timer()
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    state.active = false
    state.preview_visible = false
    state.preview_buf, state.preview_win = nil, nil
    original, release, win = nil, nil, nil
    vim.fn.delete(root, 'rf')
  end)

  for _, position in ipairs({ 'top', 'bottom' }) do
    for _, stage in ipairs({ 'fs_open', 'fs_read' }) do
      it('discards a pending ' .. stage .. ' with a ' .. position .. ' prompt', function()
        win = vim.api.nvim_open_win(buf, false, {
          relative = 'editor',
          row = position == 'top' and 3 or 2,
          col = 1,
          width = 115,
          height = 70,
        })
        state.preview_win = win
        preview.set_preview_window(win)
        operation = stage
        original = vim.uv[stage]
        vim.uv[stage] = function(path_or_fd, flags_or_size, mode_or_offset, callback)
          if not callback then return original(path_or_fd, flags_or_size, mode_or_offset) end
          return original(path_or_fd, flags_or_size, mode_or_offset, function(err, result)
            release = function()
              release = nil
              callback(err, result)
            end
          end)
        end

        assert.is_true(preview.preview(root .. '/source.lua', buf))
        assert.is_true(vim.wait(2000, function() return release ~= nil end))
        vim.uv[stage] = original
        manager.update_preview()
        assert.are.same({ 'No preview available' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        release()
        vim.wait(100)
        assert.are.same({ 'No preview available' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        assert.is_nil(preview.state.current_file)
        assert.is_nil(preview.state.file_operation)
      end)
    end
  end
end)
