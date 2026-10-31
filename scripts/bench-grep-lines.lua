local root = vim.env.FFF_BENCH_ROOT or vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(root)
vim.o.columns = 160
local grep = require('fff.picker_ui.grep_renderer')
local item = { name = 'main.lua', relative_path = 'main.lua', line_number = 1, col = 0 }
local ctx = { config = require('fff.conf').get(), win_width = 150, iter_start = 1, grep_last_file = 'main.lua' }
for _, case in ipairs({
  { 'ascii', string.rep('a', 80) },
  { 'ascii', string.rep('a', 1000) },
  { 'ascii', string.rep('a', 100000) },
  { 'ascii', string.rep('a', 1000000) },
  { 'unicode', string.rep('界', 33334) },
}) do
  item.line_content = case[2]
  local times = {}
  for sample = 1, 7 do
    collectgarbage('collect')
    local start = vim.uv.hrtime()
    for _ = 1, 100 do
      grep.render_line(item, ctx, 2)
    end
    times[sample] = (vim.uv.hrtime() - start) / 100 / 1e6
  end
  table.sort(times)
  print(string.format('grep %s bytes=%d render_ms=%.6f', case[1], #case[2], times[4]))
end
