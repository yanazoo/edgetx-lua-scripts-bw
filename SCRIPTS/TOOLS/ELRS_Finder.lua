-- ELRS_Finder.lua  (EdgeTX – Boxer B/W + TX15 MAX colour)
-- ELRS/CRSF RSSI-based lost-model finder (Geiger style) + 8-direction compass
--
-- Usage:
--   Rotate encoder  → select the direction you are currently facing (N/NE/E…)
--   Signal is auto-recorded per direction (peak-hold)
--   Compass rose shows which direction had the strongest signal (= model location)
--   ENT             → reset all direction scan data and start over

-- ── Screen detection ──────────────────────────────────────────────────
local W        = LCD_W or 128
local H        = LCD_H or 64
local IS_LARGE = (W >= 320)          -- TX15 MAX = 480 ; Boxer = 128
local PI       = math.pi or 3.14159265

-- ── Signal state ──────────────────────────────────────────────────────
local lastBeep = 0
local avg      = -120
local have     = { rssi=false, snr=false, rql=false }

local function readSignal()
  local rssi = getValue("1RSS")          -- CRSF dBm, typically -95..-40
  if rssi and rssi ~= 0 then have.rssi=true; return rssi, "dBm" end
  local snr  = getValue("RSNR")          -- SNR dB, -20..+20
  if snr  and snr  ~= 0 then have.snr=true;  return (snr*2-120), "SNR" end
  local rql  = getValue("RQly")          -- Link quality 0..100 %
  if rql  and rql  ~= 0 then have.rql=true;  return (rql-120),   "LQ"  end
  return -120, "NA"
end

local function clamp(x, a, b)
  if x < a then return a elseif x > b then return b else return x end
end

-- ── Direction tracking ────────────────────────────────────────────────
local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
-- ASCII direction arrows (unicode not reliable on all EdgeTX builds)
local DIR_ARR = { "^", "^>", ">", "v>", "v", "<v", "<", "<^" }

local dir_strengths = { -1, -1, -1, -1, -1, -1, -1, -1 }  -- peak 0-100 per dir; -1 = not yet scanned
local cur_dir = 1  -- 1=N, 2=NE … 8=NW, clockwise

-- Navigation arrow: how to turn from cur_dir to face best_dir
-- diff=0 → "^" (already facing it), diff=1 → "^>" (turn right 45°), etc.
local function navArrow(cur, best)
  local diff = (best - cur + 8) % 8
  return DIR_ARR[diff + 1]
end

-- ── Event aliases (covers multiple EdgeTX builds) ─────────────────────
local EVT_NEXT  = EVT_VIRTUAL_NEXT or 0x0305
local EVT_PREV  = EVT_VIRTUAL_PREV or 0x0304
local EVT_ENT   = EVT_ENTER_BREAK  or 0x0059
local EVT_ROT_R = (rawget(_G, "EVT_ROT_RIGHT") and EVT_ROT_RIGHT) or 0x0101
local EVT_ROT_L = (rawget(_G, "EVT_ROT_LEFT")  and EVT_ROT_LEFT)  or 0x0100

-- ── Line-style constants (safe fallback) ──────────────────────────────
local SOLID  = rawget(_G, "SOLID")  or 0
local DOTTED = rawget(_G, "DOTTED") or 1
local BOLD_F = rawget(_G, "BOLD")   or 0

-- ── Compass geometry (TX15 MAX right panel) ───────────────────────────
-- Right panel starts at x=240 on 480-wide screen → centre ≈ (360, 135)
local CX      = 360   -- compass centre x
local CY      = 135   -- compass centre y
local R_SPOKE = 54    -- octagon / spoke radius (px)
local R_LABEL = 76    -- direction label radius (px, outside octagon)

-- Compute compass-point screen position
local function cpt(r, i)
  local a = (i - 1) * PI / 4   -- 0=N, clockwise
  return CX + math.floor(r * math.sin(a)),
         CY - math.floor(r * math.cos(a))
end

-- ── Draw compass rose (TX15 MAX only) ────────────────────────────────
local function drawCompass(best_dir, has_best)

  -- Octagon outline (connects the 8 compass points)
  for i = 1, 8 do
    local j  = (i % 8) + 1
    local x1, y1 = cpt(R_SPOKE, i)
    local x2, y2 = cpt(R_SPOKE, j)
    lcd.drawLine(x1, y1, x2, y2, SOLID, 0)
  end

  -- Signal-strength spokes (proportional length = recorded peak)
  for i = 1, 8 do
    if dir_strengths[i] >= 0 then
      local len = math.max(3, math.floor(dir_strengths[i] * R_SPOKE / 100))
      local ex, ey = cpt(len, i)
      lcd.drawLine(CX, CY, ex, ey, SOLID, 0)
      -- Thicker spoke for the strongest direction
      if i == best_dir and has_best then
        local ex1, ey1 = cpt(len, i)
        lcd.drawLine(CX + 1, CY,     ex1 + 1, ey1,     SOLID, 0)
        lcd.drawLine(CX,     CY + 1, ex1,     ey1 + 1, SOLID, 0)
      end
    end
  end

  -- Current facing direction: dotted line to octagon edge
  local dcx, dcy = cpt(R_SPOKE, cur_dir)
  lcd.drawLine(CX, CY, dcx, dcy, DOTTED, 0)

  -- Centre dot
  lcd.drawFilledRectangle(CX - 3, CY - 3, 7, 7, 0)

  -- Direction labels (text outside octagon)
  for i = 1, 8 do
    local lx, ly = cpt(R_LABEL, i)
    lx = lx - 6   -- centre 2-char label on point
    ly = ly - 4
    local flags = 0
    if i == cur_dir                         then flags = INVERS
    elseif i == best_dir and has_best       then flags = BOLD_F
    end
    lcd.drawText(lx, ly, DIRS[i], flags)
  end

  -- Summary below compass
  lcd.drawText(CX - 34, H - 30, "Scan:" .. DIRS[cur_dir], 0)
  if has_best then
    lcd.drawText(CX - 34, H - 18, "Best:" .. DIRS[best_dir], 0)
  end
end

-- ── Main run loop ─────────────────────────────────────────────────────
local function run_func(event)
  local now = getTime()   -- 10 ms ticks

  -- Rotate encoder → change current facing direction
  if event == EVT_ROT_R or event == EVT_NEXT then
    cur_dir = (cur_dir % 8) + 1
  elseif event == EVT_ROT_L or event == EVT_PREV then
    cur_dir = ((cur_dir - 2) % 8) + 1
  elseif event == EVT_ENT then
    -- Reset all recorded direction data
    for i = 1, 8 do dir_strengths[i] = -1 end
  end

  -- Signal processing
  local raw, kind = readSignal()
  avg = 0.8 * avg + 0.2 * raw   -- exponential moving average
  local strength = clamp((avg + 110) * (100 / 70), 0, 100)   -- -110→0, -40→100

  -- Peak-hold: record best signal seen for current facing direction
  if strength > dir_strengths[cur_dir] then
    dir_strengths[cur_dir] = strength
  end

  -- Determine direction with strongest recorded signal
  local best_dir, has_best = 1, false
  for i = 1, 8 do
    if dir_strengths[i] >= 0 then
      has_best = true
      if dir_strengths[i] > dir_strengths[best_dir] then best_dir = i end
    end
  end

  -- Geiger-counter beep (stronger signal → shorter interval, higher pitch)
  local period = clamp(120 - strength, 10, 120)
  if now - lastBeep >= period then
    playTone(600 + strength * 6, 30, 0, 0)
    lastBeep = now
  end

  -- ── Draw UI ──────────────────────────────────────────────────────────
  lcd.clear()

  if IS_LARGE then
    -----------------------------------------------------------------------
    -- TX15 MAX  480×272  colour layout
    -- Left panel (x 0-238): signal info + direction text
    -- Right panel (x 239-480): compass rose
    -----------------------------------------------------------------------

    -- Title
    lcd.drawText(6, 6, "ELRS Finder", MIDSIZE)

    -- Source + raw reading
    lcd.drawText(6, 30, string.format("Src:%-3s  Raw:%.1f dBm", kind, raw), 0)

    -- Strength bar
    lcd.drawRectangle(6, 50, 214, 16)
    local bar_px = math.floor(strength * 210 / 100)
    lcd.drawFilledRectangle(7, 51, bar_px, 14, 0)
    lcd.drawText(224, 52, string.format("%d%%", math.floor(strength)), 0)

    -- Averaged dBm
    lcd.drawText(6, 74, string.format("Avg: %.1f dBm", avg), 0)

    -- Current scan direction
    lcd.drawText(6, 98, "Scan dir:", 0)
    lcd.drawText(72, 98, DIRS[cur_dir], INVERS)

    -- Best direction + navigation arrow (how to turn to face best signal)
    lcd.drawText(6, 118, "Best dir:", 0)
    if has_best then
      lcd.drawText(72, 118, DIRS[best_dir], 0)
      lcd.drawText(92, 118, navArrow(cur_dir, best_dir), 0)
    else
      lcd.drawText(72, 118, "---", 0)
    end

    -- Operation hints
    lcd.drawText(6, 150, "Rotate: change dir", 0)
    lcd.drawText(6, 164, "ENT: reset scan", 0)
    lcd.drawText(6, 184, "Tip: turn TX body to", 0)
    lcd.drawText(6, 198, "face each direction", 0)

    -- Panel divider
    lcd.drawLine(238, 0, 238, H - 1, SOLID, 0)

    -- Compass rose
    drawCompass(best_dir, has_best)

  else
    -----------------------------------------------------------------------
    -- Boxer  128×64  B/W layout (original positions preserved)
    -- Direction info replaces the tip-text line at y=54
    -----------------------------------------------------------------------

    lcd.drawText(2,  2,  "ELRS Finder", MIDSIZE)
    lcd.drawText(2,  18, string.format("Src:%s", kind), 0)
    lcd.drawText(60, 18, string.format("Raw:%.1f", raw), 0)
    lcd.drawText(2,  30, "Strength:", 0)
    lcd.drawRectangle(58, 30, 66, 10)
    local bar_bw = math.floor(strength * 64 / 100)
    lcd.drawFilledRectangle(59, 31, bar_bw, 8, 0)
    lcd.drawText(2, 44, string.format("Avg:%.1f dBm", avg), 0)

    -- Direction info (compact, fits 128 px wide)
    lcd.drawText(2,  54, "Sc:", 0)
    lcd.drawText(22, 54, DIRS[cur_dir], INVERS)
    lcd.drawText(40, 54, "Bst:", 0)
    lcd.drawText(66, 54, has_best and DIRS[best_dir] or "--", 0)
    if has_best then
      lcd.drawText(82, 54, navArrow(cur_dir, best_dir), 0)
    end
  end

  return 0
end

return { run = run_func }
