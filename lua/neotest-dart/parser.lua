local utils = require('neotest-dart.utils')
local async = require('neotest.async')

local M = {}

local dart_to_neotest_status_map = {
  success = 'passed',
  error = 'failed',
  failure = 'failed',
}

---@param test_result table
---@returns string
local function construct_neotest_status(test_result)
  if test_result.skipped then
    return 'skipped'
  end
  if test_result.status == nil then
    return 'running'
  end
  return test_result.status
end

local function normalize_uri(uri)
  if not uri then
    return nil
  end

  return uri:gsub('^file://', '')
end

local function runtime_position_key(test)
  if not test then
    return nil
  end

  local path = normalize_uri(test.root_url) or normalize_uri(test.url)
  local line = test.root_line or test.line
  local column = test.root_column or test.column
  if not path or not line or not column then
    return nil
  end

  return string.format('%s::%s:%s', path, line, column)
end

local function append_message(target, message)
  if not message then
    return
  end

  if target.message == nil then
    target.message = message
    return
  end

  target.message = target.message .. '\n' .. message
end

---@param lines string[]
---@return table, table, table
local function marshal_test_results(lines)
  local tests_by_id = {}
  local tests_by_name = {}
  local runtimes_by_position = {}
  local unparsable_lines = {}

  for _, line in ipairs(lines) do
    if line ~= '' then
      local ok, json = pcall(vim.json.decode, line, { luanil = { object = true } })
      if not ok then
        table.insert(unparsable_lines, line)
      elseif json.test then
        local id = json.test.id
        if id then
          local test_data = tests_by_id[id] or {}
          test_data.name = json.test.name
          test_data.position_key = runtime_position_key(json.test)
          tests_by_id[id] = test_data

          if test_data.name then
            tests_by_name[test_data.name] = test_data
          end

          if test_data.position_key then
            runtimes_by_position[test_data.position_key] = runtimes_by_position[test_data.position_key] or {}
            table.insert(runtimes_by_position[test_data.position_key], test_data)
          end
        end
      elseif json.testID then
        local test_data = tests_by_id[json.testID]
        if test_data then
          if json.result then
            test_data.status = dart_to_neotest_status_map[json.result]
          end
          append_message(test_data, json.message)
          if json.error then
            test_data.error = json.error
            test_data.stack_trace = json.stackTrace
          end
          if json.skipped ~= nil then
            test_data.skipped = json.skipped
          end
          if json.time then
            test_data.time = json.time
          end
          if json.hidden ~= nil then
            test_data.hidden = json.hidden
          end
        end
      end
    end
  end

  return runtimes_by_position, tests_by_name, unparsable_lines
end

local function highlight_as_error(message)
  if message == nil then
    return nil
  end
  return message:gsub('^', '[31m'):gsub('$', '[0m')
end

---@returns string formated duration
local function format_duration(milliseconds)
  local seconds = milliseconds / 1000
  if seconds > 0 then
    return seconds .. 's.'
  end
  return milliseconds .. 'ms.'
end

---@param output string
---@return string
local function sanitize_output(output)
  if not output then
    return output
  end
  return output:gsub('\r', '')
end

---@param error string
---@return string
local function format_error(error)
  -- remove file path from the beggining
  error = error:gsub("^'file:.*dart': (.*)$", '%1')
  return highlight_as_error(error)
end

---@param test_result table dart test result
---@param unparsable_lines table lines that was not possible to convert to json
---@param opts table?
---@returns string path to output file
local function prepare_neotest_output(test_result, unparsable_lines, opts)
  opts = opts or {}
  local fname = async.fn.tempname()
  local file_output = {}
  if unparsable_lines then
    for _, line in ipairs(unparsable_lines) do
      local sanitized = sanitize_output(line)
      table.insert(file_output, sanitized)
    end
  end
  local message = test_result.message
  if message then
    message = highlight_as_error(message)
    local messages = vim.split(message, '\n')
    table.insert(file_output, messages)
  end
  if test_result.error then
    local error = format_error(test_result.error)
    table.insert(file_output, error)
  end
  if test_result.stack_trace then
    local stack_trace = highlight_as_error(test_result.stack_trace)
    local stack_trace_lines = vim.split(stack_trace, '\n')
    table.insert(file_output, '')
    table.insert(file_output, stack_trace_lines)
  end
  if test_result.time then
    local test_time = format_duration(test_result.time)
    table.insert(file_output, 'Elapsed: ' .. test_time)
  end
  local flatten = vim.iter(file_output):flatten():totable()
  if opts.write_output == false then
    return table.concat(flatten, '\n')
  end
  vim.fn.writefile(flatten, fname, 'b')
  return fname
end

local function get_diagnostic_line(text)
  if not text then
    return nil
  end

  local patterns = {
    '[^%s:]+_test%.dart line (%d+)',
    '[^%s:]+_test%.dart (%d+):',
  }

  for _, pattern in ipairs(patterns) do
    local _, _, str = text:find(pattern)
    if str then
      return tonumber(str) - 1
    end
  end
end

local function construct_diagnostic_errors(test_result)
  local line
  local message
  if test_result.status == 'failed' then
    if test_result.message then
      line = get_diagnostic_line(test_result.message)
      message = test_result.message
    end
    if test_result.error then
      if test_result.stack_trace then
        line = get_diagnostic_line(test_result.stack_trace) or line
      end
      if not message then
        message = test_result.error
      end
    end
    if message then
      message = message
        :gsub(
          '══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════',
          ''
        )
        :gsub('The following TestFailure was thrown running a test:', '')
      return { { message = message, line = line } }
    end
  end
end

local function merge_test_results(test_results)
  local merged = {}

  for _, test_result in ipairs(test_results) do
    if test_result and not test_result.hidden then
      if test_result.status == 'failed' then
        merged.status = 'failed'
      elseif merged.status ~= 'failed' and test_result.status == 'passed' then
        merged.status = 'passed'
      elseif merged.status == nil and test_result.skipped then
        merged.status = 'skipped'
      end

      merged.skipped = merged.skipped == nil and test_result.skipped or (merged.skipped and test_result.skipped)
      merged.time = (merged.time or 0) + (test_result.time or 0)

      append_message(merged, test_result.message)
      if test_result.error then
        merged.error = merged.error and (merged.error .. '\n' .. test_result.error) or test_result.error
      end
      if test_result.stack_trace then
        merged.stack_trace = merged.stack_trace and (merged.stack_trace .. '\n' .. test_result.stack_trace)
          or test_result.stack_trace
      end
    end
  end

  if merged.status == nil and merged.skipped then
    merged.status = 'skipped'
  end

  if merged.status == nil then
    return nil
  end

  return merged
end

M.parse_lines = function(tree, lines, outline, opts)
  local runtimes_by_position, tests_by_name, unparsable_lines = marshal_test_results(lines)
  local results = {}

  for _, node in tree:iter_nodes() do
    local value = node:data()
    if value.type == 'test' then
      local test_result = merge_test_results(runtimes_by_position[utils.position_key(value)] or {})
      if not test_result then
        local test_name = utils.construct_test_name(value, outline)
        test_result = tests_by_name[test_name]
      end

      if test_result then
        local neotest_result = {
          status = construct_neotest_status(test_result),
          short = highlight_as_error(test_result.message),
          output = prepare_neotest_output(test_result, unparsable_lines, opts),
          errors = construct_diagnostic_errors(test_result),
        }
        results[value.id] = neotest_result
      end
    end
  end

  return results
end

return M
