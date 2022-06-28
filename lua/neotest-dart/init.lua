local async = require("neotest.async")
local Path = require("plenary.path")
local lib = require("neotest.lib")
local logger = require("neotest.logging")

---@type neotest.Adapter
local adapter = { name = "neotest-dart" }

adapter.root = lib.files.match_root_pattern("dart")

function adapter.is_test_file(file_path)
  if not vim.endswith(file_path, ".dart") then
    return false
  end
  local elems = vim.split(file_path, Path.path.sep)
  local file_name = elems[#elems]
  local is_test = vim.endswith(file_name, "_test.dart")
  return is_test
end

--- remove surrounding quotes
---@param name string
---@param prepare_for_summary boolean? indicates that additional whitespace
--- trimming is needed to look pretty in summary
---@return string
local function remove_surrounding_quates(name, prepare_for_summary)
  local trimmed = name:gsub("^'''(.*)'''$", "%1"):gsub("^'(.*)'$", "%1"):gsub('^"(.*)"$', "%1"):gsub("^\n(.*)$", "%1")
  if prepare_for_summary then
    return trimmed:gsub("^%s+(.*)\n.%s*$", "%1")
  end
  return trimmed
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
    if position.type == "test" or position.type == "namespace" then
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
  if position.type == "dir" then
    return
  end
  local testNames = {}
  if position.type == "namespace" or position.type == "test" then
    table.insert(testNames, 1, { position.name })
    for parent in tree:iter_parents() do
      local parent_pos = parent:data()
      if parent_pos.type ~= "namespace" then
        break
      end
      table.insert(testNames, 1, { parent_pos.name })
    end
  end

  local command = vim.tbl_flatten({
    "fvm",
    "flutter",
    "test",
    position.path,
    "--reporter",
    "json",
  })

  return {
    command = table.concat(command, " "),
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
      table.insert(map, line.test.id, line.test.name)
    end
  end
  return map
end

--- Collects test output to single table where test information is accessible
--- by test name
---@param lines string[]
---@return table
local function marshal_test_results(lines)
  local tests = {}
  local parsed_jsons = {}
  for _, line in ipairs(lines) do
    if line ~= "" then
      local ok, parsed = pcall(vim.json.decode, line, { luanil = { object = true } })
      if not ok then
        logger.error(string.format("Failed to parse test output: \n%s\n%s", parsed, line))
        return tests
      end
      table.insert(parsed_jsons, parsed)
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
        tests[test_name] = test_data
      end
    end
  end
  return tests
end

--- position id contains information enought to construct test name
--- @returns string
local function construct_test_name_from_position(position_id)
  local parts = vim.split(position_id, "::")
  local name_components = {}
  for index, value in ipairs(parts) do
    if index > 1 then
      local component = remove_surrounding_quates(value)
      table.insert(name_components, component)
    end
  end
  local name = table.concat(name_components, " ")
  vim.pretty_print(name)
  return name
end

local dart_to_neotest_status_map = {
  success = "passed",
  error = "failed",
}

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
  local lines = vim.split(data, "\n")
  local test_results = marshal_test_results(lines)
  local results = {}
  for _, node in tree:iter_nodes() do
    local value = node:data()
    if value.type == "test" then
      local test_name = construct_test_name_from_position(value.id)
      local test_result = test_results[test_name]
      if test_result then
        results[value.id] = {
          status = dart_to_neotest_status_map[test_result.result],
          short = test_result.message,
        }
      end
    end
  end
  return results
end

setmetatable(adapter, {
  __call = function()
    return adapter
  end,
})

return adapter
