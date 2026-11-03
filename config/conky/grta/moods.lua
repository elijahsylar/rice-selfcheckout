-- GRTA mood schedule: which face is shown at which hour (local time).
-- Edit freely. Ranges are [from, to) in 24-hour time; a range whose `to`
-- is smaller than its `from` wraps past midnight. The first match wins.
--
-- Available faces (defined in face.lua):
--   waking, alert, lunch, focused, wind_down, evening, night, deep_night
return {
    { from = 6,  to = 12, face = "alert"   },  -- morning
    { from = 12, to = 18, face = "focused" },  -- afternoon
    { from = 18, to = 22, face = "evening" },  -- evening
    { from = 22, to = 6,  face = "night"   },  -- night
}
