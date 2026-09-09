-- OnePlus 6T panel: 1080x2340 portrait, scale 2 -> 540x1170 logical
hl.monitor({ output = "DSI-1", mode = "1080x2340@60", position = "0x0", scale = 2 })
hl.env("GDK_SCALE", "2")
