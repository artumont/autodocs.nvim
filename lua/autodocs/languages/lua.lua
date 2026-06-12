--- @module "autodocs.languages.lua"
--- Lua Treesitter parser and LDoc-style docstring formatter for autodocs.nvim

local M = {}

--- Trigger characters for Lua doc comments
M.triggers = { "-" }

-- Treesitter Parsing

--- Extract parameters from a Lua function's parameters node
--- @param params_node TSNode
--- @param bufnr number
--- @return string[]
local function extract_params(params_node, bufnr)
  local params = {}
  for i = 0, params_node:named_child_count() - 1 do
    local child = params_node:named_child(i)
    local text = vim.treesitter.get_node_text(child, bufnr)
    if text and text ~= "" then
      table.insert(params, text)
    end
  end
  return params
end

--- Recursively check if a node contains a return_statement with a value
--- @param node TSNode
--- @return boolean
local function has_return_value(node)
  if node:type() == "return_statement" then
    return node:named_child_count() > 0
  end

  -- Don't recurse into nested function definitions
  local ntype = node:type()
  if ntype == "function_definition" or ntype == "function_declaration" then
    return false
  end

  for i = 0, node:named_child_count() - 1 do
    if has_return_value(node:named_child(i)) then
      return true
    end
  end
  return false
end

--- Find the function definition node on or after the given row
--- @param bufnr number
--- @param row number 0-indexed
--- @return TSNode|nil
local function find_function(bufnr, row)
  local parser = vim.treesitter.get_parser(bufnr, "lua")
  if not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local root = tree:root()
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local max_search = math.min(row + 20, total_lines - 1)

  for search_row = row, max_search do
    local node = root:named_descendant_for_range(search_row, 0, search_row, 0)
    while node do
      local ntype = node:type()
      if ntype == "function_declaration" or ntype == "function_definition" then
        return node
      end
      -- Handle `local function f()` which wraps in local_declaration
      if ntype == "local_declaration" then
        for i = 0, node:named_child_count() - 1 do
          local child = node:named_child(i)
          if child:type() == "function_declaration" then
            return child
          end
        end
      end
      -- Handle `local f = function() ... end`
      if ntype == "variable_declaration" or ntype == "assignment_statement" then
        local vals = node:field("value") or {}
        for _, val_node in ipairs(vals) do
          -- val_node might be expression_list
          if val_node:type() == "function_definition" then
            return val_node
          end
          for j = 0, val_node:named_child_count() - 1 do
            local c = val_node:named_child(j)
            if c:type() == "function_definition" then
              return c
            end
          end
        end
      end
      node = node:parent()
    end
  end

  return nil
end

--- Parse the construct near the cursor position
--- @param bufnr number
--- @param row number 0-indexed cursor row
--- @return table|nil Parsed data
function M.parse(bufnr, row)
  -- For Lua, the `---` line is above the function, so look at the next line
  local func_node = find_function(bufnr, row + 1)
  if not func_node then
    func_node = find_function(bufnr, row)
  end
  if not func_node then
    return nil
  end

  -- Extract function name
  local name = "unknown"
  local name_nodes = func_node:field("name")
  if name_nodes and name_nodes[1] then
    name = vim.treesitter.get_node_text(name_nodes[1], bufnr)
  end

  -- Extract parameters
  local params_nodes = func_node:field("parameters")
  local params = {}
  if params_nodes and params_nodes[1] then
    params = extract_params(params_nodes[1], bufnr)
  end

  -- Check for return value
  local body_nodes = func_node:field("body")
  local has_return = false
  if body_nodes and body_nodes[1] then
    has_return = has_return_value(body_nodes[1])
  end

  return {
    kind = "function",
    name = name,
    params = params,
    has_return = has_return,
  }
end

-- LDoc Formatting

--- Format parsed data into LDoc-style doc comment lines
--- @param data table Parsed data from M.parse()
--- @param _style string Style name (ignored, Lua only supports ldoc)
--- @param indent string Indentation prefix
--- @return string[]
function M.format(data, _style, indent)
  local lines = {}
  local tabstop = 0

  local function ts(label)
    tabstop = tabstop + 1
    return "${" .. tabstop .. ":" .. label .. "}"
  end

  -- Summary line
  table.insert(lines, indent .. "--- " .. ts("_summary_"))

  -- Parameters
  for _, param_name in ipairs(data.params) do
    if param_name == "..." then
      table.insert(lines, indent .. "--- @vararg " .. ts("_type_"))
    else
      table.insert(lines, indent .. "--- @param " .. param_name .. " " .. ts("_type_") .. " " .. ts("_description_"))
    end
  end

  -- Return
  if data.has_return then
    table.insert(lines, indent .. "--- @return " .. ts("_type_") .. " " .. ts("_description_"))
  end

  return lines
end

return M
