local M = {}

---@param result table
---@param node table
local function parse_outline(result, node, path)
  if not node then
    return
  end
  local range = node.codeRange
  local element = node.element or {}

  if element.kind == 'UNIT_TEST_TEST' then
    local _, _, test_name = element.name:find('[testWidgets,test]%("(.+)"%)')
    if test_name then
      local start_line = range.start.line
      local start_col = range.start.character
      local end_line = range['end'].line
      local end_col = range['end'].character
      local range_string = table.concat({ start_line, start_col, end_line, end_col + 1 }, '_')
      result[path .. '::' .. range_string] = test_name
    end
  end

  local children = node.children
  if not children or vim.tbl_isempty(children) then
    return
  end

  for _, child in ipairs(children) do
    parse_outline(result, child, path)
  end
end

function M.parse(data)
  local outline = data.outline or {}
  local uri = data.uri
  if not uri or not outline.children or #outline.children == 0 then
    return
  end
  local path = uri:gsub('file://', '')
  local result = {}
  for _, item in ipairs(outline.children) do
    parse_outline(result, item, path)
  end
  return result
end

return M
