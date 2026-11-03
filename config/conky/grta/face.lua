-- SelfCheckout rice — GRTA face companion (FULLSCREEN)
-- Pixelated face inspired by the GRTA AI in the series Maniac.
-- Rendered fullscreen-centered on eDP. Palette: phosphor green on black.
-- Called once per conky frame (update_interval 1s) via lua_draw_hook_post.

require 'cairo'

-- Per-monitor geometry. Each face is drawn centered on its monitor.
local MONITOR_W = 1920
local MONITOR_H = 1080

-- Big-pixel size in real pixels. 45 → face ≈ 720×540 (~40% of monitor area).
local BIGPX  = 45
local GRID_W = 16
local GRID_H = 12
local FACE_W = GRID_W * BIGPX
local FACE_H = GRID_H * BIGPX

-- Monitor origins in the 3840×1080 conky canvas.
-- Each entry = top-left pixel of the FACE (not the monitor) for centering.
local FACE_ORIGINS = {
    { x = math.floor((MONITOR_W - FACE_W) / 2),                 y = math.floor((MONITOR_H - FACE_H) / 2) }, -- eDP  (0..1920)
    { x = MONITOR_W + math.floor((MONITOR_W - FACE_W) / 2),     y = math.floor((MONITOR_H - FACE_H) / 2) }, -- HDMI (1920..3840)
}

-- Glow halo radius (proportional to big-pixel size).
local GLOW = math.floor(BIGPX / 4)

-- Palette (rgba, 0..1).
local C_PHOSPHOR = {0/255,   255/255,  65/255, 1.0}
local C_GREEN_DK = {0/255,   204/255,  51/255, 1.0}
local C_AMBER    = {255/255, 170/255,   0/255, 1.0}
local C_DIM      = {74/255,  122/255,  90/255, 1.0}

-- Face grids — 12 rows of 16-char strings.
-- '#' = filled big-pixel   '.' = empty   'e' = eye cell (blink-able, pupil-punch-able)
local GRIDS = {
    waking = {
        "................",
        "................",
        "................",
        "..###......###..",
        "................",
        "................",
        "................",
        "................",
        "................",
        "......####......",
        "................",
        "................",
    },
    alert = {
        "..eee......eee..",
        "..eee......eee..",
        "..eee......eee..",
        "................",
        "................",
        "................",
        "................",
        "................",
        ".##..........##.",
        "...##......##...",
        ".....######.....",
        "................",
    },
    lunch = {
        "..eee......eee..",
        "..eee......eee..",
        "..eee......eee..",
        "................",
        "................",
        "................",
        "................",
        "................",
        ".##..........##.",
        "..##........##..",
        "....########....",
        "......####......",
    },
    focused = {
        "................",
        "................",
        "................",
        ".#####....#####.",
        ".#####....#####.",
        "................",
        "................",
        "................",
        "................",
        ".....######.....",
        "................",
        "................",
    },
    wind_down = {
        "................",
        "...##......##...",
        "..####....####..",
        "...##......##...",
        "................",
        "................",
        "................",
        "................",
        "..##........##..",
        "...##......##...",
        "....########....",
        "................",
    },
    evening = {
        "..eee......eee..",
        "..eee......eee..",
        "..eee......eee..",
        "................",
        "................",
        "................",
        "................",
        "................",
        ".##..........##.",
        "...##......##...",
        ".....######.....",
        "................",
    },
    night = {
        "................",
        "................",
        "................",
        "..###......###..",
        "..###......###..",
        "................",
        "................",
        "................",
        "................",
        "........#####...",
        "......##........",
        "................",
    },
    deep_night = {
        "................",
        "................",
        "................",
        "................",
        "..###......###..",
        "................",
        "................",
        "................",
        "................",
        "................",
        "......####......",
        "................",
    },
}

local MOODS_WITH_PUPILS = { alert = true, lunch = true, evening = true }
local PUPIL_LEFT  = { x = 3,  y = 1 }
local PUPIL_RIGHT = { x = 12, y = 1 }

-- ---- animation state (persistent across calls) ----
local state = {
    frame          = 0,
    blink_end      = 0,
    blink_next     = 6,
    drift_end      = 0,
    drift_next     = 12,
    drift_x        = 0,
    drift_y        = 0,
    z_positions    = { {14, 2}, {13, 3}, {12, 4} },
    reduced_motion = nil,
    last_rm_check  = 0,
}

math.randomseed(os.time())

-- Mood schedule lives in moods.lua next to this file (user-editable).
-- Defaults below are used if it is missing or invalid.
local DEFAULT_SCHEDULE = {
    { from = 6,  to = 12, face = "alert"   },
    { from = 12, to = 18, face = "focused" },
    { from = 18, to = 22, face = "evening" },
    { from = 22, to = 6,  face = "night"   },
}

local function load_schedule()
    local src = debug.getinfo(1, "S").source
    local dir = src:match("^@(.*[/\\])") or "./"
    local ok, sched = pcall(dofile, dir .. "moods.lua")
    if ok and type(sched) == "table" and #sched > 0 then return sched end
    return DEFAULT_SCHEDULE
end

local SCHEDULE = load_schedule()

local function in_range(h, from, to)
    if from <= to then return h >= from and h < to end
    return h >= from or h < to   -- wraps past midnight
end

local function mood_for_hour(h)
    for _, r in ipairs(SCHEDULE) do
        if in_range(h, r.from, r.to) and GRIDS[r.face] then return r.face end
    end
    return "night"
end

local function color_for_mood(mood)
    if mood == "waking"     then return C_AMBER    end
    if mood == "evening"    then return C_GREEN_DK end
    if mood == "night"      then return C_DIM      end
    if mood == "deep_night" then return C_AMBER    end
    return C_PHOSPHOR
end

local function check_reduced_motion()
    local now = os.time()
    if state.reduced_motion ~= nil and (now - state.last_rm_check) < 30 then
        return state.reduced_motion
    end
    local h = io.popen("gsettings get org.gnome.desktop.interface enable-animations 2>/dev/null")
    local rm = false
    if h then
        local v = h:read("*a") or ""
        h:close()
        rm = (v:find("false") ~= nil)
    end
    state.reduced_motion = rm
    state.last_rm_check = now
    return rm
end

local function is_blinking()
    return state.frame < state.blink_end
end

local function update_animation(mood, rm)
    state.frame = state.frame + 1

    local closed = { deep_night = true, waking = true, night = true }
    if not rm and not closed[mood] then
        if state.frame >= state.blink_end and state.frame >= state.blink_next then
            state.blink_end  = state.frame + 1
            state.blink_next = state.frame + 1 + math.random(4, 8)
        end
    end

    if rm or not MOODS_WITH_PUPILS[mood] then
        state.drift_x = 0
        state.drift_y = 0
    else
        if state.frame < state.drift_end then
            -- holding drift offset
        elseif state.frame >= state.drift_next then
            local dirs = { {-1, 0}, {1, 0}, {0, -1} }
            local d = dirs[math.random(1, 3)]
            state.drift_x   = d[1]
            state.drift_y   = d[2]
            state.drift_end = state.frame + 1
            state.drift_next = state.frame + 1 + math.random(10, 15)
        else
            state.drift_x = 0
            state.drift_y = 0
        end
    end

    if mood == "deep_night" and not rm then
        local new_zs = {}
        for _, p in ipairs(state.z_positions) do
            local nx = p[1] - 1
            local ny = p[2] - 1
            if nx >= 2 and ny >= 0 then
                table.insert(new_zs, { nx, ny })
            end
        end
        while #new_zs < 3 do
            table.insert(new_zs, 1, { 14, 2 })
        end
        state.z_positions = new_zs
    end
end

local function draw_big_pixel(cr, x, y, ox, oy, color, glow)
    local rx = x * BIGPX + ox
    local ry = y * BIGPX + oy
    if glow then
        cairo_set_source_rgba(cr, color[1], color[2], color[3], 0.28)
        cairo_rectangle(cr, rx - GLOW, ry - GLOW, BIGPX + GLOW * 2, BIGPX + GLOW * 2)
        cairo_fill(cr)
    end
    cairo_set_source_rgba(cr, color[1], color[2], color[3], color[4])
    cairo_rectangle(cr, rx, ry, BIGPX, BIGPX)
    cairo_fill(cr)
end

local function draw_z(cr, x, y, ox, oy, color)
    -- 3x3 Z pattern inside a big-pixel cell.
    local rx = x * BIGPX + ox
    local ry = y * BIGPX + oy
    local px = BIGPX / 3
    cairo_set_source_rgba(cr, color[1], color[2], color[3], color[4])
    cairo_rectangle(cr, rx, ry, BIGPX, px)
    cairo_fill(cr)
    cairo_rectangle(cr, rx + px, ry + px, px, px)
    cairo_fill(cr)
    cairo_rectangle(cr, rx, ry + BIGPX - px, BIGPX, px)
    cairo_fill(cr)
end

-- Draw one complete face centered at (ox, oy) top-left of the face bounding box.
local function draw_one_face(cr, ox, oy, grid, color, blinking, mood, rm)
    for y = 0, GRID_H - 1 do
        local row = grid[y + 1]
        if row then
            for x = 0, GRID_W - 1 do
                local ch = row:sub(x + 1, x + 1)
                if ch == '#' then
                    draw_big_pixel(cr, x, y, ox, oy, color, true)
                elseif ch == 'e' then
                    if blinking then
                        if y == 1 then
                            draw_big_pixel(cr, x, y, ox, oy, color, false)
                        end
                    else
                        draw_big_pixel(cr, x, y, ox, oy, color, true)
                    end
                end
            end
        end
    end

    if MOODS_WITH_PUPILS[mood] and not blinking then
        local plx = PUPIL_LEFT.x  + state.drift_x
        local ply = PUPIL_LEFT.y  + state.drift_y
        local prx = PUPIL_RIGHT.x + state.drift_x
        local pry = PUPIL_RIGHT.y + state.drift_y
        cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
        cairo_rectangle(cr, plx * BIGPX + ox, ply * BIGPX + oy, BIGPX, BIGPX)
        cairo_fill(cr)
        cairo_rectangle(cr, prx * BIGPX + ox, pry * BIGPX + oy, BIGPX, BIGPX)
        cairo_fill(cr)
        cairo_set_operator(cr, CAIRO_OPERATOR_OVER)
    end

    if mood == "deep_night" and not rm then
        for _, p in ipairs(state.z_positions) do
            if p[1] >= 0 and p[1] < GRID_W and p[2] >= 0 and p[2] < GRID_H then
                draw_z(cr, p[1], p[2], ox, oy, color)
            end
        end
    end
end

function conky_draw_grta()
    if conky_window == nil then return "" end
    local cs = cairo_xlib_surface_create(
        conky_window.display, conky_window.drawable,
        conky_window.visual,
        conky_window.text_width, conky_window.text_height)
    local cr = cairo_create(cs)

    local h = tonumber(os.date("%H"))
    local mood = mood_for_hour(h)
    local rm = check_reduced_motion()
    update_animation(mood, rm)

    local color = color_for_mood(mood)
    local grid = GRIDS[mood]
    local blinking = is_blinking()

    for _, origin in ipairs(FACE_ORIGINS) do
        draw_one_face(cr, origin.x, origin.y, grid, color, blinking, mood, rm)
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
    return ""
end

-- For tests (conky ignores the return value of a lua_load script).
return { mood_for_hour = mood_for_hour, in_range = in_range, GRIDS = GRIDS }
