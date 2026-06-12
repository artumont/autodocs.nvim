--- @module "autodocs.languages"
--- Language registry — loads and resolves language-specific parsers/formatters

local M = {}

--- Registry of loaded language modules
--- @type table<string, table>
M._registry = {}

--- Supported language filetypes
M.supported = {
  "python",
  "lua",
}

--- Load and cache a language module by filetype
--- @param filetype string
--- @return table|nil The language module, or nil if unsupported
function M.get(filetype)
  if M._registry[filetype] then
    return M._registry[filetype]
  end

  local ok, mod = pcall(require, "autodocs.languages." .. filetype)
  if ok and mod then
    M._registry[filetype] = mod
    return mod
  end

  return nil
end

--- Check if a filetype is supported
--- @param filetype string
--- @return boolean
function M.is_supported(filetype)
  return M.get(filetype) ~= nil
end

--- Parse the construct (function/class) near the given position
--- Delegates to the language-specific parser
--- @param filetype string
--- @param bufnr number
--- @param row number 0-indexed row
--- @return table|nil Parsed data table, or nil if nothing found
function M.parse(filetype, bufnr, row)
  local lang = M.get(filetype)
  if not lang then
    return nil
  end
  return lang.parse(bufnr, row)
end

--- Format a docstring from parsed data
--- Delegates to the language-specific formatter
--- @param filetype string
--- @param data table Parsed data from `parse()`
--- @param style string Docstring style name
--- @param indent string Indentation prefix string
--- @return string[] Lines of the formatted docstring
function M.format(filetype, data, style, indent)
  local lang = M.get(filetype)
  if not lang then
    return {}
  end
  return lang.format(data, style, indent)
end

--- Get trigger characters for a filetype from the language module
--- @param filetype string
--- @return string[]
function M.get_triggers(filetype)
  local lang = M.get(filetype)
  if lang and lang.triggers then
    return lang.triggers
  end
  return {}
end

return M
