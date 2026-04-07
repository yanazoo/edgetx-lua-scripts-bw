-- ELRS_Finder.lua  (EdgeTX – Boxer B/W + TX15 MAX)
-- Lost-model finder  ·  Geiger beep  +  signal strength pyramid
--
-- Pyramid (right panel): bars = Now vs Peak gap
--   5 bars = MAX  → at/near peak OR peak>=90% (keep going! / very close)
--   0 bars = none → far below peak (turn around!)
--
-- Reset: ENT key  OR  tap anywhere in right panel (TX15 MAX touch)

-- ── Screen detection ──────────────────────────────────────────────────
local W        = LCD_W or 128
local H        = LCD_H or 64
local IS_LARGE = (W >= 320)   -- TX15 MAX = 480 ; Boxer = 128

-- ── Signal state ──────────────────────────────────────────────────────
local lastBeep = 0
local avg      = nil   -- dBm EMA; nil until first real reading

local function readSignal()
  local rssi = getValue("1RSS")
  if type(rssi) == "number" and rssi ~= 0 then return rssi, "dBm" end
  local snr  = getValue("RSNR")
  if type(snr)  == "number" and snr  ~= 0 then return (snr*2-120), "SNR" end
  local rql  = getValue("RQly")
  if type(rql)  == "number" and rql  ~= 0 then return (rql-120),   "LQ"  end
  return nil, "NA"
end

local function clamp(x, a, b)
  if x < a then return a elseif x > b then return b else return x end
end

-- ── Trend tracking ────────────────────────────────────────────────────
local fast_ema  = nil   -- α=0.50: reacts in ~2 frames
local slow_ema  = nil   -- α=0.08: reacts in ~12 frames
local peak_str  = 0     -- all-time peak strength 0-100 %

-- ── Events ───────────────────────────────────────────────────────────
local EVT_ENT   = EVT_ENTER_BREAK or 0x0059
local EVT_TOUCH = rawget(_G, "EVT_TOUCH_FIRST") or 0

-- ── Pyramid drawing (TX15 MAX) ────────────────────────────────────────
-- bars 0-5: drawn from bottom (widest) upward.  y_bottom = bottom edge.
-- Uses only drawFilledRectangle (no drawLine colour issues on colour LCD)
local function drawPyramid(cx, y_bottom, bars)
  local WIDTHS = { 10, 24, 42, 60, 78 }  -- index 1=bottom(narrow)…5=top(wide) = inverted pyramid
  local RH  = 18   -- row height (px)
  local GAP = 3    -- gap between rows (px)
  for k = 1, bars do
    local w = WIDTHS[k]
    -- Each row stacks upward: k=1 at bottom, k=5 at top
    local y = y_bottom - k * RH - (k - 1) * GAP
    lcd.drawFilledRectangle(cx - w // 2, y, w, RH, 0)
  end
end

-- ── Main run loop ─────────────────────────────────────────────────────
local function run_func(event)
  local now = getTime()

  -- Reset on ENT
  if event == EVT_ENT then
    avg = nil; fast_ema = nil; slow_ema = nil; peak_str = 0
  end

  -- Reset on touch inside pyramid area (CX=360 ±50px wide, y=45-165)
  if IS_LARGE and EVT_TOUCH ~= 0 and event == EVT_TOUCH then
    local ts = rawget(_G, "touchState") and touchState()
    if ts and ts.x >= 310 and ts.x <= 410 and ts.y >= 45 and ts.y <= 165 then
      avg = nil; fast_ema = nil; slow_ema = nil; peak_str = 0
    end
  end

  -- Signal acquisition
  local raw, kind = readSignal()
  local strength = 0
  if raw then
    if avg      == nil then avg      = raw end
    avg = 0.8 * avg + 0.2 * raw
    local str = clamp((avg + 110) * (100 / 70), 0, 100)
    if fast_ema == nil then fast_ema = str end
    if slow_ema == nil then slow_ema = str end
    fast_ema = 0.50 * fast_ema + 0.50 * str
    slow_ema = 0.92 * slow_ema + 0.08 * str
    strength = str
    if str > peak_str then peak_str = str end
  end

  -- Geiger-counter beep
  local period = clamp(120 - strength, 10, 120)
  if now - lastBeep >= period then
    playTone(600 + strength * 6, 30, 0, 0)
    lastBeep = now
  end

  lcd.clear()

  if IS_LARGE then
    --------------------------------------------------------------------------
    -- TX15 MAX  480×272
    -- Left panel  (x   0-236): signal data
    -- Right panel (x 240-480): pyramid + comparison bars
    --------------------------------------------------------------------------

    -- ── Left panel ──────────────────────────────────────────────────────
    lcd.drawText(6, 8, "ELRS Finder", MIDSIZE)

    lcd.drawText(6, 34, raw
      and string.format("Src:%-3s  Raw:%.1f dBm", kind, raw)
      or  "Src:NA  (waiting...)", 0)

    -- Strength: label on own line, bar below (no right-side overlap with divider)
    lcd.drawText(6, 54, string.format("Strength: %d%%", math.floor(strength)), 0)
    lcd.drawRectangle(6, 76, 220, 14)       -- y=76: 6px below text bottom (~70), right edge x=226 ✓
    lcd.drawFilledRectangle(7, 77, math.floor(strength * 218 / 100), 12, 0)

    lcd.drawText(6, 98, avg
      and string.format("Avg: %.1f dBm", avg)
      or  "Avg: ---", 0)

    lcd.drawText(6, 118, string.format("Peak: %d%%", math.floor(peak_str)), 0)
    if raw and peak_str > 0 then
      lcd.drawText(6, 134, string.format("Gap:  %+d%%",
        math.floor(strength - peak_str)), 0)
    end

    lcd.drawText(6, 160, "ENT or tap: reset", 0)
    lcd.drawText(6, 180, "Walk & watch pyramid", 0)
    lcd.drawText(6, 200, "5 bars = max signal", 0)

    -- Panel divider
    lcd.drawFilledRectangle(237, 0, 3, H, 0)

    -- ── Right panel ─────────────────────────────────────────────────────
    local CX = 360

    -- Header: "TREND" centered in right panel (panel center = 360, MIDSIZE ~16px/char × 5 = ~80px)
    lcd.drawText(CX - 40, 8, "TREND", MIDSIZE)

    -- Pyramid: bars 0-5 based on (Now - Peak) gap
    --   gap = 0        → at peak (approaching or just arrived) → 5 bars
    --   gap negative   → below peak (moved away)              → fewer bars
    --   peak >= 90%    → very close to drone                  → 5 bars (MAX)
    -- y_bottom=160; full pyramid (5 bars) spans y=58 to y=159
    local bars = 0
    if raw then
      local gap = strength - peak_str   -- 0 at peak, negative when moved away
      if peak_str >= 90 then
        bars = 5                         -- peak near 100% = drone is very close
      elseif gap >= -5  then bars = 5   -- currently at/near peak → approaching
      elseif gap >= -15 then bars = 4
      elseif gap >= -30 then bars = 3
      elseif gap >= -50 then bars = 2
      elseif gap >= -70 then bars = 1
      else                   bars = 0   -- far below peak → turn around
      end
    end
    drawPyramid(CX, 160, bars)

    -- ── Comparison bars ─────────────────────────────────────────────────
    -- Each section: label line → bar below (separate y, no overlap)
    local BX = CX - 65   -- x=295  (right panel, >240)
    local BW = 130        -- right edge x=425 (<480)
    local BH = 14         -- bar height

    -- Peak: label at y=170, bar at y=188 (gap avoids overlap even with large fonts)
    lcd.drawText(BX, 170,
      string.format("Peak: %d%%", math.floor(peak_str)), 0)
    lcd.drawRectangle(BX, 188, BW, BH)
    lcd.drawFilledRectangle(BX+1, 189,
      math.floor(peak_str * (BW-2) / 100), BH-2, 0)

    -- Now: label at y=208, bar at y=226
    lcd.drawText(BX, 208,
      string.format("Now:  %d%%", math.floor(strength)), 0)
    lcd.drawRectangle(BX, 226, BW, BH)
    lcd.drawFilledRectangle(BX+1, 227,
      math.floor(strength * (BW-2) / 100), BH-2, 0)
    -- Now bar bottom: y=226+14-1=239  (<272) ✓

  else
    --------------------------------------------------------------------------
    -- Boxer  128×64  (original layout; last line = text pyramid indicator)
    --------------------------------------------------------------------------
    lcd.drawText(2,  2,  "ELRS Finder", MIDSIZE)
    lcd.drawText(2,  18, string.format("Src:%s", kind), 0)
    lcd.drawText(60, 18, raw  and string.format("Raw:%.1f", raw)  or "---", 0)
    lcd.drawText(2,  30, "Strength:", 0)
    lcd.drawRectangle(58, 30, 66, 10)
    lcd.drawFilledRectangle(59, 31, math.floor(strength * 64 / 100), 8, 0)
    lcd.drawText(2,  44, avg
      and string.format("Avg:%.1f dBm", avg)
      or  "Avg:--- dBm", 0)
    -- Last line: text pyramid + peak %
    local bars = math.min(5, math.floor(strength / 20))
    local bar_str = "[" .. string.rep("|", bars) .. string.rep(".", 5-bars) .. "]"
    lcd.drawText(2,  54, bar_str, 0)
    lcd.drawText(56, 54, string.format("Pk:%d%%", math.floor(peak_str)), 0)
  end

  return 0
end

return { run = run_func }
