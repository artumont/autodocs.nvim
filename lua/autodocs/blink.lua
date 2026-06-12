--- @module "autodocs.blink"
--- blink.cmp custom source provider for autodocs.nvim
--- Shows a "Generate docstring" completion item when the user types
--- language-specific docstring triggers (e.g. """ in Python, --- in Lua)

local config = require("autodocs.config")
local languages = require("autodocs.languages")

--- @class blink.cmp.Source
local source = {}

--- Create a new source instance
--- @param opts? table Provider options from blink.cmp configuration
--- @return blink.cmp.Source
function source.new(opts)
  local self = setmetatable({}, { __index = source })
  self.opts = opts or {}
  return self
end

--- Enable only for filetypes that have a registered language module
--- @return boolean
function source:enabled()
  local ft = vim.bo.filetype
  return languages.is_supported(ft)
end

--- Return trigger characters based on the current filetype
--- @return string[]
function source:get_trigger_characters()
  local ft = vim.bo.filetype
  local triggers = config.get_triggers(ft)
  if #triggers > 0 then
    return triggers
  end
  return languages.get_triggers(ft)
end

--- Determine the trigger pattern for the current filetype
--- @return string|nil
local function get_trigger_pattern()
  local ft = vim.bo.filetype
  return config.get_pattern(ft)
end

--- Get the line content and indentation at the cursor
--- @param ctx table blink.cmp context
--- @return string|nil line, string|nil indent, number|nil row
local function get_cursor_context(ctx)
  local cursor = ctx.cursor
  if not cursor then
    return nil, nil, nil
  end

  local row = cursor[1] - 1 -- 0-indexed
  local col = cursor[2]
  local bufnr = ctx.bufnr or vim.api.nvim_get_current_buf()

  local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)
  if not lines or #lines == 0 then
    return nil, nil, nil
  end

  local full_line = lines[1]
  -- Get text up to the cursor position
  local line_to_cursor = full_line:sub(1, col)
  local indent = full_line:match("^(%s*)") or ""

  return line_to_cursor, indent, row
end

--- Check if the current line matches the trigger pattern
--- @param ctx table blink.cmp context
--- @return boolean matches, string indent, number row
local function check_trigger(ctx)
  local line, indent, row = get_cursor_context(ctx)
  if not line or not indent or not row then
    return false, "", 0
  end

  local pattern = get_trigger_pattern()
  if not pattern then
    return false, indent, row
  end

  if line:match(pattern) then
    return true, indent, row
  end

  return false, indent, row
end

--- Fetch completions: returns "Generate docstring" when trigger matches
--- @param ctx table blink.cmp context
--- @param callback function Callback to return items
function source:get_completions(ctx, callback)
  local matches, indent, row = check_trigger(ctx)
  if not matches then
    callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
    return
  end

  local ft = vim.bo.filetype
  local bufnr = ctx.bufnr or vim.api.nvim_get_current_buf()

  -- Parse the nearby construct
  local data = languages.parse(ft, bufnr, row)
  if not data then
    callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
    return
  end

  -- Get the docstring style
  local style = config.get_style(ft)

  -- Format the docstring
  local doc_lines = languages.format(ft, data, style, indent)
  if not doc_lines or #doc_lines == 0 then
    callback({ items = {}, is_incomplete_forward = false, is_incomplete_backward = false })
    return
  end

  -- Join into a snippet string
  local snippet_text = table.concat(doc_lines, "\n")

  -- Build a documentation preview (with placeholders replaced for readability)
  local preview = snippet_text:gsub("%$%d+", "...")

  -- Compute the text range to replace (the entire trigger line)
  local line_content = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

  --- @type lsp.CompletionItem
  local item = {
    label = "Generate docstring",
    kind = require("blink.cmp.types").CompletionItemKind.Snippet,
    detail = "autodocs · " .. style .. " · " .. data.kind,
    documentation = {
      kind = "markdown",
      value = "```" .. ft .. "\n" .. preview .. "\n```",
    },
    insertTextFormat = vim.lsp.protocol.InsertTextFormat.Snippet,
    -- Replace the entire trigger line with the docstring
    textEdit = {
      newText = snippet_text,
      range = {
        start = { line = row, character = 0 },
        ["end"] = { line = row, character = #line_content },
      },
    },
    -- Sort to the top
    sortText = "!0000",
    filterText = line_content:match("^%s*(.+)$") or line_content,
  }

  callback({
    items = { item },
    is_incomplete_forward = false,
    is_incomplete_backward = false,
  })
end

--- Resolve: populate documentation lazily (already done in get_completions)
--- @param item lsp.CompletionItem
--- @param callback function
function source:resolve(item, callback)
  callback(item)
end

return source
