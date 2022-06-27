local async = require("neotest.async")
local Path = require("plenary.path")
local lib = require("neotest.lib")

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
local function transform_test_name(name)
	return name:gsub("^'(.*)'$", "%1")
end

local function generate_position_id(position, namespaces)
	local prefix = {}
	for _, namespace in ipairs(namespaces) do
		if namespace.type ~= "file" then
			table.insert(prefix, namespace.name)
		end
	end
	local name = transform_test_name(position.name)
	return table.concat(vim.tbl_flatten({ position.path, prefix, name }), "::")
end

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
	return lib.treesitter.parse_positions(path, query, {
		require_namespaces = false,
		position_id = generate_position_id,
	})
end

function adapter.build_spec(args)
	local results_path = async.fn.tempname()
	local tree = args.tree
	if not tree then
		return
	end
	local position = tree:data()
	vim.pretty_print(position)
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
	vim.pretty_print(testNames)

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

function adapter.results(_, result, tree)
	local success, data = pcall(lib.files.read, result.output)
	if not success then
		return {}
	end
	vim.pretty_print(data)
	local results = {}
	return results
end

setmetatable(adapter, {
	__call = function()
		return adapter
	end,
})

return adapter
