local parser = require('neotest-dart.lsp_outline_parser')

describe('lsp outline parser', function()
  it('parses widget test names', function()
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
          },
        },
      },
    }
    local output = parser.parse(data)
    assert.equals(output['4_4_6_7'], "a ' ' b")
  end)

  it('parses widget test names', function()
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
          },
        },
      },
    }
    local output = parser.parse(data)
    assert.equals(output['4_4_6_7'], "a ' ' b")
  end)
end)
