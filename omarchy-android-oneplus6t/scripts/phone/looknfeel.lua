-- ~/.config/hypr/looknfeel.lua on the phone. Loaded after Omarchy's defaults.

-- Omarchy sizes every floating window (update, TUIs, About) at 875x600 for a
-- laptop. The phone is 540 logical pixels wide, so that overflowed the screen
-- by a third and the update prompt's "press any key" sat off the right edge.
-- Later rules for the same window win, so these replace the default size.
-- Logical screen is 540x1170 and the on-screen keyboard reserves the bottom
-- 315px, so 518x640 fills the width and leaves room above the keys.
o.window({ tag = "floating-window" }, { size = { 518, 640 } })
o.window("org.omarchy.about", { size = { 518, 640 } })
