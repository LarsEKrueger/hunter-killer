--[[
reporters.lua -- Set up globals reporter objects

Copyright 2023 Lars Krueger

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the “Software”), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]

local StatisticsReporter = require 'StatisticsReporter'

local reporters = {}

function reporters.ensure_globals()
  -- Create the reporters if they don't exist
  global.report_bases = global.report_bases or StatisticsReporter.new( 'Home bases managed: ', true)
  global.report_killers = global.report_killers or StatisticsReporter.new( 'Killers managed: ', true)
  global.report_targets = global.report_targets or StatisticsReporter.new( 'Enemies of the realm: ', false)
  global.report_places = global.report_places or StatisticsReporter.new( 'Places to visit: ', false)
end

return reporters
