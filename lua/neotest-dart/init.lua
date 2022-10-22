local async = require('neotest.async')
local Path = require('plenary.path')
local lib = require('neotest.lib')
local utils = require('neotest-dart.utils')
local parser = require('neotest-dart.parser')
local outline_parser = require('neotest-dart.lsp_outline_parser')

---@type neotest.Adapter
local adapter = { name = 'neotest-dart' }

adapter.root = lib.files.match_root_pattern('dart')

--- Command to use for running tests. Value is set from config
local command = 'flutter'

local outline = {}

function adapter.is_test_file(file_path)
  if not vim.endswith(file_path, '.dart') then
    return false
  end
  local elems = vim.split(file_path, Path.path.sep)
  local file_name = elems[#elems]
  local is_test = vim.endswith(file_name, 'test.dart')
  return is_test
end

--- Dart LSP has all the correct test names - they should take precedence if available
local function on_outline_changed(data)
  local new_outline = outline_parser.parse(data)
  for key, value in pairs(new_outline) do
    outline[key] = value
  end
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
      local outline_test_name = utils.get_test_name_from_outline(position, outline)
      if outline_test_name then
        local parts = vim.split(position.id, '::')
        -- last component is test name
        parts[#parts] = outline_test_name
        position.id = table.concat(parts, '::')
        position.name = outline_test_name
      else
        position.name = utils.remove_surrounding_quates(position.name, true)
      end
    end
  end
  return tree
end

local function construct_test_argument(position, strategy)
  local test_argument = {}
  if position.type == 'test' then
    local test_name = utils.construct_test_name(position, outline)
    table.insert(test_argument, '--plain-name')
    if strategy == 'dap' then
      table.insert(test_argument, test_name)
    else
      test_name = test_name:gsub('"', '\\"')
      table.insert(test_argument, '"' .. test_name .. '"')
    end
  end
  return test_argument
end

---@return table?
local function get_strategy_config(strategy, path, script_args)
  local config = {
    dap = function()
      local status_ok, dap = pcall(require, 'dap')
      if not status_ok then
        return
      end
      dap.adapters.dart_test = {
        type = 'executable',
        command = 'flutter',
        args = { 'debug-adapter', '--test' },
        options = { -- Dartls is slow to start so avoid warnings from nvim-dap
          initialize_timeout_sec = 30,
        },
      }
      return {
        type = 'dart_test',
        name = 'Neotest Debugger',
        request = 'launch',
        program = path,
        args = script_args,
      }
    end,
  }
  if config[strategy] then
    return config[strategy]()
  end
end

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function adapter.build_spec(args)
  local partial_output = {}
  local results_path = async.fn.tempname()
  local tree = args.tree
  if not tree then
    return {}
  end
  local position = tree:data()
  if position.type == 'dir' then
    return {}
  end
  local test_argument = construct_test_argument(position, args.strategy)

  local command_parts = {
    command,
    'test',
    position.path,
    test_argument,
    '--reporter',
    'json',
  }

  local strategy_config = get_strategy_config(args.strategy, position.path, test_argument)

  local full_command = table.concat(vim.tbl_flatten(command_parts), ' ')
  return {
    command = full_command,
    context = {
      results_path = results_path,
      file = position.path,
    },
    strategy = strategy_config,
    stream = function(data)
      return function()
        local lines = data()
        for _, line in ipairs(lines) do
          table.insert(partial_output, line)
        end
        local tests = parser.parse_lines(tree, partial_output, outline)
        return tests
      end
    end,
  }
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
  local tests = parser.parse_lines(tree, lines, outline)
  return tests
end

setmetatable(adapter, {
  __call = function(_, config)
    if config.command then
      command = config.command
    end
    if config.use_lsp or true then
      vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client.name == 'dartls' then
            local originalOutline = client.handlers['dart/textDocument/publishOutline']
            client.handlers['dart/textDocument/publishOutline'] = function(_, data)
              originalOutline(_, data)
              on_outline_changed(data)
            end
          end
        end,
      })
    end
    return adapter
  end,
})

return adapter
