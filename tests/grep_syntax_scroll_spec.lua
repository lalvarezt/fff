local child
local root = vim.fn.getcwd()

describe('grep syntax scroll events', function()
  before_each(function()
    child = require('mini.test').new_child_neovim()
    child.start({ '--clean', '-n', '-i', 'NONE' })
    child.o.columns, child.o.lines = 160, 48
    child.lua(string.format(
      [[
      vim.opt.runtimepath:prepend(%q)
      vim.cmd('cd ' .. vim.fn.fnameescape(%q))
      vim.g.fff = { logging = { enabled = false }, suggestions = { enabled = false },
        frecency = { enabled = false }, history = { enabled = false } }
      require('fff.core').ensure_initialized()
      require('fff.rust').wait_for_initial_scan(8000)
      _G.assert_visible_syntax = function()
        local S = require('fff.picker_ui.picker_ui').state
        local view = vim.api.nvim_win_call(S.list_win, function()
          return { vim.fn.line('w0'), vim.fn.line('w$') }
        end)
        local count = 0
        for i, mapping in pairs(S.item_to_lines) do
          if mapping.last >= view[1] and mapping.last <= view[2] then
            assert(S.last_render_ctx._syntax_highlighted[i], 'Missing syntax for visible item ' .. i)
            count = count + 1
          end
        end
        assert(count > 0)
        return view
      end
    ]],
      root,
      root
    ))
  end)

  after_each(function() child.stop() end)

  for _, position in ipairs({ 'top', 'bottom' }) do
    it('highlights newly visible rows after native scrolling with a ' .. position .. ' prompt', function()
      child.lua(string.format(
        [[
        local picker = require('fff.picker_ui.picker_ui')
        picker.open({ mode = 'grep', query = 'local', renderer = require('fff.picker_ui.grep_renderer'),
          layout = { prompt_position = %q } })
        vim.wait(30)
        local items = {}
        for i = 1, 200 do
          items[i] = { name = 'renderer.lua', relative_path = 'lua/fff/picker_ui/renderer.lua',
            directory = 'lua/fff/picker_ui', line_number = i, col = 0,
            line_content = 'local value_' .. i .. ' = require("fff")', match_ranges = { { 0, 5 } } }
        end
        picker.state.filtered_items = items
        picker.render_list()
        vim.cmd('redraw')
        assert_visible_syntax()
        _G.scroll_events = 0
        vim.api.nvim_create_autocmd('WinScrolled', {
          pattern = tostring(picker.state.list_win),
          callback = function() scroll_events = scroll_events + 1 end,
        })
      ]],
        position
      ))
      child.lua(string.format(
        [[
        local S = require('fff.picker_ui.picker_ui').state
        local total = vim.api.nvim_buf_line_count(S.list_buf)
        vim.api.nvim_win_call(S.list_win, function()
          local first = %s
          vim.fn.winrestview({ topline = first, lnum = first + 10 })
          vim.cmd('redraw')
        end)
      ]],
        position == 'top' and '60' or 'math.max(1, total - 90)'
      ))
      child.lua('vim.wait(30); assert(scroll_events > 0); assert_visible_syntax()')
      child.lua([[
        local picker = require('fff.picker_ui.picker_ui')
        picker.close()
        picker.open({ mode = 'grep', query = 'local', renderer = require('fff.picker_ui.grep_renderer') })
        vim.wait(30)
        assert_visible_syntax()
        picker.close()
      ]])
    end)
  end
end)
