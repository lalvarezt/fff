local root = vim.env.FFF_BENCH_ROOT or vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local workload = vim.env.FFF_BENCH_PATH or root
local output = vim.env.FFF_BENCH_OUTPUT or vim.fn.tempname() .. '.json'
local position = vim.env.FFF_BENCH_POSITION or 'top'
local kind = vim.env.FFF_BENCH_KIND or 'files'
local init = vim.env.FFF_BENCH_INIT or 'NONE'
local responses, marks, presented, trace, stderr = {}, {}, {}, {}, {}
local sequence, phase = 0, 0
local changed = false
local origin = vim.uv.hrtime()
local unpacker = vim.mpack.Unpacker()

local function elapsed() return (vim.uv.hrtime() - origin) / 1e6 end

local function receive(packet)
  if packet[1] == 1 then
    responses[packet[2]] = packet
  elseif packet[1] == 2 and packet[2] == 'fff_screen_mark' then
    marks[#marks + 1] = packet[3][1]
  elseif packet[1] == 2 and packet[2] == 'redraw' then
    local now = elapsed()
    if vim.env.FFF_BENCH_RECORD then trace[#trace + 1] = { time_ms = now, events = packet[3] } end
    for _, event in ipairs(packet[3]) do
      if event[1] == 'grid_line' or event[1] == 'grid_scroll' then changed = true end
      if event[1] == 'flush' and changed then
        for _, mark in ipairs(marks) do
          mark.flush_ms = now
          presented[#presented + 1] = mark
        end
        marks, changed = {}, false
      end
    end
  end
end

local job = vim.fn.jobstart({ 'nvim', '--embed', '--headless', '-u', init, '-i', 'NONE', '-n' }, {
  on_stdout = function(_, chunks)
    -- Job callbacks encode embedded NUL bytes as newlines.
    for i, line in ipairs(chunks) do
      chunks[i] = line:gsub('\n', '\0')
    end
    local data, offset = table.concat(chunks, '\n'), 1
    while offset <= #data do
      local packet
      packet, offset = unpacker(data, offset)
      if not packet then break end
      receive(packet)
    end
  end,
  on_stderr = function(_, lines) vim.list_extend(stderr, lines) end,
})
assert(job > 0)

local function send(method, args)
  sequence = sequence + 1
  vim.api.nvim_chan_send(job, vim.mpack.encode({ 0, sequence, method, args or {} }))
  return sequence
end

local function request(method, args)
  local id = send(method, args)
  assert(vim.wait(20000, function() return responses[id] ~= nil end, 1), table.concat(stderr, '\n'))
  local response = responses[id]
  responses[id] = nil
  assert(response[3] == vim.NIL, vim.inspect(response[3]))
  return response[4]
end

local function lua(code, args) return request('nvim_exec_lua', { code, args or {} }) end

request('nvim_ui_attach', { 120, 80, { rgb = true, ext_linegrid = true } })
local dimensions = lua('return {vim.o.columns, vim.o.lines}')
assert(dimensions[1] == 120 and dimensions[2] == 80)
lua(
  [[
  local root, workload = ...
  vim.opt.runtimepath:prepend(root)
  vim.cmd('cd ' .. vim.fn.fnameescape(workload))
  vim.g.fff = { logging = { enabled = false }, suggestions = { enabled = false },
    frecency = { enabled = false }, history = { enabled = false } }
  local picker = require('fff.picker_ui.picker_ui')
  local preview = require('fff.file_picker.preview')
  local target, attached
  local function mark(kind)
    local S = picker.state
    vim.rpcnotify(1, 'fff_screen_mark', { kind = kind, phase = _G.fff_screen_phase,
      query = S.query or '', cursor = S.cursor, items = #(S.filtered_items or {}) })
  end
  local function attach_preview()
    local buf = picker.state.preview_buf
    if not buf or buf == attached then return end
    attached = buf
    vim.api.nvim_buf_attach(buf, false, { on_lines = function()
      local current = target
      vim.schedule(function()
        if current and target == current and picker.state.preview_buf == buf and not preview.state.is_loading
          and picker.state.last_preview_file then mark('preview') end
      end)
    end })
  end
  for _, key in ipairs({'render_list', 'render_after_cursor_move'}) do
    local original = picker[key]
    picker[key] = function(...)
      local result = original(...)
      attach_preview()
      mark('list')
      return result
    end
  end
  local manager = require('fff.picker_ui.preview_manager')
  local original_preview = manager.update_preview
  local function update_preview(...)
    target = {}
    local result = original_preview(...)
    if not preview.state.is_loading then mark('preview') end
    return result
  end
  manager.update_preview = update_preview
  picker.update_preview = update_preview
  local original_close = picker.close
  picker.close = function(...)
    local result = original_close(...)
    mark('close')
    return result
  end
]],
  { root, workload }
)

local results = {}
local function measure(label, query, action, min_items, cursor)
  phase = phase + 1
  lua('_G.fff_screen_phase = ...', { phase })
  local start = elapsed()
  if vim.env.FFF_BENCH_RECORD then trace[#trace + 1] = { time_ms = start, action = label } end
  action()
  local found
  local expected = label == 'close' and 'close' or 'list'
  assert(
    vim.wait(20000, function()
      for _, mark in ipairs(presented) do
        if
          mark.phase == phase
          and mark.kind == expected
          and (expected == 'close' or mark.query == query)
          and (not min_items or mark.items >= min_items)
          and (not cursor or mark.cursor == cursor)
        then
          found = mark
          return true
        end
      end
      return false
    end, 1),
    label .. ' did not reach a redraw flush: ' .. table.concat(stderr, '\n')
  )
  local row = {
    action = label,
    query = query,
    cursor = found.cursor,
    items = found.items,
    results_ms = found.flush_ms - start,
  }
  if expected == 'list' and found.items > 0 then
    vim.wait(2000, function()
      for _, mark in ipairs(presented) do
        if
          mark.phase == phase
          and mark.kind == 'preview'
          and mark.query == query
          and mark.items >= (min_items or 0)
          and mark.cursor == found.cursor
        then
          row.preview_ms = mark.flush_ms - start
          return true
        end
      end
      return false
    end, 1)
  end
  results[#results + 1] = row
  return row
end

local function open()
  lua(
    [[
    local kind, position = ...
    local opts = { layout = { prompt_position = position } }
    if kind == 'files' then require('fff').find_files(opts)
    else opts.grep = { modes = {kind} }; require('fff').live_grep(opts) end
    assert(require('fff.picker_ui.picker_ui').state.config.layout.prompt_position == position)
  ]],
    { kind, position }
  )
end

local ok, err = pcall(function()
  measure('cold_open', '', open, kind == 'files' and 1 or 0)
  lua("require('fff.rust').wait_for_initial_scan(15000)")
  measure('first_key', 'm', function() send('nvim_input', { 'm' }) end, 1)
  measure('burst', 'main', function() send('nvim_input', { 'ain' }) end, 2)
  measure('clear_burst', '', function() send('nvim_input', { '<BS><BS><BS><BS>' }) end, kind == 'files' and 1 or 0)
  local query = ''
  for key in ('test'):gmatch('.') do
    query = query .. key
    measure('type_' .. query, query, function() send('nvim_input', { key }) end, 1)
  end
  for remaining = 3, 0, -1 do
    query = ('test'):sub(1, remaining)
    measure('erase_' .. remaining, query, function() send('nvim_input', { '<BS>' }) end, kind == 'files' and 1 or 0)
  end
  -- End on a distinct query so a coalesced no-op still has an observable redraw.
  measure('rapid_type_erase', 'm', function() send('nvim_input', { 'test<BS><BS><BS><BS>m' }) end, 1)
  measure('restore_main', 'main', function() send('nvim_input', { 'ain' }) end, 2)
  for i = 1, 8 do
    local key = position == 'bottom' and '<Up>' or '<Down>'
    measure('next_' .. i, 'main', function() send('nvim_input', { key }) end, 2, i + 1)
  end
  measure('close', 'main', function() send('nvim_input', { '<Esc>' }) end)
  measure('warm_open', '', open, kind == 'files' and 1 or 0)
end)

pcall(send, 'nvim_command', { 'qa!' })
vim.fn.jobwait({ job }, 1000)
vim.fn.writefile({
  vim.json.encode({
    columns = 120,
    lines = 80,
    position = position,
    mode = kind,
    workload = workload,
    results = results,
    error = not ok and tostring(err) or nil,
  }),
}, output)
if vim.env.FFF_BENCH_RECORD then
  local file = assert(io.open(vim.env.FFF_BENCH_RECORD, 'wb'))
  file:write(vim.json.encode({ columns = 120, lines = 80, frames = trace }))
  file:close()
end
assert(ok, err)
print('Screen benchmark: ' .. output)
