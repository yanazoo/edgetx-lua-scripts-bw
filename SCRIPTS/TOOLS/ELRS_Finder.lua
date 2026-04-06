-- ELRS_Finder.lua  (EdgeTX – Boxer B/W + TX15 MAX)
-- ELRS/CRSF lost-model finder  ·  Geiger beep  +  auto signal trend arrow
--
-- Trend arrow (fully automatic):
--   ↑  = signal rising   → heading CLOSER to model
--   ↓  = signal dropping → heading FARTHER from model
--   ≡  = stable / uncertain
--
-- ENT: reset peak and trend history

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
-- fast_ema (α=0.50): reacts in ~2 frames  – tracks rapid changes
-- slow_ema (α=0.08): reacts in ~12 frames – tracks baseline
-- trend = sign(fast_ema - slow_ema)
local fast_ema  = nil
local slow_ema  = nil
local peak_str  = 0     -- all-time peak strength 0-100 %
local TREND_THR = 2     -- % points gap needed to declare a trend (sensitive)

-- ── Event alias ───────────────────────────────────────────────────────
local EVT_ENT = EVT_ENTER_BREAK or 0x0059

-- ── Large trend arrow (TX15 MAX, built from drawFilledRectangle) ──────
-- Shape: clean ↑ / ↓  (3-step arrowhead + thin shaft)
-- cx = centre x, y_top = top of arrow, direction: 1=up, -1=down, 0=stable
local function drawTrendArrow(cx, y_top, direction)
  -- Arrowhead row widths: narrowest first (tip) → widest (base)
  local HEAD = { 12, 30, 48 }
  local RH   = 13    -- row height
  local SW   = 10    -- shaft width
  local SH   = 80    -- shaft height

  if direction == 1 then
    -- ↑ UP: tip at top, shaft below
    for k, w in ipairs(HEAD) do
      lcd.drawFilledRectangle(cx - w // 2, y_top + (k-1)*RH, w, RH-1, 0)
    end
    lcd.drawFilledRectangle(cx - SW//2, y_top + #HEAD*RH, SW, SH, 0)

  elseif direction == -1 then
    -- ↓ DOWN: shaft at top, tip at bottom
    lcd.drawFilledRectangle(cx - SW//2, y_top, SW, SH, 0)
    -- Head rows reversed: widest closest to shaft, narrowest at tip
    for k = #HEAD, 1, -1 do
      local yo = SH + (#HEAD - k) * RH
      lcd.drawFilledRectangle(cx - HEAD[k]//2, y_top + yo, HEAD[k], RH-1, 0)
    end

  else
    -- ≡ STABLE: three horizontal bars
    lcd.drawFilledRectangle(cx - 40, y_top + 20, 80, 12, 0)
    lcd.drawFilledRectangle(cx - 40, y_top + 50, 80, 12, 0)
    lcd.drawFilledRectangle(cx - 40, y_top + 80, 80, 12, 0)
  end
end

-- ── Main run loop ─────────────────────────────────────────────────────
local function run_func(event)
  local now = getTime()   -- 10 ms ticks

  -- ENT → reset peak and trend history
  if event == EVT_ENT then
    avg = nil; fast_ema = nil; slow_ema = nil; peak_str = 0
  end

  -- Signal acquisition
  local raw, kind = readSignal()
  local strength = 0
  if raw then
    if avg      == nil then avg      = raw end
    avg = 0.8 * avg + 0.2 * raw
    local str = clamp((avg + 110) * (100 / 70), 0, 100)   -- -110→0, -40→100
    if fast_ema == nil then fast_ema = str end
    if slow_ema == nil then slow_ema = str end
    fast_ema = 0.50 * fast_ema + 0.50 * str   -- fast: α=0.50
    slow_ema = 0.92 * slow_ema + 0.08 * str   -- slow: α=0.08
    strength = str
    if str > peak_str then peak_str = str end
  end

  -- Trend: only valid with live telemetry
  local trend = 0
  if raw and fast_ema and slow_ema and slow_ema > 0 then
    if fast_ema > slow_ema + TREND_THR then trend =  1
    elseif fast_ema < slow_ema - TREND_THR then trend = -1
    end
  end

  -- Geiger-counter beep
  local period = clamp(120 - strength, 10, 120)
  if now - lastBeep >= period then
    playTone(600 + strength * 6, 30, 0, 0)
    lastBeep = now
  end

  -- ── Draw UI ──────────────────────────────────────────────────────────
  lcd.clear()

  if IS_LARGE then
    --------------------------------------------------------------------------
    -- TX15 MAX  480×272
    -- Left panel  (x   0-236) : signal data
    -- Right panel (x 240-480) : trend arrow + comparison bars
    --------------------------------------------------------------------------

    -- ── Left panel ──────────────────────────────────────────────────────
    lcd.drawText(6, 6, "ELRS Finder", MIDSIZE)

    lcd.drawText(6, 30, raw
      and string.format("Src:%-3s  Raw:%.1f dBm", kind, raw)
      or  "Src:NA  (waiting...)", 0)

    -- Strength bar (x=6, w=200, then % at x=210)
    lcd.drawRectangle(6, 50, 200, 16)
    lcd.drawFilledRectangle(7, 51, math.floor(strength * 196 / 100), 14, 0)
    lcd.drawText(210, 52, string.format("%d%%", math.floor(strength)), 0)

    lcd.drawText(6, 74, avg
      and string.format("Avg: %.1f dBm", avg)
      or  "Avg: ---", 0)

    -- Peak and gap (on separate lines to avoid crowding)
    lcd.drawText(6, 94, string.format("Peak: %d%%", math.floor(peak_str)), 0)
    if raw and peak_str > 0 then
      lcd.drawText(6, 110, string.format("Gap: %+d%%",
        math.floor(strength - peak_str)), 0)
    end

    -- Trend text
    local tlbl = trend ==  1 and "^ CLOSER"
              or trend == -1 and "v FARTHER"
              or                 "= STABLE"
    lcd.drawText(6, 130, "Trend: " .. tlbl, 0)

    -- Hints
    lcd.drawText(6, 160, "ENT: reset peak", 0)
    lcd.drawText(6, 178, "Walk & watch arrow", 0)
    lcd.drawText(6, 196, "^=closer  v=farther", 0)

    -- Panel divider
    lcd.drawFilledRectangle(237, 0, 3, H, 0)

    -- ── Right panel ─────────────────────────────────────────────────────
    local CX = 360

    -- Header
    lcd.drawText(CX - 28, 6, "TREND", MIDSIZE)

    -- Large arrow  (y 35 → ~154)
    drawTrendArrow(CX, 35, trend)

    -- Direction label below arrow (y=163)
    if trend == 1 then
      lcd.drawText(CX - 36, 163, "CLOSER",  MIDSIZE)
    elseif trend == -1 then
      lcd.drawText(CX - 42, 163, "FARTHER", MIDSIZE)
    else
      lcd.drawText(CX - 36, 163, "STABLE",  MIDSIZE)
    end

    -- ── Comparison bars ─────────────────────────────────────────────────
    -- Layout (no overlap):
    --   y=188: "Peak: XX%" label
    --   y=200: Peak bar (h=13)  → ends y=213
    --   y=219: "Now:  XX%" label
    --   y=231: Now bar  (h=13)  → ends y=244
    local BX = CX - 65   -- x=295, right panel (>240)
    local BW = 130        -- bar width; right edge x=425 (<480)

    lcd.drawText(BX, 188,
      string.format("Peak: %d%%", math.floor(peak_str)), 0)
    lcd.drawRectangle(BX, 200, BW, 13)
    lcd.drawFilledRectangle(BX+1, 201,
      math.floor(peak_str * (BW-2) / 100), 11, 0)

    lcd.drawText(BX, 219,
      string.format("Now:  %d%%", math.floor(strength)), 0)
    lcd.drawRectangle(BX, 231, BW, 13)
    lcd.drawFilledRectangle(BX+1, 232,
      math.floor(strength * (BW-2) / 100), 11, 0)

  else
    --------------------------------------------------------------------------
    -- Boxer  128×64  (original layout; trend replaces tip-text line)
    --------------------------------------------------------------------------
    lcd.drawText(2,  2,  "ELRS Finder", MIDSIZE)
    lcd.drawText(2,  18, string.format("Src:%s", kind), 0)
    lcd.drawText(60, 18, raw  and string.format("Raw:%.1f", raw) or "---", 0)
    lcd.drawText(2,  30, "Strength:", 0)
    lcd.drawRectangle(58, 30, 66, 10)
    lcd.drawFilledRectangle(59, 31, math.floor(strength * 64 / 100), 8, 0)
    lcd.drawText(2,  44, avg
      and string.format("Avg:%.1f dBm", avg)
      or  "Avg:--- dBm", 0)
    -- Trend on last line
    local t_sym = trend ==  1 and "^" or (trend == -1 and "v" or "=")
    local t_lbl = trend ==  1 and "Closer"  or
                  trend == -1 and "Farther" or "Stable"
    lcd.drawText(2,  54, t_sym, INVERS)
    lcd.drawText(16, 54, t_lbl, 0)
  end

  return 0
end

return { run = run_func }
