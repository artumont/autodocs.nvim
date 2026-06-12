--- @module "autodocs.languages.python"
--- Python Treesitter parser and docstring formatter for autodocs.nvim
--- Supports Google, NumPy, Sphinx, and Simple docstring styles

local config = require("autodocs.config")

local M = {}

--- Trigger characters for Python docstrings
M.triggers = { '"', "'" }

-- Treesitter Parsing

--- Extract parameter info from a single Treesitter parameter node
--- @param node TSNode
--- @param bufnr number
--- @return table|nil { name: string, type: string|nil, default: string|nil }
local function parse_param_node(node, bufnr)
  local ntype = node:type()
  local text = vim.treesitter.get_node_text

  if ntype == "identifier" then
    return { name = text(node, bufnr), type = nil, default = nil }
  end

  if ntype == "typed_parameter" then
    local name_node = node:named_child(0)
    local type_node = node:named_child(1)
    return {
      name = name_node and text(name_node, bufnr) or nil,
      type = type_node and text(type_node, bufnr) or nil,
      default = nil,
    }
  end

  if ntype == "default_parameter" then
    local name_node = node:named_child(0)
    local val_node = node:named_child(1)
    return {
      name = name_node and text(name_node, bufnr) or nil,
      type = nil,
      default = val_node and text(val_node, bufnr) or nil,
    }
  end

  if ntype == "typed_default_parameter" then
    local name_node = node:named_child(0)
    local type_node = node:named_child(1)
    local val_node = node:named_child(2)
    return {
      name = name_node and text(name_node, bufnr) or nil,
      type = type_node and text(type_node, bufnr) or nil,
      default = val_node and text(val_node, bufnr) or nil,
    }
  end

  if ntype == "list_splat_pattern" then
    local child = node:named_child(0)
    return {
      name = child and ("*" .. text(child, bufnr)) or "*args",
      type = nil,
      default = nil,
    }
  end

  if ntype == "dictionary_splat_pattern" then
    local child = node:named_child(0)
    return {
      name = child and ("**" .. text(child, bufnr)) or "**kwargs",
      type = nil,
      default = nil,
    }
  end

  -- Skip separators and other non-parameter nodes
  return nil
end

--- Extract all parameters from a function_definition node
--- @param func_node TSNode
--- @param bufnr number
--- @return table[] List of { name, type, default }
local function extract_params(func_node, bufnr)
  local params_nodes = func_node:field("parameters")
  if not params_nodes or not params_nodes[1] then
    return {}
  end

  local params_node = params_nodes[1]
  local params = {}
  local excluded = config.get_excluded_params("python")
  local excluded_set = {}
  for _, p in ipairs(excluded) do
    excluded_set[p] = true
  end

  for i = 0, params_node:named_child_count() - 1 do
    local child = params_node:named_child(i)
    local param = parse_param_node(child, bufnr)
    if param and param.name and not excluded_set[param.name] then
      table.insert(params, param)
    end
  end

  return params
end

--- Extract the return type annotation from a function_definition node
--- @param func_node TSNode
--- @param bufnr number
--- @return string|nil
local function extract_return_type(func_node, bufnr)
  local rt_nodes = func_node:field("return_type")
  if rt_nodes and rt_nodes[1] then
    return vim.treesitter.get_node_text(rt_nodes[1], bufnr)
  end
  return nil
end

--- Recursively find all raise statements within a node
--- @param node TSNode
--- @param bufnr number
--- @param results string[]
local function find_raises(node, bufnr, results)
  if node:type() == "raise_statement" then
    -- Get the first named child which is the exception
    local exc_node = node:named_child(0)
    if exc_node then
      local exc_text
      if exc_node:type() == "call" then
        -- raise SomeError(...) — extract the function name
        local fn = exc_node:field("function")
        if fn and fn[1] then
          exc_text = vim.treesitter.get_node_text(fn[1], bufnr)
        end
      else
        exc_text = vim.treesitter.get_node_text(exc_node, bufnr)
      end
      if exc_text then
        -- Deduplicate
        local found = false
        for _, r in ipairs(results) do
          if r == exc_text then
            found = true
            break
          end
        end
        if not found then
          table.insert(results, exc_text)
        end
      end
    end
    return
  end

  -- Don't recurse into nested function definitions
  if node:type() == "function_definition" then
    return
  end

  for i = 0, node:named_child_count() - 1 do
    find_raises(node:named_child(i), bufnr, results)
  end
end

--- Extract raised exceptions from a function body
--- @param func_node TSNode
--- @param bufnr number
--- @return string[]
local function extract_raises(func_node, bufnr)
  local body_nodes = func_node:field("body")
  if not body_nodes or not body_nodes[1] then
    return {}
  end

  local raises = {}
  find_raises(body_nodes[1], bufnr, raises)
  return raises
end

--- Check if the function body contains any return statements with values
--- @param func_node TSNode
--- @param bufnr number
--- @return boolean
local function has_return_value(func_node, bufnr)
  local body_nodes = func_node:field("body")
  if not body_nodes or not body_nodes[1] then
    return false
  end

  local body = body_nodes[1]

  local function scan(node)
    if node:type() == "function_definition" then
      return false
    end
    if node:type() == "return_statement" then
      -- Check if the return has a value (named children beyond the keyword)
      if node:named_child_count() > 0 then
        return true
      end
    end
    for i = 0, node:named_child_count() - 1 do
      if scan(node:named_child(i)) then
        return true
      end
    end
    return false
  end

  return scan(body)
end

--- Extract class attributes from __init__ body (self.attr = ...)
--- @param init_node TSNode
--- @param bufnr number
--- @return string[] List of attribute names
local function extract_class_attributes(init_node, bufnr)
  local body_nodes = init_node:field("body")
  if not body_nodes or not body_nodes[1] then
    return {}
  end

  local attrs = {}
  local seen = {}

  local query_str = [[
    (assignment
      left: (attribute
        object: (identifier) @obj (#eq? @obj "self")
        attribute: (identifier) @attr))
  ]]

  local ok, query = pcall(vim.treesitter.query.parse, "python", query_str)
  if not ok then
    return {}
  end

  for id, node in query:iter_captures(body_nodes[1], bufnr) do
    if query.captures[id] == "attr" then
      local name = vim.treesitter.get_node_text(node, bufnr)
      if not seen[name] then
        seen[name] = true
        table.insert(attrs, name)
      end
    end
  end

  return attrs
end

--- Find the function or class definition node at or after a given row
--- @param bufnr number
--- @param row number 0-indexed
--- @return TSNode|nil, string|nil The node and its kind ("function" or "class")
local function find_construct(bufnr, row)
  local parser = vim.treesitter.get_parser(bufnr, "python")
  if not parser then
    return nil, nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil, nil
  end

  local root = tree:root()

  -- Search downward from the current row for the nearest definition
  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local max_search = math.min(row + 20, total_lines - 1)

  for search_row = row, max_search do
    local node = root:named_descendant_for_range(search_row, 0, search_row, 0)
    while node do
      local ntype = node:type()
      if ntype == "function_definition" then
        return node, "function"
      end
      if ntype == "class_definition" then
        return node, "class"
      end
      node = node:parent()
    end
  end

  return nil, nil
end

--- Parse the construct near the cursor position
--- @param bufnr number
--- @param row number 0-indexed cursor row
--- @return table|nil Parsed data
function M.parse(bufnr, row)
  -- The cursor is on the """ line; look at the next line for the definition
  local construct, kind = find_construct(bufnr, row + 1)
  if not construct then
    -- Also try the current line (for inside-body docstrings)
    construct, kind = find_construct(bufnr, row)
    if not construct then
      return nil
    end
    -- If we found a construct at the current row, we might be inside its body
    -- Walk up to find the enclosing function/class
    local node = construct
    while node do
      local ntype = node:type()
      if ntype == "function_definition" or ntype == "class_definition" then
        construct = node
        kind = ntype == "function_definition" and "function" or "class"
        break
      end
      node = node:parent()
    end
  end

  local name_nodes = construct:field("name")
  local name = name_nodes and name_nodes[1]
    and vim.treesitter.get_node_text(name_nodes[1], bufnr)
    or "unknown"

  if kind == "function" then
    local params = extract_params(construct, bufnr)
    local return_type = extract_return_type(construct, bufnr)
    local raises = extract_raises(construct, bufnr)
    local has_return = has_return_value(construct, bufnr) or return_type ~= nil

    -- Apply return type exclusions (e.g. "None")
    if return_type then
      local excluded = config.get_excluded_returns("python")
      for _, r in ipairs(excluded) do
        if r == return_type then
          has_return = false
          break
        end
      end
    end

    return {
      kind = "function",
      name = name,
      params = params,
      return_type = return_type,
      has_return = has_return,
      raises = raises,
    }
  end

  if kind == "class" then
    -- Look for __init__ method to extract attributes
    local body_nodes = construct:field("body")
    local attrs = {}
    local init_params = {}
    if body_nodes and body_nodes[1] then
      local body = body_nodes[1]
      for i = 0, body:named_child_count() - 1 do
        local child = body:named_child(i)
        if child:type() == "function_definition" then
          local cn = child:field("name")
          if cn and cn[1]
            and vim.treesitter.get_node_text(cn[1], bufnr) == "__init__" then
            attrs = extract_class_attributes(child, bufnr)
            init_params = extract_params(child, bufnr)
            break
          end
        end
      end
    end

    -- Get superclasses
    local supers = {}
    local super_nodes = construct:field("superclasses")
    if super_nodes and super_nodes[1] then
      local arg_list = super_nodes[1]
      for i = 0, arg_list:named_child_count() - 1 do
        local child = arg_list:named_child(i)
        table.insert(supers, vim.treesitter.get_node_text(child, bufnr))
      end
    end

    return {
      kind = "class",
      name = name,
      superclasses = supers,
      attributes = attrs,
      init_params = init_params,
    }
  end

  return nil
end

-- Docstring Formatting

--- Snippet tabstop counter (managed per format call)
local _tabstop = 0

--- Create a tabstop with a placeholder label: ${N:label}
--- @param label string Placeholder text shown inside the tabstop
--- @return string
local function tabstop(label)
  _tabstop = _tabstop + 1
  return "${" .. _tabstop .. ":" .. label .. "}"
end

--- Shorthand for a summary placeholder
local function summary_tabstop()
  return tabstop("_summary_")
end

--- Shorthand for a description placeholder
local function desc_tabstop()
  return tabstop("_description_")
end

local function reset_tabstops()
  _tabstop = 0
end

--- Format a function docstring in Google style
--- @param data table Parsed function data
--- @param indent string
--- @return string[]
local function format_google_function(data, indent)
  reset_tabstops()
  local lines = {}

  table.insert(lines, indent .. '"""' .. summary_tabstop() .. "")

  if #data.params > 0 then
    table.insert(lines, "")
    table.insert(lines, indent .. "Args:")
    for _, p in ipairs(data.params) do
      local type_hint = p.type and (" (" .. p.type .. ")") or ""
      local default_hint = p.default and (". Defaults to " .. p.default .. ".") or ""
      table.insert(lines,
        indent .. "    " .. p.name .. type_hint .. ": " .. desc_tabstop() .. default_hint)
    end
  end

  if #data.raises > 0 then
    table.insert(lines, "")
    table.insert(lines, indent .. "Raises:")
    for _, exc in ipairs(data.raises) do
      table.insert(lines, indent .. "    " .. exc .. ": " .. desc_tabstop())
    end
  end

  if data.has_return then
    table.insert(lines, "")
    table.insert(lines, indent .. "Returns:")
    local rtype = data.return_type and (data.return_type .. ": ") or ""
    table.insert(lines, indent .. "    " .. rtype .. desc_tabstop())
  end

  table.insert(lines, indent .. '"""')
  return lines
end

--- Format a function docstring in NumPy style
--- @param data table Parsed function data
--- @param indent string
--- @return string[]
local function format_numpy_function(data, indent)
  reset_tabstops()
  local lines = {}

  table.insert(lines, indent .. '"""' .. summary_tabstop())

  if #data.params > 0 then
    table.insert(lines, "")
    table.insert(lines, indent .. "Parameters")
    table.insert(lines, indent .. "----------")
    for _, p in ipairs(data.params) do
      local type_hint = p.type or tabstop("_type_")
      table.insert(lines, indent .. p.name .. " : " .. type_hint)
      local default_hint = p.default and (" (default: " .. p.default .. ")") or ""
      table.insert(lines, indent .. "    " .. desc_tabstop() .. default_hint)
    end
  end

  if #data.raises > 0 then
    table.insert(lines, "")
    table.insert(lines, indent .. "Raises")
    table.insert(lines, indent .. "------")
    for _, exc in ipairs(data.raises) do
      table.insert(lines, indent .. exc)
      table.insert(lines, indent .. "    " .. desc_tabstop())
    end
  end

  if data.has_return then
    table.insert(lines, "")
    table.insert(lines, indent .. "Returns")
    table.insert(lines, indent .. "-------")
    local rtype = data.return_type or tabstop("_type_")
    table.insert(lines, indent .. rtype)
    table.insert(lines, indent .. "    " .. desc_tabstop())
  end

  table.insert(lines, indent .. '"""')
  return lines
end

--- Format a function docstring in Sphinx (reST) style
--- @param data table Parsed function data
--- @param indent string
--- @return string[]
local function format_sphinx_function(data, indent)
  reset_tabstops()
  local lines = {}

  table.insert(lines, indent .. '"""' .. summary_tabstop())

  if #data.params > 0 then
    table.insert(lines, "")
    for _, p in ipairs(data.params) do
      table.insert(lines,
        indent .. ":param " .. p.name .. ": " .. desc_tabstop())
      if p.type then
        table.insert(lines,
          indent .. ":type " .. p.name .. ": " .. p.type)
      end
    end
  end

  if #data.raises > 0 then
    for _, exc in ipairs(data.raises) do
      table.insert(lines, indent .. ":raises " .. exc .. ": " .. desc_tabstop())
    end
  end

  if data.has_return then
    table.insert(lines, indent .. ":returns: " .. desc_tabstop())
    if data.return_type then
      table.insert(lines, indent .. ":rtype: " .. data.return_type)
    end
  end

  table.insert(lines, indent .. '"""')
  return lines
end

--- Format a function docstring in simple/minimal style
--- @param data table Parsed function data
--- @param indent string
--- @return string[]
local function format_simple_function(data, indent)
  reset_tabstops()
  local lines = {}

  table.insert(lines, indent .. '"""' .. summary_tabstop())

  if #data.params > 0 then
    table.insert(lines, "")
    for _, p in ipairs(data.params) do
      local type_hint = p.type and (" (" .. p.type .. ")") or ""
      table.insert(lines,
        indent .. "- " .. p.name .. type_hint .. ": " .. desc_tabstop())
    end
  end

  if data.has_return then
    table.insert(lines, "")
    local rtype = data.return_type and (" (" .. data.return_type .. ")") or ""
    table.insert(lines, indent .. "Returns" .. rtype .. ": " .. desc_tabstop())
  end

  table.insert(lines, indent .. '"""')
  return lines
end

--- Format a class docstring in Google style
--- @param data table Parsed class data
--- @param indent string
--- @return string[]
local function format_google_class(data, indent)
  reset_tabstops()
  local lines = {}

  table.insert(lines, indent .. '"""' .. summary_tabstop())

  if #data.attributes > 0 then
    table.insert(lines, "")
    table.insert(lines, indent .. "Attributes:")
    for _, attr in ipairs(data.attributes) do
      table.insert(lines, indent .. "    " .. attr .. ": " .. desc_tabstop())
    end
  end

  table.insert(lines, indent .. '"""')
  return lines
end

--- Format a class docstring in NumPy style
--- @param data table Parsed class data
--- @param indent string
--- @return string[]
local function format_numpy_class(data, indent)
  reset_tabstops()
  local lines = {}

  table.insert(lines, indent .. '"""' .. summary_tabstop())

  if #data.init_params and #data.init_params > 0 then
    table.insert(lines, "")
    table.insert(lines, indent .. "Parameters")
    table.insert(lines, indent .. "----------")
    for _, p in ipairs(data.init_params) do
      local type_hint = p.type or tabstop("_type_")
      table.insert(lines, indent .. p.name .. " : " .. type_hint)
      table.insert(lines, indent .. "    " .. desc_tabstop())
    end
  end

  if #data.attributes > 0 then
    table.insert(lines, "")
    table.insert(lines, indent .. "Attributes")
    table.insert(lines, indent .. "----------")
    for _, attr in ipairs(data.attributes) do
      table.insert(lines, indent .. attr .. " : " .. tabstop("_type_"))
      table.insert(lines, indent .. "    " .. desc_tabstop())
    end
  end

  table.insert(lines, indent .. '"""')
  return lines
end

--- Format a class docstring in Sphinx style
--- @param data table Parsed class data
--- @param indent string
--- @return string[]
local function format_sphinx_class(data, indent)
  reset_tabstops()
  local lines = {}

  table.insert(lines, indent .. '"""' .. summary_tabstop())

  if #data.init_params and #data.init_params > 0 then
    table.insert(lines, "")
    for _, p in ipairs(data.init_params) do
      table.insert(lines, indent .. ":param " .. p.name .. ": " .. desc_tabstop())
      if p.type then
        table.insert(lines, indent .. ":type " .. p.name .. ": " .. p.type)
      end
    end
  end

  table.insert(lines, indent .. '"""')
  return lines
end

--- Format a class docstring in simple style
--- @param data table Parsed class data
--- @param indent string
--- @return string[]
local function format_simple_class(data, indent)
  reset_tabstops()
  local lines = {}

  table.insert(lines, indent .. '"""' .. summary_tabstop())

  if #data.attributes > 0 then
    table.insert(lines, "")
    for _, attr in ipairs(data.attributes) do
      table.insert(lines, indent .. "- " .. attr .. ": " .. desc_tabstop())
    end
  end

  table.insert(lines, indent .. '"""')
  return lines
end

--- Style dispatch tables
local function_formatters = {
  google = format_google_function,
  numpy = format_numpy_function,
  sphinx = format_sphinx_function,
  simple = format_simple_function,
}

local class_formatters = {
  google = format_google_class,
  numpy = format_numpy_class,
  sphinx = format_sphinx_class,
  simple = format_simple_class,
}

--- Format parsed data into docstring lines
--- @param data table Parsed data from M.parse()
--- @param style string Docstring style name
--- @param indent string Indentation prefix
--- @return string[]
function M.format(data, style, indent)
  if data.kind == "function" then
    local formatter = function_formatters[style] or function_formatters.google
    return formatter(data, indent)
  end

  if data.kind == "class" then
    local formatter = class_formatters[style] or class_formatters.google
    return formatter(data, indent)
  end

  return {}
end

return M
