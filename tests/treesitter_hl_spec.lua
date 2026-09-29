local ts = require('fff.treesitter_hl')
local original_get_parser = vim.treesitter.get_parser
local parser_calls

describe('grep Tree-sitter highlight cache', function()
  before_each(function()
    ts.cleanup()
    parser_calls = 0
    vim.treesitter.get_parser = function(buf, lang)
      parser_calls = parser_calls + 1
      return original_get_parser(buf, lang == 'test_alias' and 'lua' or lang)
    end
  end)

  after_each(function()
    vim.treesitter.get_parser = original_get_parser
    ts.cleanup()
  end)

  it('reuses syntax highlights after highlighting another row', function()
    local text = 'local value = require("fff")'
    local expected = ts.get_line_highlights(text, 'lua')
    assert.is_true(#expected > 0)
    ts.get_line_highlights('return value', 'lua')
    assert.are.same(expected, ts.get_line_highlights(text, 'lua'))
    assert.are.equal(2, parser_calls)
  end)

  it('separates identical text in different languages', function()
    local text = 'local value = 1'
    ts.get_line_highlights(text, 'lua')
    ts.get_line_highlights(text, 'test_alias')
    ts.get_line_highlights(text, 'lua')
    ts.get_line_highlights(text, 'test_alias')
    assert.are.equal(2, parser_calls)
  end)

  it('drops cached highlights when the picker closes', function()
    local text = 'local value = 1'
    local expected = ts.get_line_highlights(text, 'lua')
    ts.cleanup()
    assert.are.same(expected, ts.get_line_highlights(text, 'lua'))
    assert.are.equal(2, parser_calls)
  end)

  it('evicts old lines rather than retaining every search result', function()
    local text = 'local value = 0'
    local expected = ts.get_line_highlights(text, 'lua')
    for i = 1, 256 do
      ts.get_line_highlights('local value = ' .. i, 'lua')
    end
    assert.are.same(expected, ts.get_line_highlights(text, 'lua'))
    assert.are.equal(258, parser_calls)
  end)

  it('does not retain oversized source lines', function()
    local text = '--' .. string.rep('a', 4096)
    local expected = ts.get_line_highlights(text, 'lua')
    assert.are.same(expected, ts.get_line_highlights(text, 'lua'))
    assert.are.equal(2, parser_calls)
  end)

  it('retries a parser failure', function()
    vim.treesitter.get_parser = function()
      parser_calls = parser_calls + 1
      error('parser unavailable')
    end
    assert.are.same({}, ts.get_line_highlights('local value = 1', 'lua'))
    vim.treesitter.get_parser = function(buf, lang)
      parser_calls = parser_calls + 1
      return original_get_parser(buf, lang)
    end
    assert.is_true(#ts.get_line_highlights('local value = 1', 'lua') > 0)
    assert.are.equal(2, parser_calls)
  end)
end)
