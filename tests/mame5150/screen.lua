print("LUA-START")
local out = os.getenv("SCREEN_OUT") or "screen.txt"
local function dump()
  local mem = manager.machine.devices[":maincpu"].spaces["program"]
  local f = io.open(out, "w")
  for _, base in ipairs({0xB8000, 0xB0000}) do
    f:write(string.format("== %05X\n", base))
    for row = 0, 24 do
      local line = {}
      for col = 0, 79 do
        local c = mem:read_u8(base + (row * 80 + col) * 2)
        line[#line + 1] = (c >= 32 and c < 127) and string.char(c) or " "
      end
      f:write((table.concat(line):gsub("%s+$", "")) .. "\n")
    end
  end
  f:close()
end
local frames = 0
emu.register_frame_done(function()
  frames = frames + 1
  if frames % 300 == 0 then dump() end
end)
