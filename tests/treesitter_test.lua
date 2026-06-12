-- Integration test: verify Treesitter parsing of Python source code
-- Run with: nvim --headless -u NONE --cmd 'set rtp+=.' -l tests/treesitter_test.lua

local passed = 0
local failed = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  ✓ " .. name)
  else
    failed = failed + 1
    print("  ✗ " .. name .. ": " .. tostring(err))
  end
end

-- Check if Python treesitter parser is available
local parser_ok = pcall(vim.treesitter.get_string_parser, "pass", "python")
if not parser_ok then
  print("⚠ Python treesitter parser not installed, skipping integration tests")
  os.exit(0)
end

-- We need a real buffer for the parser, so create scratch buffers
local function create_python_buf(source_lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, source_lines)
  vim.bo[bufnr].filetype = "python"
  return bufnr
end

local py = require("autodocs.languages.python")
require("autodocs.config").setup({ exclude_params = { python = { "self", "cls" } } })

print("autodocs.nvim Treesitter integration tests (Python)")
print(string.rep("-", 50))

test("parse simple function", function()
  -- Simulate: cursor on row 1 (the """ line), function def is on row 0
  -- The parser looks at row, then row+1, walking up parents
  local bufnr = create_python_buf({
    "def greet(name, age):",
    '    """',
    "    pass",
  })
  -- Row 1 is the """ line — parser will walk up to find function_definition
  local data = py.parse(bufnr, 1)
  assert(data, "expected parsed data")
  assert(data.kind == "function", "expected function, got " .. tostring(data.kind))
  assert(data.name == "greet", "expected greet, got " .. data.name)
  assert(#data.params == 2, "expected 2 params, got " .. #data.params)
  assert(data.params[1].name == "name", "expected param 'name'")
  assert(data.params[2].name == "age", "expected param 'age'")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("parse typed function with return type", function()
  local bufnr = create_python_buf({
    "def calc(x: int, y: float = 1.0) -> str:",
    '    """',
    "    return str(x + y)",
  })
  local data = py.parse(bufnr, 1)
  assert(data, "expected parsed data")
  assert(data.params[1].name == "x", "expected param x")
  assert(data.params[1].type == "int", "expected type int, got " .. tostring(data.params[1].type))
  assert(data.params[2].name == "y", "expected param y")
  assert(data.params[2].type == "float", "expected type float")
  assert(data.params[2].default == "1.0", "expected default 1.0, got " .. tostring(data.params[2].default))
  assert(data.return_type == "str", "expected return_type str, got " .. tostring(data.return_type))
  assert(data.has_return == true, "expected has_return true")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("parse function with *args and **kwargs", function()
  local bufnr = create_python_buf({
    "def variadic(a, *args, **kwargs):",
    '    """',
    "    pass",
  })
  local data = py.parse(bufnr, 1)
  assert(data, "expected parsed data")
  assert(#data.params == 3, "expected 3 params, got " .. #data.params)
  assert(data.params[1].name == "a")
  assert(data.params[2].name == "*args", "expected *args, got " .. data.params[2].name)
  assert(data.params[3].name == "**kwargs", "expected **kwargs, got " .. data.params[3].name)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("excludes self and cls", function()
  local bufnr = create_python_buf({
    "def method(self, x, y):",
    '    """',
    "    pass",
  })
  local data = py.parse(bufnr, 1)
  assert(data, "expected parsed data")
  assert(#data.params == 2, "expected 2 params (self excluded), got " .. #data.params)
  assert(data.params[1].name == "x")
  assert(data.params[2].name == "y")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("parse function with raises", function()
  -- Use a pass placeholder instead of unclosed """ which corrupts the AST
  local bufnr = create_python_buf({
    "def validate(x):",
    "    pass",
    '    raise ValueError("bad")',
    "    raise TypeError",
  })
  -- Parse from row 1 (inside the function body)
  local data = py.parse(bufnr, 1)
  assert(data, "expected parsed data")
  assert(#data.raises == 2, "expected 2 raises, got " .. #data.raises)
  assert(data.raises[1] == "ValueError", "expected ValueError")
  assert(data.raises[2] == "TypeError", "expected TypeError")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("parse class with attributes", function()
  local bufnr = create_python_buf({
    "class MyClass(Base):",
    '    """',
    "    def __init__(self, x: int, y):",
    "        self.x = x",
    "        self.y = y",
    "        self.z = 42",
  })
  local data = py.parse(bufnr, 1)
  assert(data, "expected parsed data")
  assert(data.kind == "class", "expected class, got " .. tostring(data.kind))
  assert(data.name == "MyClass", "expected MyClass, got " .. data.name)
  assert(#data.attributes == 3, "expected 3 attrs, got " .. #data.attributes)
  assert(#data.init_params == 2, "expected 2 init params (self excluded), got " .. #data.init_params)
  assert(data.superclasses[1] == "Base", "expected superclass Base")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

test("format google generates valid snippet", function()
  local bufnr = create_python_buf({
    "def example(a: int, b: str = 'x') -> bool:",
    "    pass",
    '    raise RuntimeError("fail")',
    "    return True",
  })
  local data = py.parse(bufnr, 1)
  assert(data, "expected parsed data")
  local lines = py.format(data, "google", "    ")
  local joined = table.concat(lines, "\n")

  assert(joined:match('"""'), "should contain triple quotes")
  assert(joined:match("Args:"), "should contain Args section")
  assert(joined:match("a %(int%)"), "should contain a (int)")
  assert(joined:match("b %(str%)"), "should contain b (str)")
  assert(joined:match("Defaults to 'x'"), "should mention default")
  assert(joined:match("Raises:"), "should contain Raises section")
  assert(joined:match("RuntimeError"), "should contain RuntimeError")
  assert(joined:match("Returns:"), "should contain Returns section")
  assert(joined:match("bool"), "should contain return type bool")
  assert(joined:match("%$1"), "should contain snippet tabstop $1")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end)

print(string.rep("-", 50))
print(string.format("Results: %d passed, %d failed", passed, failed))

if failed > 0 then
  os.exit(1)
end
