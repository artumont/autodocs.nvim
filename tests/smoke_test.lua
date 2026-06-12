-- Smoke test: verify all autodocs modules load without errors
-- Run with: nvim --headless -u NONE --cmd 'set rtp+=.' -l tests/smoke_test.lua

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

print("autodocs.nvim smoke tests")
print(string.rep("-", 40))

test("require autodocs.config", function()
  local config = require("autodocs.config")
  assert(config.defaults, "missing defaults")
  assert(config.setup, "missing setup()")
  assert(config.get_style, "missing get_style()")
end)

test("config.setup merges options", function()
  local config = require("autodocs.config")
  config.setup({ style = "numpy" })
  assert(config.options.style == "numpy", "expected numpy, got " .. config.options.style)
  config.setup({}) -- reset
end)

test("config.get_style returns correct style", function()
  local config = require("autodocs.config")
  config.setup({ style = "sphinx", languages = { python = { style = "numpy" } } })
  assert(config.get_style("python") == "numpy", "expected numpy for python")
  -- Lua has style="ldoc" in defaults, so test fallback with a filetype that has no override
  assert(config.get_style("rust") == "sphinx", "expected sphinx fallback for unconfigured filetype")
  config.setup({})
end)

test("require autodocs.languages", function()
  local langs = require("autodocs.languages")
  assert(langs.get, "missing get()")
  assert(langs.is_supported, "missing is_supported()")
  assert(langs.parse, "missing parse()")
  assert(langs.format, "missing format()")
end)

test("require autodocs.languages.python", function()
  local py = require("autodocs.languages.python")
  assert(py.parse, "missing parse()")
  assert(py.format, "missing format()")
  assert(py.triggers, "missing triggers")
end)

test("require autodocs.languages.lua", function()
  local lua_lang = require("autodocs.languages.lua")
  assert(lua_lang.parse, "missing parse()")
  assert(lua_lang.format, "missing format()")
  assert(lua_lang.triggers, "missing triggers")
end)

test("require autodocs.blink", function()
  -- blink source needs blink.cmp.types at runtime, so we mock it
  package.loaded["blink.cmp.types"] = {
    CompletionItemKind = { Snippet = 15, Text = 1 },
  }
  local blink = require("autodocs.blink")
  assert(blink.new, "missing new()")
  local instance = blink.new({})
  assert(instance.get_completions, "missing get_completions()")
  assert(instance.get_trigger_characters, "missing get_trigger_characters()")
end)

test("require autodocs (init)", function()
  local autodocs = require("autodocs")
  assert(autodocs.setup, "missing setup()")
  assert(autodocs.generate, "missing generate()")
end)

test("python format google function", function()
  local py = require("autodocs.languages.python")
  local data = {
    kind = "function",
    name = "test",
    params = {
      { name = "x", type = "int", default = nil },
      { name = "y", type = "str", default = '"hello"' },
    },
    return_type = "bool",
    has_return = true,
    raises = { "ValueError" },
  }
  local lines = py.format(data, "google", "    ")
  assert(#lines > 0, "expected lines, got none")
  assert(lines[1]:match('"""'), "first line should contain triple quotes")
  assert(lines[#lines]:match('"""'), "last line should contain triple quotes")

  local joined = table.concat(lines, "\n")
  assert(joined:match("Args:"), "expected Args section")
  assert(joined:match("Returns:"), "expected Returns section")
  assert(joined:match("Raises:"), "expected Raises section")
  assert(joined:match("ValueError"), "expected ValueError in Raises")
end)

test("python format numpy function", function()
  local py = require("autodocs.languages.python")
  local data = {
    kind = "function",
    name = "test",
    params = { { name = "x", type = "int", default = nil } },
    return_type = "float",
    has_return = true,
    raises = {},
  }
  local lines = py.format(data, "numpy", "    ")
  local joined = table.concat(lines, "\n")
  assert(joined:match("Parameters"), "expected Parameters section")
  assert(joined:match("----------"), "expected underline dashes")
  assert(joined:match("Returns"), "expected Returns section")
end)

test("python format sphinx function", function()
  local py = require("autodocs.languages.python")
  local data = {
    kind = "function",
    name = "test",
    params = { { name = "x", type = "int", default = nil } },
    return_type = "str",
    has_return = true,
    raises = {},
  }
  local lines = py.format(data, "sphinx", "    ")
  local joined = table.concat(lines, "\n")
  assert(joined:match(":param x:"), "expected :param x:")
  assert(joined:match(":type x: int"), "expected :type x:")
  assert(joined:match(":returns:"), "expected :returns:")
  assert(joined:match(":rtype: str"), "expected :rtype:")
end)

test("python format class google", function()
  local py = require("autodocs.languages.python")
  local data = {
    kind = "class",
    name = "MyClass",
    superclasses = { "Base" },
    attributes = { "x", "y" },
    init_params = { { name = "x", type = "int" } },
  }
  local lines = py.format(data, "google", "    ")
  local joined = table.concat(lines, "\n")
  assert(joined:match("Attributes:"), "expected Attributes section")
  assert(joined:match("x:"), "expected attribute x")
end)

test("lua format ldoc function", function()
  local lua_lang = require("autodocs.languages.lua")
  local data = {
    kind = "function",
    name = "greet",
    params = { "name", "greeting" },
    has_return = true,
  }
  local lines = lua_lang.format(data, "ldoc", "")
  assert(#lines > 0, "expected lines")
  assert(lines[1]:match("^%-%-%- "), "first line should be --- summary")

  local joined = table.concat(lines, "\n")
  assert(joined:match("@param name"), "expected @param name")
  assert(joined:match("@param greeting"), "expected @param greeting")
  assert(joined:match("@return"), "expected @return")
end)

test("lua format ldoc with varargs", function()
  local lua_lang = require("autodocs.languages.lua")
  local data = {
    kind = "function",
    name = "variadic",
    params = { "x", "..." },
    has_return = false,
  }
  local lines = lua_lang.format(data, "ldoc", "")
  local joined = table.concat(lines, "\n")
  assert(joined:match("@param x"), "expected @param x")
  assert(joined:match("@vararg"), "expected @vararg for ...")
  assert(not joined:match("@return"), "should not have @return")
end)

print(string.rep("-", 40))
print(string.format("Results: %d passed, %d failed", passed, failed))

if failed > 0 then
  os.exit(1)
end
