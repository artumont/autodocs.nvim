--- @module "autodocs.init"
--- Initializes the `autodocs.nvim` plugin
--- Provides setup() for user configuration and a manual :AutodocsGenerate command

local config = require("autodocs.config")
local languages = require("autodocs.languages")

local M = {}

--- Setup the plugin with user options
--- @param opts? table User configuration options
---
--- Example:
--- ```lua
--- require("autodocs").setup({
---   style = "google",    -- Default style: "google", "numpy", "sphinx", "simple"
---   languages = {
---     python = { style = "numpy" },  -- Override style per language
---   },
---   exclude_params = {
---     python = { "self", "cls" },
---   },
--- })
--- ```
function M.setup(opts)
  config.setup(opts)

  -- Register user command
  vim.api.nvim_create_user_command("AutodocsGenerate", function()
    M.generate()
  end, {
    desc = "Generate a docstring for the function/class at cursor",
  })
end

--- Manually generate and insert a docstring at the cursor position
function M.generate()
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype

  if not languages.is_supported(ft) then
    vim.notify("[autodocs] Unsupported filetype: " .. ft, vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1 -- 0-indexed

  -- Parse the construct
  local data = languages.parse(ft, bufnr, row)
  if not data then
    vim.notify("[autodocs] No function or class found near cursor", vim.log.levels.WARN)
    return
  end

  -- Get indentation from the current line
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local indent = line:match("^(%s*)") or ""

  -- Get the style and format
  local style = config.get_style(ft)
  local doc_lines = languages.format(ft, data, style, indent)
  if not doc_lines or #doc_lines == 0 then
    vim.notify("[autodocs] Could not generate docstring", vim.log.levels.WARN)
    return
  end

  -- Strip snippet tabstops for plain text insertion
  local clean_lines = {}
  for _, l in ipairs(doc_lines) do
    table.insert(clean_lines, (l:gsub("%$%d+", "")))
  end

  -- Insert the lines at the current row (replacing the current line)
  vim.api.nvim_buf_set_lines(bufnr, row, row + 1, false, clean_lines)

  -- Move cursor to the first line of the docstring
  vim.api.nvim_win_set_cursor(0, { row + 1, #indent })
end

return M
