package.path = table.concat({
  vim.loop.cwd() .. '/lua/?.lua',
  vim.loop.cwd() .. '/lua/?/init.lua',
  package.path,
}, ';')

local failures = {}

local function reset_modules(names)
  for _, name in ipairs(names) do
    package.loaded[name] = nil
    package.preload[name] = nil
  end
end

local function assert_eq(actual, expected)
  assert(
    vim.deep_equal(actual, expected),
    string.format('Expected %s, got %s', vim.inspect(expected), vim.inspect(actual))
  )
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print('PASS ' .. name)
    return
  end

  table.insert(failures, name .. '\n' .. err)
  print('FAIL ' .. name)
end

test('outline parser extracts widget names', function()
  reset_modules({ 'neotest-dart.lsp_outline_parser' })
  local parser = require('neotest-dart.lsp_outline_parser')
  local data = {
    outline = {
      children = {
        {
          children = {
            {
              children = {
                {
                  codeRange = {
                    ['end'] = { character = 6, line = 6 },
                    start = { character = 4, line = 4 },
                  },
                  element = {
                    kind = 'UNIT_TEST_TEST',
                    name = 'testWidgets("a \' \' b")',
                  },
                },
              },
            },
          },
        },
      },
    },
    uri = 'file:///tmp/project/test/foo_test.dart',
  }

  local output = parser.parse(data)
  assert_eq(output['/tmp/project/test/foo_test.dart::4_4_6_7'], "a ' ' b")
end)

test('parser handles generic dart test filenames in diagnostics', function()
  reset_modules({ 'neotest.async', 'neotest-dart.utils', 'neotest-dart.parser' })
  package.preload['neotest.async'] = function()
    return {
      fn = {
        tempname = function()
          return '/tmp/neotest-dart-output'
        end,
      },
    }
  end

  local parser = require('neotest-dart.parser')
  local tree = {
    iter_nodes = function()
      local yielded = false
      local node = {
        data = function()
          return {
            type = 'test',
            id = '/tmp/project/test/foo_test.dart::"group"::"works"',
            path = '/tmp/project/test/foo_test.dart',
            range = { 4, 4, 6, 7 },
          }
        end,
      }

      return function()
        if yielded then
          return nil
        end
        yielded = true
        return 1, node
      end
    end,
  }

  local lines = {
    vim.json.encode({ test = { id = 1, name = 'group works' } }),
    vim.json.encode({
      testID = 1,
      result = 'failure',
      message = 'Expected true but was false in foo_test.dart line 12',
      time = 42,
    }),
  }

  local results = parser.parse_lines(tree, lines, {}, { write_output = false })
  local result = results['/tmp/project/test/foo_test.dart::"group"::"works"']
  assert_eq(result.status, 'failed')
  assert_eq(result.errors[1].line, 11)
  assert(result.output:match('Elapsed: 0%.042s%.'), 'Expected elapsed time in in-memory output')
end)

test('parser matches runtime tests by location instead of name', function()
  reset_modules({ 'neotest.async', 'neotest-dart.utils', 'neotest-dart.parser' })
  package.preload['neotest.async'] = function()
    return {
      fn = {
        tempname = function()
          return '/tmp/neotest-dart-output'
        end,
      },
    }
  end

  local parser = require('neotest-dart.parser')
  local tree = {
    iter_nodes = function()
      local yielded = false
      local node = {
        data = function()
          return {
            type = 'test',
            id = '/tmp/project/test/foo_test.dart::"works"',
            name = 'works',
            path = '/tmp/project/test/foo_test.dart',
            range = { 4, 2, 6, 7 },
          }
        end,
      }

      return function()
        if yielded then
          return nil
        end
        yielded = true
        return 1, node
      end
    end,
  }

  local lines = {
    vim.json.encode({
      type = 'testStart',
      test = {
        id = 1,
        name = 'generated runtime name',
        url = 'file:///tmp/project/test/foo_test.dart',
        line = 5,
        column = 3,
      },
    }),
    vim.json.encode({
      type = 'testDone',
      testID = 1,
      result = 'success',
      hidden = false,
      skipped = false,
      time = 42,
    }),
  }

  local results = parser.parse_lines(tree, lines, {}, { write_output = false })
  local result = results['/tmp/project/test/foo_test.dart::"works"']
  assert(result, 'Expected runtime test to be matched by location')
  assert_eq(result.status, 'passed')
end)

test('parser aggregates multiple runtime tests from same source location', function()
  reset_modules({ 'neotest.async', 'neotest-dart.utils', 'neotest-dart.parser' })
  package.preload['neotest.async'] = function()
    return {
      fn = {
        tempname = function()
          return '/tmp/neotest-dart-output'
        end,
      },
    }
  end

  local parser = require('neotest-dart.parser')
  local tree = {
    iter_nodes = function()
      local yielded = false
      local node = {
        data = function()
          return {
            type = 'test',
            id = '/tmp/project/test/foo_test.dart::"loop"',
            name = 'loop',
            path = '/tmp/project/test/foo_test.dart',
            range = { 9, 4, 12, 6 },
          }
        end,
      }

      return function()
        if yielded then
          return nil
        end
        yielded = true
        return 1, node
      end
    end,
  }

  local lines = {
    vim.json.encode({
      type = 'testStart',
      test = {
        id = 1,
        name = 'case 1',
        root_url = 'file:///tmp/project/test/foo_test.dart',
        root_line = 10,
        root_column = 5,
        url = 'file:///tmp/project/test/helpers.dart',
        line = 30,
        column = 2,
      },
    }),
    vim.json.encode({
      type = 'testDone',
      testID = 1,
      result = 'success',
      hidden = false,
      skipped = false,
      time = 11,
    }),
    vim.json.encode({
      type = 'testStart',
      test = {
        id = 2,
        name = 'case 2',
        url = 'file:///tmp/project/test/foo_test.dart',
        line = 10,
        column = 5,
      },
    }),
    vim.json.encode({
      type = 'error',
      testID = 2,
      error = "'file:///tmp/project/test/foo_test.dart': Expected true but was false",
      stackTrace = 'foo_test.dart line 14',
      isFailure = true,
    }),
    vim.json.encode({
      type = 'testDone',
      testID = 2,
      result = 'failure',
      hidden = false,
      skipped = false,
      time = 17,
    }),
  }

  local results = parser.parse_lines(tree, lines, {}, { write_output = false })
  local result = results['/tmp/project/test/foo_test.dart::"loop"']
  assert(result, 'Expected loop-generated tests to be aggregated')
  assert_eq(result.status, 'failed')
  assert(result.output:match('Expected true but was false'), 'Expected combined failure output')
  assert_eq(result.errors[1].line, 13)
end)

test('adapter respects use_lsp and avoids duplicate wrapping', function()
  reset_modules({
    'neotest.async',
    'plenary.path',
    'neotest.lib',
    'neotest-dart.utils',
    'neotest-dart.parser',
    'neotest-dart.lsp_outline_parser',
    'neotest-dart',
  })

  local autocmd_callback
  local autocmd_count = 0
  local parser_opts
  local outline_parse_calls = 0
  local client = {
    id = 7,
    name = 'dartls',
    handlers = {},
  }
  local original_handler_calls = 0
  local original_handler = function()
    original_handler_calls = original_handler_calls + 1
  end
  client.handlers['dart/textDocument/publishOutline'] = original_handler

  package.preload['neotest.async'] = function()
    return {
      fn = {
        tempname = function()
          return '/tmp/neotest-dart-results'
        end,
      },
    }
  end
  package.preload['plenary.path'] = function()
    return { path = { sep = '/' } }
  end
  package.preload['neotest.lib'] = function()
    return {
      files = {
        match_root_pattern = function()
          return function()
            return '/tmp/project'
          end
        end,
        read = function()
          return ''
        end,
      },
      treesitter = {
        parse_positions = function()
          return {
            iter = function()
              return function()
                return nil
              end
            end,
          }
        end,
      },
    }
  end
  package.preload['neotest-dart.utils'] = function()
    return {
      get_test_name_from_outline = function()
        return nil
      end,
      remove_surrounding_quates = function(name)
        return name
      end,
      construct_test_name = function()
        return 'works'
      end,
      position_target = function(position)
        return string.format('%s?line=%s', position.path, position.range[1] + 1)
      end,
      join_path = function(...)
        return table.concat({ ... }, '/')
      end,
    }
  end
  package.preload['neotest-dart.parser'] = function()
    return {
      parse_lines = function(_, _, _, opts)
        parser_opts = opts
        return {}
      end,
    }
  end
  package.preload['neotest-dart.lsp_outline_parser'] = function()
    return {
      parse = function()
        outline_parse_calls = outline_parse_calls + 1
        return {}
      end,
    }
  end

  local original_create_autocmd = vim.api.nvim_create_autocmd
  local original_get_client = vim.lsp.get_client_by_id
  vim.api.nvim_create_autocmd = function(_, opts)
    autocmd_count = autocmd_count + 1
    autocmd_callback = opts.callback
  end
  vim.lsp.get_client_by_id = function(id)
    if id == client.id then
      return client
    end
  end

  local ok, err = pcall(function()
    local adapter = require('neotest-dart')
    adapter({ use_lsp = false })
    assert_eq(autocmd_count, 1)

    autocmd_callback({ file = '/tmp/project/test/foo_test.dart', data = { client_id = client.id } })
    assert_eq(client.handlers['dart/textDocument/publishOutline'], original_handler)

    adapter({ use_lsp = true })
    assert_eq(autocmd_count, 1)

    autocmd_callback({ file = '/tmp/project/test/foo_test.dart', data = { client_id = client.id } })
    local wrapped_handler = client.handlers['dart/textDocument/publishOutline']
    assert(
      wrapped_handler ~= original_handler,
      'Expected outline handler to be wrapped once when enabled'
    )

    autocmd_callback({ file = '/tmp/project/test/foo_test.dart', data = { client_id = client.id } })
    assert_eq(client.handlers['dart/textDocument/publishOutline'], wrapped_handler)

    wrapped_handler(
      nil,
      { outline = { children = {} }, uri = 'file:///tmp/project/test/foo_test.dart' }
    )
    assert_eq(original_handler_calls, 1)
    assert_eq(outline_parse_calls, 1)

    local spec = adapter.build_spec({
      tree = {
        data = function()
          return {
            type = 'test',
            id = '/tmp/project/test/foo_test.dart::"works"',
            path = '/tmp/project/test/foo_test.dart',
            range = { 1, 0, 1, 4 },
          }
        end,
      },
    })
    local stream = spec.stream(function()
      return { vim.json.encode({ event = 'testStart' }) }
    end)
    stream()
    assert_eq(parser_opts.write_output, false)
  end)

  vim.api.nvim_create_autocmd = original_create_autocmd
  vim.lsp.get_client_by_id = original_get_client
  if not ok then
    error(err)
  end
end)

test('adapter uses positional path when running individual tests', function()
  reset_modules({
    'neotest.async',
    'plenary.path',
    'neotest.lib',
    'neotest-dart.utils',
    'neotest-dart.parser',
    'neotest-dart.lsp_outline_parser',
    'neotest-dart',
  })

  package.preload['neotest.async'] = function()
    return {
      fn = {
        tempname = function()
          return '/tmp/neotest-dart-results'
        end,
      },
    }
  end
  package.preload['plenary.path'] = function()
    return { path = { sep = '/' } }
  end
  package.preload['neotest.lib'] = function()
    return {
      files = {
        match_root_pattern = function()
          return function()
            return '/tmp/project'
          end
        end,
        read = function()
          return ''
        end,
      },
      treesitter = {
        parse_positions = function()
          return {
            iter = function()
              return function()
                return nil
              end
            end,
          }
        end,
      },
    }
  end
  package.preload['neotest-dart.utils'] = function()
    return {
      get_test_name_from_outline = function()
        return nil
      end,
      remove_surrounding_quates = function(name)
        return name
      end,
      construct_test_name = function()
        return 'works'
      end,
      position_target = function(position)
        return string.format('%s?line=%s', position.path, position.range[1] + 1)
      end,
      join_path = function(...)
        return table.concat({ ... }, '/')
      end,
    }
  end
  package.preload['neotest-dart.parser'] = function()
    return {
      parse_lines = function()
        return {}
      end,
    }
  end
  package.preload['neotest-dart.lsp_outline_parser'] = function()
    return {
      parse = function()
        return {}
      end,
    }
  end

  local original_create_autocmd = vim.api.nvim_create_autocmd
  vim.api.nvim_create_autocmd = function() end

  local ok, err = pcall(function()
    local adapter = require('neotest-dart')
    adapter({ command = 'dart', use_lsp = false })

    local spec = adapter.build_spec({
      tree = {
        data = function()
          return {
            type = 'test',
            id = '/tmp/project/test/foo_test.dart::"works"',
            name = 'works',
            path = '/tmp/project/test/foo_test.dart',
            range = { 4, 2, 6, 7 },
          }
        end,
      },
    })

    assert(
      spec.command:match('^dart test "/tmp/project/test/foo_test%.dart%?line=5" '),
      'Expected positional test target'
    )
    assert(not spec.command:match('%-%-plain%-name'), 'Did not expect plain-name argument')
  end)

  vim.api.nvim_create_autocmd = original_create_autocmd
  if not ok then
    error(err)
  end
end)

test('adapter uses positional program for dart debug adapter', function()
  reset_modules({
    'neotest.async',
    'plenary.path',
    'neotest.lib',
    'neotest-dart.utils',
    'neotest-dart.parser',
    'neotest-dart.lsp_outline_parser',
    'neotest-dart',
    'dap',
  })

  local registered_adapter
  package.preload['neotest.async'] = function()
    return {
      fn = {
        tempname = function()
          return '/tmp/neotest-dart-results'
        end,
      },
    }
  end
  package.preload['plenary.path'] = function()
    return { path = { sep = '/' } }
  end
  package.preload['neotest.lib'] = function()
    return {
      files = {
        match_root_pattern = function()
          return function()
            return '/tmp/project'
          end
        end,
        read = function()
          return ''
        end,
      },
      treesitter = {
        parse_positions = function()
          return {
            iter = function()
              return function()
                return nil
              end
            end,
          }
        end,
      },
    }
  end
  package.preload['neotest-dart.utils'] = function()
    return {
      get_test_name_from_outline = function()
        return nil
      end,
      remove_surrounding_quates = function(name)
        return name
      end,
      construct_test_name = function()
        return 'works'
      end,
      position_target = function(position)
        return string.format('%s?line=%s', position.path, position.range[1] + 1)
      end,
      join_path = function(...)
        return table.concat({ ... }, '/')
      end,
    }
  end
  package.preload['neotest-dart.parser'] = function()
    return {
      parse_lines = function()
        return {}
      end,
    }
  end
  package.preload['neotest-dart.lsp_outline_parser'] = function()
    return {
      parse = function()
        return {}
      end,
    }
  end
  package.preload['dap'] = function()
    return {
      adapters = setmetatable({}, {
        __newindex = function(_, key, value)
          if key == 'dart_test' then
            registered_adapter = value
          end
        end,
      }),
    }
  end

  local original_create_autocmd = vim.api.nvim_create_autocmd
  vim.api.nvim_create_autocmd = function() end

  local ok, err = pcall(function()
    local adapter = require('neotest-dart')
    adapter({ command = 'dart', use_lsp = false })

    local spec = adapter.build_spec({
      tree = {
        data = function()
          return {
            type = 'test',
            id = '/tmp/project/test/foo_test.dart::"works"',
            path = '/tmp/project/test/foo_test.dart',
            range = { 1, 0, 1, 4 },
          }
        end,
      },
      strategy = 'dap',
    })

    assert(
      spec.command:match('^dart test /tmp/project/test/foo_test%.dart '),
      'Expected dart test command'
    )
    assert(not spec.command:match('%-%-no%-pub'), 'Did not expect --no-pub for dart command')
    assert_eq(spec.strategy.program, '/tmp/project/test/foo_test.dart?line=2')
    assert_eq(spec.strategy.args, {})
    assert_eq(registered_adapter.command, 'dart')
    assert_eq(registered_adapter.args, { 'debug_adapter', '--test' })
  end)

  vim.api.nvim_create_autocmd = original_create_autocmd
  if not ok then
    error(err)
  end
end)

test('adapter uses positional program for flutter debug adapter', function()
  reset_modules({
    'neotest.async',
    'plenary.path',
    'neotest.lib',
    'neotest-dart.utils',
    'neotest-dart.parser',
    'neotest-dart.lsp_outline_parser',
    'neotest-dart',
    'dap',
  })

  local registered_adapter
  package.preload['neotest.async'] = function()
    return {
      fn = {
        tempname = function()
          return '/tmp/neotest-dart-results'
        end,
      },
    }
  end
  package.preload['plenary.path'] = function()
    return { path = { sep = '/' } }
  end
  package.preload['neotest.lib'] = function()
    return {
      files = {
        match_root_pattern = function()
          return function()
            return '/tmp/project'
          end
        end,
        read = function()
          return ''
        end,
      },
      treesitter = {
        parse_positions = function()
          return {
            iter = function()
              return function()
                return nil
              end
            end,
          }
        end,
      },
    }
  end
  package.preload['neotest-dart.utils'] = function()
    return {
      get_test_name_from_outline = function()
        return nil
      end,
      remove_surrounding_quates = function(name)
        return name
      end,
      construct_test_name = function()
        return 'works'
      end,
      position_target = function(position)
        return string.format('%s?line=%s', position.path, position.range[1] + 1)
      end,
      join_path = function(...)
        return table.concat({ ... }, '/')
      end,
    }
  end
  package.preload['neotest-dart.parser'] = function()
    return {
      parse_lines = function()
        return {}
      end,
    }
  end
  package.preload['neotest-dart.lsp_outline_parser'] = function()
    return {
      parse = function()
        return {}
      end,
    }
  end
  package.preload['dap'] = function()
    return {
      adapters = setmetatable({}, {
        __newindex = function(_, key, value)
          if key == 'dart_test' then
            registered_adapter = value
          end
        end,
      }),
    }
  end

  local original_create_autocmd = vim.api.nvim_create_autocmd
  vim.api.nvim_create_autocmd = function() end

  local ok, err = pcall(function()
    local adapter = require('neotest-dart')
    adapter({ command = 'flutter', use_lsp = false })

    local spec = adapter.build_spec({
      tree = {
        data = function()
          return {
            type = 'test',
            id = '/tmp/project/test/foo_test.dart::"works"',
            path = '/tmp/project/test/foo_test.dart',
            range = { 1, 0, 1, 4 },
          }
        end,
      },
      strategy = 'dap',
    })

    assert(
      spec.command:match('^flutter test /tmp/project/test/foo_test%.dart '),
      'Expected flutter test command'
    )
    assert(spec.command:match('%-%-no%-pub'), 'Expected --no-pub for flutter command')
    assert_eq(spec.strategy.program, '/tmp/project/test/foo_test.dart?line=2')
    assert_eq(spec.strategy.args, { '--no-pub' })
    assert_eq(registered_adapter.command, 'flutter')
    assert_eq(registered_adapter.args, { 'debug-adapter', '--test' })
  end)

  vim.api.nvim_create_autocmd = original_create_autocmd
  if not ok then
    error(err)
  end
end)

if #failures > 0 then
  error(table.concat(failures, '\n\n'))
end
