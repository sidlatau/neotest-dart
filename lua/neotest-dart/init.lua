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

-- remove surrounding quotes
---@return string
local function remove_surrounding_quates(name)
  return name:gsub("^'''(.*)'''$", "%1"):gsub("^'(.*)'$", "%1"):gsub('^"(.*)"$', "%1")
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
      position.name = remove_surrounding_quates(position.name)
    end
  end
  return tree
end

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

---@param lines string[]
---@return table
local function marshal_dart_output(lines)
  local tests = {}
  local parsedJsonLines = {}
  for _, line in ipairs(lines) do
    if line ~= "" then
      local ok, parsed = pcall(vim.json.decode, line, { luanil = { object = true } })
      if not ok then
        logger.error(string.format("Failed to parse test output: \n%s\n%s", parsed, line))
        return tests
      end
      table.insert(parsedJsonLines, parsed)
    end
  end
  local testNamesByIds = {}

  for _, line in ipairs(parsedJsonLines) do
    if line.test then
      table.insert(testNamesByIds, line.test.id, line.test.name)
    end
  end
  for _, line in ipairs(parsedJsonLines) do
    if line.testID then
      local testName = testNamesByIds[line.testID]
      if testName then
        local testData = tests[testName] or {}
        if line.result then
          testData.result = line.result
        end
        if line.message then
          testData.message = line.message
        end
        if line.error then
          testData.error = line.error
        end
        tests[testName] = testData
      end
    end
  end
  vim.pretty_print(tests)
  return tests
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
  local lines = vim.split(data, "\n")
  local test_result = marshal_dart_output(lines)
  local results = {}
  for _, node in tree:iter_nodes() do
    local value = node:data()
    if value.type == "test" then
      results[value.id] = {
        status = "failed",
        short = "Short",
      }
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
