local parser = require('neotest-dart.lsp_outline_parser')

describe('lsp outline parser', function()
  it('parses test names', function()
    local data = {
      outline = {
        children = {
          {
            children = {
              {
                children = {
                  {
                    codeRange = {
                      ['end'] = {
                        character = 6,
                        line = 6,
                      },
                      start = {
                        character = 4,
                        line = 4,
                      },
                    },
                    element = {
                      kind = 'UNIT_TEST_TEST',
                      name = 'testWidgets("a \' \' b")',
                      range = {
                        ['end'] = {
                          character = 15,
                          line = 4,
                        },
                        start = {
                          character = 4,
                          line = 4,
                        },
                      },
                    },
                    range = {
                      ['end'] = {
                        character = 6,
                        line = 6,
                      },
                      start = {
                        character = 4,
                        line = 4,
                      },
                    },
                  },
                },
                codeRange = {
                  ['end'] = {
                    character = 4,
                    line = 7,
                  },
                  start = {
                    character = 2,
                    line = 3,
                  },
                },
                element = {
                  kind = 'UNIT_TEST_GROUP',
                  name = 'group("group")',
                  range = {
                    ['end'] = {
                      character = 7,
                      line = 3,
                    },
                    start = {
                      character = 2,
                      line = 3,
                    },
                  },
                },
                range = {
                  ['end'] = {
                    character = 4,
                    line = 7,
                  },
                  start = {
                    character = 2,
                    line = 3,
                  },
                },
              },
            },
            codeRange = {
              ['end'] = {
                character = 1,
                line = 8,
              },
              start = {
                character = 0,
                line = 2,
              },
            },
            element = {
              kind = 'FUNCTION',
              name = 'main',
              parameters = '()',
              range = {
                ['end'] = {
                  character = 9,
                  line = 2,
                },
                start = {
                  character = 5,
                  line = 2,
                },
              },
              returnType = 'void',
            },
            range = {
              ['end'] = {
                character = 1,
                line = 8,
              },
              start = {
                character = 0,
                line = 2,
              },
            },
          },
        },
        codeRange = {
          ['end'] = {
            character = 0,
            line = 9,
          },
          start = {
            character = 0,
            line = 0,
          },
        },
        element = {
          kind = 'COMPILATION_UNIT',
          name = '<unit>',
          range = {
            ['end'] = {
              character = 0,
              line = 9,
            },
            start = {
              character = 0,
              line = 0,
            },
          },
        },
        range = {
          ['end'] = {
            character = 0,
            line = 9,
          },
          start = {
            character = 0,
            line = 0,
          },
        },
      },
      uri = 'file:///Users/ts/Documents/github/personal/pikis/test/test.dart',
    }
    local output = parser.parse(data)
    asert.equals(output['4_4_6_7'], "a ' ' b")
  end)
end)
