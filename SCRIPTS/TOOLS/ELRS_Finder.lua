-- ELRS_Finder.lua  (EdgeTX – Boxer B/W + TX15 MAX)
-- ELRS/CRSF lost-model finder  ·  Geiger beep  +  auto signal trend arrow
--
-- Trend arrow (auto, no compass needed):
--   ^  = signal rising   → heading CLOSER to model
--   v  = signal dropping → heading FARTHER from model
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
-- fast_ema (α=0.30): reacts in ~3 frames  – tracks recent changes
-- slow_ema (α=0.05): reacts in ~20 frames – tracks baseline
-- trend = sign(fast_ema - slow_ema): positive→closer, negative→farther
local fast_ema  = nil
local slow_ema  = nil
local peak_str  = 0     -- all-time peak strength 0-100 %
local TREND_THR = 3     -- % points gap needed to declare a trend

-- ── Event alias ───────────────────────────────────────────────────────
local EVT_ENT = EVT_ENTER_BREAK or 0x0059

-- ── Large trend arrow (TX15 MAX right panel) ─────────────────────────
-- Built entirely from drawFilledRectangle (avoids drawLine colour issues)
-- cx=centre x, y_top=top y of arrow area, direction: 1=up, -1=down, 0=stable
local function drawTrendArrow(cx, y_top, direction)
  if direction == 1 then
    -- ▲ UP: 5-row pyramid (wide→narrow toward tip at top), then shaft
    local ws = { 78, 60, 42, 24, 10 }
    for k, w in ipairs(ws) do
      lcd.drawFilledRectangle(cx - w // 2, y_top + (k-1)*13, w, 11, 0)
    end
    lcd.drawFilledRectangle(cx - 10, y_top + 65, 20, 55, 0)   -- shaft

  elseif direction == -1 then
    -- ▼ DOWN: shaft first, then 5-row pyramid (narrow→wide toward tip)
    lcd.drawFilledRectangle(cx - 10, y_top, 20, 55, 0)         -- shaft
    local ws = { 10, 24, 42, 60, 78 }
    for k, w in ipairs(ws) do
      lcd.drawFilledRectangle(cx - w // 2, y_top + 55 + (k-1)*13, w, 11, 0)
    end

  else
    -- ≡ STABLE: three horizontal bars
    lcd.drawFilledRectangle(cx - 40, y_top + 10, 80, 14, 0)
    lcd.drawFilledRectangle(cx - 40, y_top + 40, 80, 14, 0)
    lcd.drawFilledRectangle(cx - 40, y_top + 70, 80, 14, 0)
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
    fast_ema = 0.70 * fast_ema + 0.30 * str
    slow_ema = 0.95 * slow_ema + 0.05 * str
    strength = str
    if str > peak_str then peak_str = str end
  end

  -- Trend: only meaningful when we have live telemetry
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
    -- Left panel  (x   0-236): signal data
    -- Right panel (x 240-480): large trend arrow + comparison bars
    --------------------------------------------------------------------------

    -- ── Left panel ──────────────────────────────────────────────────────
    lcd.drawText(6, 6, "ELRS Finder", MIDSIZE)

    lcd.drawText(6, 30, raw
      and string.format("Src:%-3s  Raw:%.1f dBm", kind, raw)
      or  "Src:NA  (waiting...)", 0)

    -- Strength bar
    lcd.drawRectangle(6, 50, 214, 16)
    lcd.drawFilledRectangle(7, 51, math.floor(strength * 210 / 100), 14, 0)
    lcd.drawText(224, 52, string.format("%d%%", math.floor(strength)), 0)

    lcd.drawText(6, 74, avg
      and string.format("Avg: %.1f dBm", avg)
      or  "Avg: ---", 0)

    -- Peak and gap from peak
    lcd.drawText(6, 94, string.format("Peak: %d%%", math.floor(peak_str)), 0)
    if raw and peak_str > 0 then
      lcd.drawText(120, 94, string.format("Gap:%+d%%",
        math.floor(strength - peak_str)), 0)
    end

    -- Trend text label
    local tlbl = trend ==  1 and "^ CLOSER"
              or trend == -1 and "v FARTHER"
              or                 "= STABLE"
    lcd.drawText(6, 118, "Trend: " .. tlbl, 0)

    -- Hints
    lcd.drawText(6, 155, "ENT: reset peak", 0)
    lcd.drawText(6, 175, "Walk & watch arrow", 0)
    lcd.drawText(6, 195, "^=closer  v=farther", 0)

    -- Panel divider (filled rectangle, not drawLine)
    lcd.drawFilledRectangle(237, 0, 3, H, 0)

    -- ── Right panel ─────────────────────────────────────────────────────
    local CX = 360

    lcd.drawText(CX - 28, 6, "TREND", MIDSIZE)

    drawTrendArrow(CX, 35, trend)   -- arrow occupies y 35-155

    -- Direction label below arrow
    if trend == 1 then
      lcd.drawText(CX - 36, 163, "CLOSER",  MIDSIZE)
    elseif trend == -1 then
      lcd.drawText(CX - 42, 163, "FARTHER", MIDSIZE)
    else
      lcd.drawText(CX - 36, 163, "STABLE",  MIDSIZE)
    end

    -- Peak vs Now comparison bars
    local BX = CX - 65    -- x=295 (within right panel)
    local BW = 130        -- bar width; right edge x=425 (<480)

    lcd.drawText(BX, 185, "Peak", 0)
    lcd.drawRectangle(BX, 197, BW, 12)
    lcd.drawFilledRectangle(BX+1, 198,
      math.floor(peak_str * (BW-2) / 100), 10, 0)
    lcd.drawText(BX + BW + 4, 197,
      string.format("%d%%", math.floor(peak_str)), 0)

    lcd.drawText(BX, 215, "Now ", 0)
    lcd.drawRectangle(BX, 227, BW, 12)
    lcd.drawFilledRectangle(BX+1, 228,
      math.floor(strength * (BW-2) / 100), 10, 0)
    lcd.drawText(BX + BW + 4, 227,
      string.format("%d%%", math.floor(strength)), 0)

  else
    --------------------------------------------------------------------------
    -- Boxer  128×64  (original layout; trend arrow replaces tip-text line)
    --------------------------------------------------------------------------
    lcd.drawText(2,  2,  "ELRS Finder", MIDSIZE)
    lcd.drawText(2,  18, string.format("Src:%s", kind), 0)
    lcd.drawText(60, 18, raw  and string.format("Raw:%.1f", raw)     or "---", 0)
    lcd.drawText(2,  30, "Strength:", 0)
    lcd.drawRectangle(58, 30, 66, 10)
    lcd.drawFilledRectangle(59, 31, math.floor(strength * 64 / 100), 8, 0)
    lcd.drawText(2,  44, avg
      and string.format("Avg:%.1f dBm", avg)
      or  "Avg:--- dBm", 0)
    -- Trend arrow on last line (replaces old tip text)
    local t_sym = trend ==  1 and "^" or (trend == -1 and "v" or "=")
    local t_lbl = trend ==  1 and "Closer"  or
                  trend == -1 and "Farther" or "Stable"
    lcd.drawText(2,  54, t_sym, INVERS)
    lcd.drawText(16, 54, t_lbl, 0)
  end

  return 0
end

return { run = run_func }
