local picker = require('fff.picker_ui.picker_ui')
local file_picker = require('fff.file_picker')
local fuzzy = require('fff.fuzzy')
local counts, originals

describe('picker opening and input searches', function()
  before_each(function()
    vim.o.columns = 160
    vim.o.lines = 48
    vim.g.fff = {
      logging = { enabled = false },
      suggestions = { enabled = false },
      frecency = { enabled = false },
      history = { enabled = false },
      git = { status_updates = 'manual' },
    }
    local git = require('fff.conf').get().git
    local git_status_updates = git.status_updates
    git.status_updates = 'manual'
    require('fff.core').ensure_initialized()
    require('fff.rust').wait_for_initial_scan(8000)
    counts = { files = 0, grep = 0 }
    originals = {
      files = file_picker.search_files_paginated,
      grep = fuzzy.live_grep,
      progress = file_picker.get_scan_progress,
      git_status_updates = git_status_updates,
    }
    file_picker.search_files_paginated = function(...)
      counts.files = counts.files + 1
      return originals.files(...)
    end
    fuzzy.live_grep = function(...)
      counts.grep = counts.grep + 1
      return originals.grep(...)
    end
  end)

  after_each(function()
    picker.close()
    file_picker.search_files_paginated = originals.files
    fuzzy.live_grep = originals.grep
    file_picker.get_scan_progress = originals.progress
    require('fff.conf').get().git.status_updates = originals.git_status_updates
    vim.wait(20)
  end)

  for _, position in ipairs({ 'top', 'bottom' }) do
    for _, mode in ipairs({ 'files', 'grep' }) do
      it('searches a warm prefilled ' .. mode .. ' picker once with a ' .. position .. ' prompt', function()
        picker.open({
          mode = mode,
          query = 'main',
          renderer = mode == 'grep' and require('fff.picker_ui.grep_renderer') or nil,
          layout = { prompt_position = position },
        })
        vim.wait(40)
        assert.are.equal(1, counts[mode])
        assert.are.equal('main', picker.state.query)
        assert.is_true(vim.api.nvim_buf_is_valid(picker.state.list_buf))
        assert.is_true(vim.api.nvim_buf_is_valid(picker.state.preview_buf))
        local prompt = picker.state.config.prompt
        for _, query in ipairs({ 'm', 'ma', 'main' }) do
          vim.api.nvim_buf_set_lines(picker.state.input_buf, 0, -1, false, { prompt .. query })
        end
        vim.wait(40)
        assert.are.equal(2, counts[mode])
        assert.are.equal('main', picker.state.query)
      end)
    end

    it('refreshes after an initial scan and keeps queued input with a ' .. position .. ' prompt', function()
      local scanning = true
      file_picker.get_scan_progress = function()
        local progress = originals.progress()
        progress.is_scanning = scanning
        return progress
      end
      picker.open({ layout = { prompt_position = position } })
      assert.are.equal(1, counts.files)
      scanning = false
      vim.api.nvim_buf_set_lines(picker.state.input_buf, 0, -1, false, { picker.state.config.prompt .. 'main' })
      picker.update_results()
      vim.wait(160)
      assert.are.equal('main', picker.state.query)
      assert.is_true(counts.files >= 3)
      assert.is_true(#picker.state.filtered_items > 0)
    end)
  end
end)
