local M = {}

--- remove surrounding quotes
---@param name string
---@param prepare_for_summary boolean? indicates that additional whitespace
--- trimming is needed to look pretty in summary
---@return string
M.remove_surrounding_quates = function(name, prepare_for_summary)
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

M.get_test_name_from_outline = function(position, outline)
  local range = table.concat(position.range, '_')
  local outline_key = position.path .. '::' .. range
  return outline[outline_key]
end

--- position and outline contains information enought to construct test name
--- @returns string
M.construct_test_name = function(position, outline)
  local outline_test_name = M.get_test_name_from_outline(position, outline)
  local parts = vim.split(position.id, '::')
  if outline_test_name then
    parts[#parts] = outline_test_name
  end
  local name_components = {}
  for index, value in ipairs(parts) do
    if index > 1 then
      local component = M.remove_surrounding_quates(value)
      table.insert(name_components, component)
    end
  end
  local name = table.concat(name_components, ' ')
  return name
end

return M
