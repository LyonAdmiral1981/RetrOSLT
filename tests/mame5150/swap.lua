local tag
for t, img in pairs(manager.machine.images) do
  if t:find("fdc:0") then tag = t end
end
print("SWAP-DRIVE", tag)
local done = false
emu.register_frame_done(function()
  if done then return end
  local mem = manager.machine.devices[":maincpu"].spaces["program"]
  if mem:read_u8(0x4F0) == 0xA5 then
    manager.machine.images[tag]:load(os.getenv("SWAP_IMAGE"))
    mem:write_u8(0x4F0, 0x5A)
    done = true
    print("SWAPPED")
  end
end)
