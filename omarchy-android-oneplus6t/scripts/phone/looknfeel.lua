-- ~/.config/hypr/looknfeel.lua on the phone. Loaded after Omarchy's defaults.

-- Omarchy sizes every floating window (update, TUIs, About) at 875x600 for a
-- laptop. The phone is 540 logical pixels wide, so that overflowed the screen
-- by a third and the update prompt's "press any key" sat off the right edge.
-- Later rules for the same window win, so these replace the default size.
-- Logical screen is 540x1170 and the on-screen keyboard reserves the bottom
-- 315px, so 518x640 fills the width and leaves room above the keys.
o.window({ tag = "floating-window" }, { size = { 518, 640 } })
o.window("org.omarchy.about", { size = { 518, 640 } })

-- Hyprland's own "Support Hyprland" popup is an internal surface, not a client
-- window, so no rule can resize it. It is ~900px wide and its close button is
-- off the phone's screen. Sponsor upstream from a laptop instead.
hl.config({ ecosystem = { no_donation_nag = true } })

-- Only the power key wakes a switched-off panel (fajita-power-key). With these
-- on, Hyprland wakes it on any key or touch, which reopens the menu on every
-- wake and lights the screen in a pocket.
hl.config({ misc = { key_press_enables_dpms = false, mouse_move_enables_dpms = false } })

-- No pointer on a touchscreen: hide it after a moment of no mouse movement and
-- on every touch. Hyprland otherwise draws one in the middle of the screen at login.
hl.config({ cursor = { inactive_timeout = 1, hide_on_touch = true, hide_on_key_press = true } })
