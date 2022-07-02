local async = require('neotest.async')
local Path = require('plenary.path')
local lib = require('neotest.lib')

---@type neotest.Adapter
local adapter = { name = 'neotest-dart' }

adapter.root = lib.files.match_root_pattern('dart')

--- Config property to control if FVM should be used
local fvm = false

function adapter.is_test_file(file_path)
  if not vim.endswith(file_path, '.dart') then
    return false
  end
  local elems = vim.split(file_path, Path.path.sep)
  local file_name = elems[#elems]
  local is_test = vim.endswith(file_name, '_test.dart')
  return is_test
end

--- remove surrounding quotes
---@param name string
---@param prepare_for_summary boolean? indicates that additional whitespace
--- trimming is needed to look pretty in summary
---@return string
local function remove_surrounding_quates(name, prepare_for_summary)
  local trimmed = name
    :gsub("^'''(.*)'''$", '%1')
    :gsub("^'(.*)'$", '%1')
    :gsub('^"(.*)"$', '%1')
    :gsub('^\n(.*)$', '%1')
  if prepare_for_summary then
    return trimmed:gsub('^%s+(.*)\n.%s*$', '%1')
  end
  return trimmed
end

--- position id contains information enought to construct test name
--- @returns string
local function construct_test_name_from_position(position_id)
  local parts = vim.split(position_id, '::')
  local name_components = {}
  for index, value in ipairs(parts) do
    if index > 1 then
      local component = remove_surrounding_quates(value)
      table.insert(name_components, component)
    end
  end
  local name = table.concat(name_components, ' ')
  return name
end

---@async
---@return neotest.Tree| nil
function adapter.discover_positions(path)
  local query = [[
  ;; group blocks
  (expression_statement 
    (identifier) @group (#eq? @group "group")
    (selector (argument_part (arguments (argument (string_literal) @namespace.name )))))
    @namespace.definition

  ;; tests blocks
  (expression_statement 
    (identifier) @testFunc (#any-of? @testFunc "test" "testWidgets")
    (selector (argument_part (arguments (argument (string_literal) @test.name))))) 
    @test.definition
  ]]
  local tree = lib.treesitter.parse_positions(path, query, {
    require_namespaces = false,
  })
  for _, position in tree:iter() do
    if position.type == 'test' or position.type == 'namespace' then
      position.name = remove_surrounding_quates(position.name, true)
    end
  end
  return tree
end

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function adapter.build_spec(args)
  local results_path = async.fn.tempname()
  local tree = args.tree
  if not tree then
    return
  end
  local position = tree:data()
  if position.type == 'dir' then
    return
  end
  local test_argument = ''
  if position.type == 'test' then
    local test_name = construct_test_name_from_position(position.id)
    test_name = test_name:gsub('"', '\\"')
    test_argument = '--plain-name "' .. test_name .. '"'
  end

  local command_parts = {
    fvm and 'fvm' or '',
    'flutter',
    'test',
    position.path,
    test_argument,
    '--reporter',
    'json',
  }
  local command = table.concat(command_parts, ' ')
  return {
    command = command,
    context = {
      results_path = results_path,
      file = position.path,
    },
  }
end

local function get_test_names_by_ids(parsed_jsons)
  local map = {}

  for _, line in ipairs(parsed_jsons) do
    if line.test then
      map[line.test.id] = line.test.name
    end
  end
  return map
end

--- Collects test output to single table where test information is accessible
--- by test name
---@param lines string[]
---@return table, table
local function marshal_test_results(lines)
  local tests = {}
  local parsed_jsons = {}
  local unparsable_lines = {}
  for _, line in ipairs(lines) do
    if line ~= '' then
      local ok, parsed = pcall(vim.json.decode, line, { luanil = { object = true } })
      if ok then
        table.insert(parsed_jsons, parsed)
      else
        table.insert(unparsable_lines, line)
      end
    end
  end
  local test_names_by_ids = get_test_names_by_ids(parsed_jsons)

  for _, json in ipairs(parsed_jsons) do
    if json.testID then
      local test_name = test_names_by_ids[json.testID]
      if test_name then
        local test_data = tests[test_name] or {}
        if json.result then
          test_data.result = json.result
        end
        if json.message then
          test_data.message = json.message
        end
        if json.error then
          test_data.error = json.error
        end
        test_data.skipped = json.skipped
        test_data.time = json.time
        tests[test_name] = test_data
      end
    end
  end
  return tests, unparsable_lines
end

local dart_to_neotest_status_map = {
  success = 'passed',
  error = 'failed',
}

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

---@param test_result table dart test result
---@param unparsable_lines table lines that was not possible to convert to json
---@returns string path to output file
local function prepare_neotest_output(test_result, unparsable_lines)
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
  if test_result.time then
    local test_time = format_duration(test_result.time)
    table.insert(file_output, 'Elapsed: ' .. test_time)
  end
  local flatten = vim.tbl_flatten(file_output)
  vim.fn.writefile(flatten, fname, 'b')
  return fname
end

---@param test_result table
---@returns string
local function construct_neotest_status(test_result)
  if test_result.skipped then
    return 'skipped'
  end
  return dart_to_neotest_status_map[test_result.result]
end

---@async
---@param _ neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result[]>
function adapter.results(_, result, tree)
  local success, data = pcall(lib.files.read, result.output)
  if not success then
    return {}
  end
  local lines = vim.split(data, '\n')
  local tests, unparsable_lines = marshal_test_results(lines)
  local results = {}
  for _, node in tree:iter_nodes() do
    local value = node:data()
    if value.type == 'test' then
      local test_name = construct_test_name_from_position(value.id)
      local test_result = tests[test_name]
      if test_result then
        local neotest_result = {
          status = construct_neotest_status(test_result),
          short = highlight_as_error(test_result.message),
          output = prepare_neotest_output(test_result, unparsable_lines),
        }
        results[value.id] = neotest_result
      end
    end
  end
  return results
end

setmetatable(adapter, {
  __call = function(_, config)
    fvm = config.fvm
    return adapter
  end,
})

return adapter
