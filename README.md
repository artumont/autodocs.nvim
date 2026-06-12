# autodocs.nvim

Treesitter-powered documentation block generator with blink.cmp integration.

## Usage

Configure with `lazy.nvim`:

```lua
return {
  {
    "artumont/autodocs.nvim",
    dependencies = { "saghen/blink.cmp" },
    opts = {
      style = "google",
    },
  }
}
```

Add the source to your `blink.cmp` configuration:

```lua
require("blink.cmp").setup({
  sources = {
    default = { "lsp", "path", "snippets", "buffer", "autodocs" },
    providers = {
      autodocs = {
        name = "autodocs",
        module = "autodocs.blink",
        score_offset = 100,
      },
    },
  },
})
```

## Features

- **Treesitter AST Parsing**: Resolves function definitions, parameter names, types, defaults, raises, and class attributes.
- **Completion Trigger**: Spawns directly in `blink.cmp` when typing trigger sequences (e.g. `"""` or `'''` in Python, `---` in Lua).
- **Snippet Placeholders**: Generates LSP snippets with default tabstop placeholders (`${1:_summary_}`, `${2:_description_}`).
- **Manual Command**: `:AutodocsGenerate` extracts docstring data and prints/inserts at cursor line without snippet formatting.

## Configuration

Defaults:

```lua
require("autodocs").setup({
  -- Default style applied to all files (google, numpy, sphinx, simple)
  style = "google",

  -- Per-language overrides
  languages = {
    python = {
      style = nil, -- Inherit global style
      trigger = { '"', "'" },
      pattern = '^%s*["\'][\'"]+$',
    },
    lua = {
      style = "ldoc",
      trigger = { "-" },
      pattern = "^%s*%-%-%-$",
    },
  },

  -- Parameters to exclude from generation
  exclude_params = {
    python = { "self", "cls" },
    lua = {},
  },

  -- Return types to exclude from generation
  exclude_returns = {
    python = { "None" },
    lua = {},
  },
})
```

## Supported Languages & Styles

### Python
Supports Google, NumPy, Sphinx, and Simple styles. Parses function parameters, types, defaults, return annotations/values, and raise statements. For classes, parses `__init__` constructor parameter variables and assignment target attributes (`self.x`).

#### Google
```python
"""${1:_summary_}

Args:
    param_name (type): ${2:_description_}. Defaults to value.

Raises:
    ErrorType: ${3:_description_}

Returns:
    return_type: ${4:_description_}
"""
```

#### NumPy
```python
"""${1:_summary_}

Parameters
----------
param_name : type
    ${2:_description_} (default: value)

Returns
-------
return_type
    ${3:_description_}
"""
```

#### Sphinx
```python
"""${1:_summary_}

:param param_name: ${2:_description_}
:type param_name: type
:returns: ${3:_description_}
:rtype: return_type
"""
```

#### Simple
```python
"""${1:_summary_}

- param_name (type): ${2:_description_}
Returns (return_type): ${3:_description_}
"""
```

### Lua
Supports LDoc syntax. Parses local/global functions, parameters, varargs (`...`), and return statements.

```lua
--- ${1:_summary_}
--- @param param_name ${2:_type_} ${3:_description_}
--- @vararg ${4:_type_}
--- @return ${5:_type_} ${6:_description_}
```

## Adding Custom Languages

Define a parser/formatter module under `lua/autodocs/languages/<filetype>.lua`:

```lua
local M = {}

M.triggers = { "-" }

function M.parse(bufnr, row)
  -- Use Treesitter to parse construct at row
  -- Return a custom data table
  return { kind = "function", name = "foo", params = {} }
end

function M.format(data, style, indent)
  -- Format using snippet syntax ${index:placeholder}
  return { indent .. "--- ${1:_summary_}" }
end

return M
```

Then append the filetype to the `supported` list in `lua/autodocs/languages/init.lua`.
