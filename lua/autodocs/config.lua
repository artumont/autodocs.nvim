--- @module "autodocs.config"
--- Configuration defaults and user option merging for autodocs.nvim

local M = {}

--- @class autodocs.Config
--- @field style string Default docstring style (google, numpy, sphinx, simple)
--- @field languages table<string, table> Per-language overrides
--- @field exclude_params table<string, string[]> Parameters to exclude per language
M.defaults = {
  --- Default docstring style for all languages
  style = "google",

  --- Per-language configuration overrides
  --- Each key is a filetype, each value is a table with:
  ---   style: string — override the default style for this language
  ---   trigger: string[] — characters that trigger the completion
  ---   pattern: string — lua pattern to match the trigger line
  languages = {
    python = {
      style = nil, -- inherit from top-level default
      trigger = { '"', "'" },
      pattern = '^%s*["\'][\'"]+$',
    },
    lua = {
      style = "ldoc",
      trigger = { "-" },
      pattern = "^%s*%-%-%-$",
    },
  },

  --- Parameters to automatically exclude from generated docstrings
  exclude_params = {
    python = { "self", "cls" },
    lua = {},
  },

  --- Return types to automatically exclude from generated docstrings
  exclude_returns = {
    python = { "None" },
    lua = {},
  },
}

--- @type autodocs.Config
M.options = vim.deepcopy(M.defaults)

--- Merge user options with defaults
--- @param opts? table User-provided options
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

--- Get the resolved style for a given filetype
--- @param filetype string
--- @return string
function M.get_style(filetype)
  local lang_cfg = M.options.languages[filetype]
  if lang_cfg and lang_cfg.style then
    return lang_cfg.style
  end
  return M.options.style
end

--- Get the trigger characters for a given filetype
--- @param filetype string
--- @return string[]
function M.get_triggers(filetype)
  local lang_cfg = M.options.languages[filetype]
  if lang_cfg and lang_cfg.trigger then
    return lang_cfg.trigger
  end
  return {}
end

--- Get the trigger pattern for a given filetype
--- @param filetype string
--- @return string|nil
function M.get_pattern(filetype)
  local lang_cfg = M.options.languages[filetype]
  if lang_cfg then
    return lang_cfg.pattern
  end
  return nil
end

--- Get the excluded parameters for a given filetype
--- @param filetype string
--- @return string[]
function M.get_excluded_params(filetype)
  return M.options.exclude_params[filetype] or {}
end

--- Get the excluded return types for a given filetype
--- @param filetype string
--- @return string[]
function M.get_excluded_returns(filetype)
  return M.options.exclude_returns[filetype] or {}
end

return M
