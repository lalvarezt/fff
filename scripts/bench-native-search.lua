local root = vim.env.FFF_BENCH_ROOT or vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
vim.cmd('cd ' .. vim.fn.fnameescape(vim.env.FFF_BENCH_PATH or root))
vim.g.fff = {
  logging = { enabled = false },
  frecency = { enabled = false },
  history = { enabled = false },
}
require('fff.core').ensure_initialized()
assert(require('fff.rust').wait_for_initial_scan(15000))

local grep = require('fff.picker_ui.grep_renderer')
local page_size = tonumber(vim.env.FFF_BENCH_PAGE_SIZE) or 161
local config = vim.env.FFF_BENCH_RAW_CONFIG and {} or nil
local search = grep.search
for _, mode in ipairs({ 'plain', 'regex', 'fuzzy' }) do
  for _, query in ipairs({ 'm', 'main' }) do
    local result
    for _ = 1, 3 do
      result = search(query, 0, page_size, config, mode)
    end
    local samples = {}
    for i = 1, 25 do
      local start = vim.uv.hrtime()
      result = search(query, 0, page_size, config, mode)
      samples[i] = (vim.uv.hrtime() - start) / 1e6
    end
    table.sort(samples)
    print(
      string.format(
        '%s query=%s median_ms=%.4f p95_ms=%.4f items=%d searched=%d total=%d',
        mode,
        query,
        samples[13],
        samples[24],
        #result.items,
        result.total_files_searched,
        result.total_files
      )
    )
  end
end
