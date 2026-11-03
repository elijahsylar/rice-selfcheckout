-- Run from the repo root: lua tests/test_moods.lua
package.preload["cairo"] = function() return {} end
local face = dofile("config/conky/grta/face.lua")
local sched = dofile("config/conky/grta/moods.lua")
local failed = 0
local function check(cond, msg)
  if not cond then failed = failed + 1; print("FAIL " .. msg) else print("ok   " .. msg) end
end

local want = { [6] = "alert", [11] = "alert", [12] = "focused", [17] = "focused",
               [18] = "evening", [21] = "evening", [22] = "night", [23] = "night", [0] = "night", [5] = "night" }
for h, m in pairs(want) do check(face.mood_for_hour(h) == m, ("hour %02d -> %s"):format(h, m)) end

for h = 0, 23 do check(face.GRIDS[face.mood_for_hour(h)] ~= nil, ("hour %02d maps to a defined face"):format(h)) end
for _, r in ipairs(sched) do check(face.GRIDS[r.face] ~= nil, "schedule face '" .. r.face .. "' exists") end

check(face.in_range(23, 22, 6) and face.in_range(3, 22, 6) and not face.in_range(12, 22, 6), "ranges wrap past midnight")
check(face.in_range(6, 6, 12) and not face.in_range(12, 6, 12), "ranges are [from, to)")

for name, grid in pairs(face.GRIDS) do
  local ok = #grid == 12
  for _, row in ipairs(grid) do ok = ok and #row == 16 end
  check(ok, "face '" .. name .. "' is 16x12")
end

if failed > 0 then print(failed .. " failed"); os.exit(1) end
print("all passed")
