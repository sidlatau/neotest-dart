local M = {}

---@param result table
---@param node table
local function parse_outline(result, node)
  if not node then
    return
  end
  local range = node.codeRange
  local element = node.element or {}

  if element.kind == 'UNIT_TEST_TEST' then
    local _, _, test_name = element.name:find('testWidgets%("(.+)"%)')
    if test_name then
      local start_line = range.start.line
      local start_col = range.start.character
      local end_line = range['end'].line
      local end_col = range['end'].character
      range = table.concat({ start_line, start_col, end_line, end_col + 1 }, '_')
      result[range] = test_name
    end
  end

  local children = node.children
  if not children or vim.tbl_isempty(children) then
    return
  end

  for _, child in ipairs(children) do
    parse_outline(result, child)
  end
end

function M.parse(data)
  local outline = data.outline or {}
  if not outline.children or #outline.children == 0 then
    return
  end
  local result = {}
  for _, item in ipairs(outline.children) do
    parse_outline(result, item)
  end
  return result
end

return M
