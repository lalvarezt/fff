local preview = require('fff.file_picker.preview')
local root, target, buffers

local function loaded_buffer(path, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, path)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  buffers[#buffers + 1] = buf
  return buf
end

describe('preview reuse of loaded buffers', function()
  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, 'p')
    vim.fn.writefile({ 'return "on disk"' }, root .. '/source.lua')
    buffers = {}
    target = vim.api.nvim_create_buf(false, true)
    preview.setup(require('fff.conf').get().preview)
  end)

  after_each(function()
    preview.clear_buffer(target)
    vim.api.nvim_buf_delete(target, { force = true })
    for _, buf in ipairs(buffers) do
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end
    vim.fn.delete(root, 'rf')
  end)

  it('shows unsaved content from an exact file buffer', function()
    loaded_buffer(root .. '/other.lua', { 'return "other"' })
    loaded_buffer(root .. '/source.lua', { 'return "unsaved"' })
    assert.is_true(preview.preview_file(root .. '/source.lua', target))
    assert.are.same({ 'return "unsaved"' }, vim.api.nvim_buf_get_lines(target, 0, -1, false))
  end)

  it('preserves symlink fallback for a buffer opened through an alias', function()
    local linked, err = vim.uv.fs_symlink(root .. '/source.lua', root .. '/alias.lua')
    if not linked and vim.fn.has('win32') == 1 then
      pending('symlink creation unavailable: ' .. tostring(err))
      return
    end
    assert(linked, err)
    loaded_buffer(root .. '/alias.lua', { 'return "unsaved alias"' })
    assert.is_true(preview.preview_file(root .. '/source.lua', target))
    assert.are.same({ 'return "unsaved alias"' }, vim.api.nvim_buf_get_lines(target, 0, -1, false))
  end)

  it('resolves a symlink request to an exact loaded file', function()
    local linked, err = vim.uv.fs_symlink(root .. '/source.lua', root .. '/alias.lua')
    if not linked and vim.fn.has('win32') == 1 then
      pending('symlink creation unavailable: ' .. tostring(err))
      return
    end
    assert(linked, err)
    loaded_buffer(root .. '/source.lua', { 'return "unsaved target"' })
    assert.is_true(preview.preview_file(root .. '/alias.lua', target))
    assert.are.same({ 'return "unsaved target"' }, vim.api.nvim_buf_get_lines(target, 0, -1, false))
  end)

  it('reads the file when its existing buffer is unloaded', function()
    local source = loaded_buffer(root .. '/source.lua', { 'return "discarded"' })
    vim.api.nvim_buf_delete(source, { unload = true, force = true })
    assert.is_true(preview.preview_file(root .. '/source.lua', target))
    assert.is_true(
      vim.wait(2000, function() return vim.api.nvim_buf_get_lines(target, 0, 1, false)[1] == 'return "on disk"' end)
    )
  end)
end)
