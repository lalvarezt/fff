local grep = require('fff.picker_ui.grep_renderer')

local function original_truncation(content, available)
  if vim.fn.strdisplaywidth(content) > available and available > 3 then
    local lo, hi = 0, vim.fn.strchars(content)
    while lo < hi do
      local mid = math.floor((lo + hi + 1) / 2)
      if vim.fn.strdisplaywidth(vim.fn.strcharpart(content, 0, mid)) <= available - 1 then
        lo = mid
      else
        hi = mid - 1
      end
    end
    return vim.fn.strcharpart(content, 0, lo) .. '…'
  end
  return content
end

describe('grep content truncation', function()
  for _, position in ipairs({ 'top', 'bottom' }) do
    it('preserves byte offsets and Unicode content with a ' .. position .. ' prompt', function()
      local config = require('fff.conf').get()
      for _, text in ipairs({
        '',
        'short',
        string.rep('a', 10000),
        string.rep('界é', 1000),
        string.rep('é', 1000),
        'a' .. string.rep('́', 500),
        string.rep('\tvalue', 1000),
        string.rep('👩‍💻', 1000),
      }) do
        for _, width in ipairs({ 10, 15, 80, 150 }) do
          local item = { name = 'main.lua', relative_path = 'main.lua', line_number = 12, col = 0, line_content = text }
          local ctx = {
            config = config,
            win_width = width,
            prompt_position = position,
            iter_start = 1,
            grep_last_file = 'main.lua',
          }
          local line = grep.render_line(item, ctx, 2)[1]
          local expected = original_truncation(text, width - #' :12:1  ' - 2)
          assert.are.equal(expected, item._trimmed_content)
          assert.are.equal(#' :12:1  ', item._content_offset)
          assert.are.equal(' :12:1  ' .. expected, line:sub(1, #' :12:1  ' + #expected))
        end
      end
    end)
  end
end)
