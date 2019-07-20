--[[ Spot Welder with dual pulse controller

https://github.com/northox/spot-welder

- OLED Display: SDA->D1/5, SCL->D2/4
- Solid State Relay: D8/15
- Welding switch: D4/2
- Rotary encoder: CLK->D5/14, DT->D6/12, SW->D7/13

]]

sda_pin = 2 -- gpio 4
scl_pin = 1 -- gpio 5
oled_id = 0 -- i2c interface id
zap_pin = 4 -- gpio 2
relay_pin=0 -- gpio 16
enco_clk_pin = 5 -- gpio 14
enco_dt_pin  = 6 -- gpio 12
enco_sm_pin  = 7 -- gpio 13

pulse1 = 0
delay = 0
pulse2 = 0
pos_old = 0
select_line = 0
str1_sep = "*"
str2_sep = ":"
str3_sep = ":"
last_zap = 0
debounce_delay = 1000000 -- 1-second re-trigger delay

-- turn off the SSR at start in case we are recovering from a crash
gpio.mode(zap_pin, gpio.INPUT, gpio.PULLUP)
gpio.mode(relay_pin, gpio.OUTPUT)
gpio.write(relay_pin, gpio.LOW)

-- XXXXXXXXXXXXXXXXXXXXX
function load_config()
  files = file.list()
  if files["pulse1.conf"] then
    if file.open("pulse1.conf", "r") then
      pulse1 = file.read()
      file.close()
    end
    if file.open("delay.conf", "r") then
      delay = file.read()
      file.close()
    end
    if file.open("pulse2.conf", "r") then
      pulse2 = file.read()
      file.close()
    end
  end
  str1="Pulse1" .. str1_sep .. " " .. pulse1 .. " ms"
  str2="Delay " .. str2_sep .. " "  .. delay .. " ms"
  str3="Pulse2" .. str3_sep .. " " .. pulse2 .. " ms"
end

-- XXXXXXXXXXXXXXXXXXXXXXXX
function save_config()
  files = file.list()
  if file.open("pulse1.conf", "w") then
    file.write(pulse1)
    file.close()
  end
  if file.open("delay.conf", "w") then
    file.write(delay)
    file.close()
  end
  if file.open("pulse2.conf", "w") then
    file.write(pulse2)
    file.close()
  end
end

function init_OLED(sda, scl, id)
  sla = 0x3C -- i2c slave offset
  i2c.setup(id, sda, scl, i2c.SLOW)
  disp = u8g2.sh1106_i2c_128x64_noname(id, sla)
  disp:setFlipMode(1)
  disp:clearBuffer()
  disp:setContrast(255)
  disp:setFontMode(0)
  disp:setDrawColor(1)
  disp:setBitmapMode(0)
  disp:setFont(u8g2.font_6x10_tf)
  disp:setFontRefHeightExtendedText()
  disp:setFontPosTop()
  disp:setFontDirection(0)
end

function top_line(str)
  disp:clearBuffer()
  disp:drawStr(5, 0, str)
  disp:sendBuffer()  
end

function print_OLED()
  disp:clearBuffer()
  disp:drawFrame(2,2,126,62)
  disp:drawStr(5, 16, str1)
  disp:drawStr(5, 30, str2)
  disp:drawStr(5, 44, str3)
  disp:sendBuffer()
end

rotary.setup(0, enco_clk_pin, enco_dt_pin, enco_sm_pin, 1000, 250)

load_config()
init_OLED(sda_pin, scl_pin, oled_id)
print_OLED()

gpio.trig(zap_pin, "down", function (level, when)
   local delta = when - last_zap
   if delta < 0 then delta = delta + 2147483647 end;
   if delta > debounce_delay then
    last_zap = when
    if level == 0 then
      -- Keeping the if statements outside the timing loop complicates the code, but gives more accurate timings.
      pulse1us = (pulse1*1000)-750
      pulse2us = (pulse2*1000)-750
      bothus = ((pulse1+pulse2)*1000)-750
      delayus = (delay*1000)
      -- XXXXXXXXXXXXXXXXXXx what happend if you submit a 0 delay??? if this works, remove all of that
      if pulse1 == 0 and pulse2 == 0 then -- Do nothing
        top_line("No Zap...")    
      elseif pulse2 == 0 then -- Only do pulse1
        top_line("Zap Pulse 1...")
        gpio.write(relay_pin, gpio.HIGH)
        tmr.delay(pulse1us)
        gpio.write(relay_pin, gpio.LOW)
      elseif pulse1 == 0 then -- Only do pulse2
        top_line("Zap Pulse 2...")
        gpio.write(relay_pin, gpio.HIGH)
        tmr.delay(pulse2us)
        gpio.write(relay_pin, gpio.LOW)
      elseif delay == 0 then -- Add pulse1+pulse2 into single longer pulse
        top_line("Zap Pulse 1+2...")
        gpio.write(relay_pin, gpio.HIGH)
        tmr.delay(bothus)
        gpio.write(relay_pin, gpio.LOW)
      else  -- Double-zap cycle - pulse1, delay, pulse2
        top_line("Double Zap...")
        gpio.write(relay_pin, gpio.HIGH)
        tmr.delay(pulse1us)
        gpio.write(relay_pin, gpio.LOW)
        tmr.delay(delayus)
        gpio.write(relay_pin, gpio.HIGH)
        tmr.delay(pulse2us)
        gpio.write(relay_pin, gpio.LOW)
      end
      print_OLED()
    end
  end
end
)

rotary.on(0, rotary.TURN, function (type, pos, when)
  if bit.isclear(pos,1)  then
    if bit.isclear(pos,0) then
      diff = pos - pos_old
      pos_old = pos
      -- XXXXXXXXXXXXXXXXXXXX this is all the same thing, extract in a function
      if select_line == 0 then
        pulse1 = pulse1 + diff
        if pulse1 < 0 then 
          pulse1 = 0
        end
        if pulse1 > 1000 then
          pulse1 = 1000
        end
        str1="Pulse 1" .. str1_sep .. " " .. pulse1 .. " ms"
      end
      if select_line == 1 then
        delay = delay + diff
        if delay < 0 then 
          delay = 0
        end
        if delay > 1000 then
          delay = 1000
        end
        str2="Delay " .. str2_sep .. " " .. delay .. " ms"
      end
      if select_line == 2 then
        pulse2 = pulse2 + diff
        if pulse2 < 0 then 
          pulse2 = 0
        end
        if pulse2 > 1000 then
          pulse2 = 1000
        end
        str3="Pulse 2" .. str3_sep .. " " .. pulse2 .. " ms"
      end
      print_OLED()
    end
  end
end
)

rotary.on(0, rotary.CLICK, function (type, pos, when)
  if select_line < 2 then
    select_line = select_line+1
  else
    select_line = 0
  end
  -- use case
  if select_line == 0 then
    str1_sep = "*"
  else
    str1_sep = ":"
  end
  if select_line == 1 then
    str2_sep = "*"
  else
    str2_sep = ":"
  end
  if select_line == 2 then
    str3_sep = "*"
  else
    str3_sep = ":"
  end
  str1="Pulse1" .. str1_sep .. " " .. pulse1 .. " ms"
  str2="Delay " .. str2_sep .. " "  .. delay .. " ms"
  str3="Pulse2" .. str3_sep .. " " .. pulse2 .. " ms"
  print_OLED()
end
)

rotary.on(0, rotary.DBLCLICK, function (type, pos, when)
  top_line("Saving...")
  save_config()
  print_OLED()
end
)

rotary.on(0, rotary.LONGPRESS, function (type, pos, when)
  top_line("Loading...")
  load_config()
  select_line=2
  print_OLED()
end
)
