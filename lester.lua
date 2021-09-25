--[[
Minimal test framework for Lua.
lester - v0.1.2 - 15/Feb/2021
Eduardo Bart - edub4rt@gmail.com
https://github.com/edubart/lester
Minimal Lua test framework.
See end of file for LICENSE.
]]

--[[--
Lester is a minimal unit testing framework for Lua with a focus on being simple to use.

## Features

* Minimal, just one file.
* Self contained, no external dependencies.
* Simple and hackable when needed.
* Use `describe` and `it` blocks to describe tests.
* Supports `before` and `after` handlers.
* Colored output.
* Configurable via the script or with environment variables.
* Quiet mode, to use in live development.
* Optionally filter tests by name.
* Show traceback on errors.
* Show time to complete tests.
* Works with Lua 5.1+.
* Efficient.

## Usage

Copy `lester.lua` file to a project and require it,
which returns a table that includes all of the functionality:

```lua
local lester = require 'lester'
local describe, it, expect = lester.describe, lester.it, lester.expect

-- Customize lester configuration.
lester.show_traceback = false

describe('my project', function()
  lester.before(function()
    -- This function is run before every test.
  end)

  describe('module1', function() -- Describe blocks can be nested.
    it('feature1', function()
      expect.equal('something', 'something') -- Pass.
    end)

    it('feature2', function()
      expect.truthy(false) -- Fail.
    end)
  end)
end)

lester.report() -- Print overall statistic of the tests run.
lester.exit() -- Exit with success if all tests passed.
```

## Customizing output with environment variables

To customize the output of lester externally,
you can set the following environment variables before running a test suite:

* `LESTER_QUIET="true"`, omit print of passed tests.
* `LESTER_COLORED="false"`, disable colored output.
* `LESTER_SHOW_TRACEBACK="false"`, disable traceback on test failures.
* `LESTER_SHOW_ERROR="false"`, omit print of error description of failed tests.
* `LESTER_STOP_ON_FAIL="true"`, stop on first test failure.
* `LESTER_UTF8TERM="false"`, disable printing of UTF-8 characters.
* `LESTER_FILTER="some text"`, filter the tests that should be run.

Note that these configurations can be changed via script too, check the documentation.

]]

-- Returns whether the terminal supports UTF-8 characters.
local function is_utf8term()
    local lang = os.getenv('LANG')
    return (lang and lang:lower():match('utf%-8$')) and true or false
  end
  
  -- Returns whether a system environment variable is "true".
  local function getboolenv(varname, default)
    local val = os.getenv(varname)
    if val == 'true' then
      return true
    elseif val == 'false' then
      return false
    end
    return default
  end
  
  -- The lester module.
  local lester = {
    --- Weather lines of passed tests should not be printed. False by default.
    quiet = getboolenv('LESTER_QUIET', false),
    --- Weather the output should  be colorized. True by default.
    colored = getboolenv('LESTER_COLORED', true),
    --- Weather a traceback must be shown on test failures. True by default.
    show_traceback = getboolenv('LESTER_SHOW_TRACEBACK', true),
    --- Weather the error description of a test failure should be shown. True by default.
    show_error = getboolenv('LESTER_SHOW_ERROR', true),
    --- Weather test suite should exit on first test failure. False by default.
    stop_on_fail = getboolenv('LESTER_STOP_ON_FAIL', false),
    --- Weather we can print UTF-8 characters to the terminal. True by default when supported.
    utf8term = getboolenv('LESTER_UTF8TERM', is_utf8term()),
    --- A string with a lua pattern to filter tests. Nil by default.
    filter = os.getenv('LESTER_FILTER'),
    --- Function to retrieve time in seconds with milliseconds precision, `os.clock` by default.
    seconds = os.clock,
  }
  
  -- Variables used internally for the lester state.
  local lester_start = nil
  local last_succeeded = false
  local level = 0
  local successes = 0
  local total_successes = 0
  local failures = 0
  local total_failures = 0
  local start = 0
  local befores = {}
  local afters = {}
  local names = {}
  
  -- Color codes.
  local color_codes = {
    reset = string.char(27) .. '[0m',
    bright = string.char(27) .. '[1m',
    red = string.char(27) .. '[31m',
    green = string.char(27) .. '[32m',
    blue = string.char(27) .. '[34m',
    magenta = string.char(27) .. '[35m',
  }
  
  -- Colors table, returning proper color code if colored mode is enabled.
  local colors = setmetatable({}, { __index = function(_, key)
    return lester.colored and color_codes[key] or ''
  end})
  
  --- Table of terminal colors codes, can be customized.
  lester.colors = colors
  
  --- Describe a block of tests, which consists in a set of tests.
  -- Describes can be nested.
  -- @param name A string used to describe the block.
  -- @param func A function containing all the tests or other describes.
  function lester.describe(name, func)
    if level == 0 then -- Get start time for top level describe blocks.
      start = lester.seconds()
      if not lester_start then
        lester_start = start
      end
      failures = 0
      successes = 0
    end
    -- Setup describe block variables.
    level = level + 1
    names[level] = name
    -- Run the describe block.
    func()
    -- Cleanup describe block.
    afters[level] = nil
    befores[level] = nil
    names[level] = nil
    level = level - 1
    -- Pretty print statistics for top level describe block.
    if level == 0 and not lester.quiet and (successes > 0 or failures > 0) then
      local io_write = io.write
      local colors_reset, colors_green = colors.reset, colors.green
      io_write(failures == 0 and colors_green or colors.red, '[====] ',
               colors.magenta, name, colors_reset, ' | ',
               colors_green, successes, colors_reset, ' successes / ')
      if failures > 0 then
        io_write(colors.red, failures, colors_reset, ' failures / ')
      end
      io_write(colors.bright, string.format('%.6f', lester.seconds() - start), colors_reset, ' seconds\n')
    end
  end
  
  -- Error handler used to get traceback for errors.
  local function xpcall_error_handler(err)
    return debug.traceback(tostring(err), 2)
  end
  
  -- Pretty print the line on the test file where an error happened.
  local function show_error_line(err)
    local info = debug.getinfo(3)
    local io_write = io.write
    local colors_reset = colors.reset
    local short_src, currentline = info.short_src, info.currentline
    io_write(' (', colors.blue, short_src, colors_reset,
             ':', colors.bright, currentline, colors_reset)
    if err and lester.show_traceback then
      local fnsrc = short_src..':'..currentline
      for cap1, cap2 in err:gmatch('\t[^\n:]+:(%d+): in function <([^>]+)>\n') do
        if cap2 == fnsrc then
          io_write('/', colors.bright, cap1, colors_reset)
          break
        end
      end
    end
    io_write(')')
  end
  
  -- Pretty print the test name, with breadcrumb for the describe blocks.
  local function show_test_name(name)
    local io_write = io.write
    local colors_reset = colors.reset
    for _,descname in ipairs(names) do
      io_write(colors.magenta, descname, colors_reset, ' | ')
    end
    io_write(colors.bright, name, colors_reset)
  end
  
  --- Declare a test, which consists of a set of assertions.
  -- @param name A name for the test.
  -- @param func The function containing all assertions.
  function lester.it(name, func)
    -- Skip the test if it does not match the filter.
    if lester.filter then
      local fullname = table.concat(names, ' | ')..' | '..name
      if not fullname:match(lester.filter) then
        return
      end
    end
    -- Execute before handlers.
    for _,levelbefores in ipairs(befores) do
      for _,beforefn in ipairs(levelbefores) do
        beforefn(name)
      end
    end
    -- Run the test, capturing errors if any.
    local success, err
    if lester.show_traceback then
      success, err = xpcall(func, xpcall_error_handler)
    else
      success, err = pcall(func)
      if not success and err then
        err = tostring(err)
      end
    end
    -- Count successes and failures.
    if success then
      successes = successes + 1
      total_successes = total_successes + 1
    else
      failures = failures + 1
      total_failures = total_failures + 1
    end
    local io_write = io.write
    local colors_reset = colors.reset
    -- Print the test run.
    if not lester.quiet then -- Show test status and complete test name.
      if success then
        io_write(colors.green, '[PASS] ', colors_reset)
      else
        io_write(colors.red, '[FAIL] ', colors_reset)
      end
      show_test_name(name)
      if not success then
        show_error_line(err)
      end
      io_write('\n')
    else
      if success then -- Show just a character hinting that the test succeeded.
        local o = (lester.utf8term and lester.colored) and
                  string.char(226, 151, 143) or 'o'
        io_write(colors.green, o, colors_reset)
      else -- Show complete test name on failure.
        io_write(last_succeeded and '\n' or '',
                 colors.red, '[FAIL] ', colors_reset)
        show_test_name(name)
        show_error_line(err)
        io_write('\n')
      end
    end
    -- Print error message, colorizing its output if possible.
    if err and lester.show_error then
      if lester.colored then
        local errfile, errline, errmsg, rest = err:match('^([^:\n]+):(%d+): ([^\n]+)(.*)')
        if errfile and errline and errmsg and rest then
          io_write(colors.blue, errfile, colors_reset,
                   ':', colors.bright, errline, colors_reset, ': ')
          if errmsg:match('^%w([^:]*)$') then
            io_write(colors.red, errmsg, colors_reset)
          else
            io_write(errmsg)
          end
          err = rest
        end
      end
      io_write(err, '\n\n')
    end
    io.flush()
    -- Stop on failure.
    if not success and lester.stop_on_fail then
      if lester.quiet then
        io_write('\n')
        io.flush()
      end
      lester.exit()
    end
    -- Execute after handlers.
    for _,levelafters in ipairs(afters) do
      for _,afterfn in ipairs(levelafters) do
        afterfn(name)
      end
    end
    last_succeeded = success
  end
  
  --- Set a function that is called before every test inside a describe block.
  -- A single string containing the name of the test about to be run will be passed to `func`.
  function lester.before(func)
    local levelbefores = befores[level]
    if not levelbefores then
      levelbefores = {}
      befores[level] = levelbefores
    end
    levelbefores[#levelbefores+1] = func
  end
  
  --- Set a function that is called after every test inside a describe block.
  -- A single string containing the name of the test that was finished will be passed to `func`.
  -- The function is executed independently if the test passed or failed.
  function lester.after(func)
    local levelafters = afters[level]
    if not levelafters then
      levelafters = {}
      afters[level] = levelafters
    end
    levelafters[#levelafters+1] = func
  end
  
  --- Pretty print statistics of all test runs.
  -- With total success, total failures and run time in seconds.
  function lester.report()
    local now = lester.seconds()
    local colors_reset = colors.reset
    io.write(lester.quiet and '\n' or '',
             colors.green, total_successes, colors_reset, ' successes / ',
             colors.red, total_failures, colors_reset, ' failures / ',
             colors.bright, string.format('%.6f', now - (lester_start or now)), colors_reset, ' seconds\n')
    io.flush()
    return total_failures == 0
  end
  
  --- Exit the application with success code if all tests passed, or failure code otherwise.
  function lester.exit()
    os.exit(total_failures == 0)
  end
  
  local expect = {}
  --- Expect module, containing utility function for doing assertions inside a test.
  lester.expect = expect
  
  --- Check if a function fails with an error.
  -- If `expected` is nil then any error is accepted.
  -- If `expected` is a string then we check if the error contains that string.
  -- If `expected` is anything else then we check if both are equal.
  function expect.fail(func, expected)
    local ok, err = pcall(func)
    if ok then
      error('expected function to fail', 2)
    elseif expected ~= nil then
      local found = expected == err
      if not found and type(expected) == 'string' then
        found = string.find(tostring(err), expected, 1, true)
      end
      if not found then
        error('expected function to fail\nexpected:\n'..tostring(expected)..'\ngot:\n'..tostring(err), 2)
      end
    end
  end
  
  --- Check if a function does not fail with a error.
  function expect.not_fail(func)
    local ok, err = pcall(func)
    if not ok then
      error('expected function to not fail\ngot error:\n'..tostring(err), 2)
    end
  end
  
  --- Check if a value is not `nil`.
  function expect.exist(v)
    if v == nil then
      error('expected value to exist\ngot:\n'..tostring(v), 2)
    end
  end
  
  --- Check if a value is `nil`.
  function expect.not_exist(v)
    if v ~= nil then
      error('expected value to not exist\ngot:\n'..tostring(v), 2)
    end
  end
  
  --- Check if an expression is evaluates to `true`.
  function expect.truthy(v)
    if not v then
      error('expected expression to be true\ngot:\n'..tostring(v), 2)
    end
  end
  
  --- Check if an expression is evaluates to `false`.
  function expect.falsy(v)
    if v then
      error('expected expression to be false\ngot:\n'..tostring(v), 2)
    end
  end
  
  --- Compare if two values are equal, considering nested tables.
  local function strict_eq(t1, t2)
    if rawequal(t1, t2) then return true end
    if type(t1) ~= type(t2) then return false end
    if type(t1) ~= 'table' then return t1 == t2 end
    if getmetatable(t1) ~= getmetatable(t2) then return false end
    for k,v1 in pairs(t1) do
      if not strict_eq(v1, t2[k]) then return false end
    end
    for k,v2 in pairs(t2) do
      if not strict_eq(v2, t1[k]) then return false end
    end
    return true
  end
  
  --- Check if two values are equal.
  function expect.equal(v1, v2)
    if not strict_eq(v1, v2) then
      error('expected values to be equal\nfirst value:\n'..tostring(v1)..'\nsecond value:\n'..tostring(v2), 2)
    end
  end
  
  --- Check if two values are not equal.
  function expect.not_equal(v1, v2)
    if strict_eq(v1, v2) then
      error('expected values to be not equal\nfirst value:\n'..tostring(v1)..'\nsecond value:\n'..tostring(v2), 2)
    end
  end
  
  return lester
  
  --[[
  The MIT License (MIT)
  
  Copyright (c) 2021 Eduardo Bart (https://github.com/edubart)
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
  
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
  ]]