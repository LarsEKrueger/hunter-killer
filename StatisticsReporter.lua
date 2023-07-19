--[[
StatisticsReporter.lua -- Track and report statistics

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

local StatisticsReporterMt

local StatisticsReporter = {}

local kStatLength = 8

local kSparks = {
  '▁',
  '▂',
  '▃',
  '▄',
  '▅',
  '▆',
  '▇',
  '█'
}

function StatisticsReporter.new( message, always_report)
  local self = setmetatable( {
    _message = message,
    _always_report = always_report,
    _values = {},
    set = StatisticsReporter.set,
    report = StatisticsReporter.report,
  }, StatisticsReporterMt)
  return self
end

local function sparkline( data)
  local txt = ''
  local minData
  local maxData
  if #data > 0 then
    minData = data[1]
    maxData = data[1]
  else
    minData = 0
    maxData = 0
  end
  for i,v in pairs(data) do
    maxData = math.max(maxData,v)
    minData = math.min(minData,v)
  end
  if maxData > minData then
    for i,v in pairs(data) do
      local scaled = math.floor((v-minData)*(#kSparks - 1) / (maxData - minData))
      txt = txt .. kSparks[ 1 + scaled]
    end
  else
    for i,v in pairs(data) do
      txt = txt .. '╌'
    end
  end
  return txt
end

function StatisticsReporter:set( value)
  -- Update values
  local prevValue = self._values[#self._values] or 0
  if value ~= prevValue then
    self._values[#self._values + 1] = value
    if #self._values > kStatLength then
      table.remove( self._values,1)
    end
    if (value > prevValue) or (self._always_report) then
      self:report()
    end
  end
end

function StatisticsReporter:report()
  -- Report value if required
  if #self._values > 0 then
    local firstValue = self._values[1]
    local lastValue = self._values[#self._values]
    game.print( self._message .. firstValue .. ' ' .. sparkline(self._values) .. ' ' .. lastValue)
  else
    game.print( self._message .. 'No data')
  end
end

StatisticsReporterMt = {
  __index = StatisticsReporter,
}
StatisticsReporter.metatable = StatisticsReporterMt

return StatisticsReporter
