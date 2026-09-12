-- ~/.config/hypr/looknfeel.lua on the phone. Loaded after Omarchy's defaults.

-- Omarchy sizes every floating window (update, TUIs, About) at 875x600, which
-- is laptop shaped. The phone is 540x1170 logical, so the width overflowed by
-- a third and the update prompt's "press any key" sat off the right edge.
-- Later rules for the same window win, so these replace the size only:
-- Omarchy's `center = true` still applies and the whole band stays usable.
--
-- The keyboard is handled outside the config, by fajita-osk-fit: it drops the
-- floating bit while squeekboard is up, so Hyprland tiles the window into the
-- reserved-aware area (516x754 at y=89, clear of the OSK top at y=855) and
-- restores it afterwards. Sizing for the keyboard here instead would waste
-- the bottom 315px whenever it is down, which is nearly always.
o.window({ tag = "floating-window" }, { size = { 518, 960 } })
o.window("org.omarchy.about", { size = { 518, 960 } })

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

-- Concept shell look: tight gaps, thin borders, blue focus accent. Gaps stay
-- small on the 540x1170 panel so tiles keep usable width; borders make the
-- focused window obvious with no mouse pointer.
hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 6,
    border_size = 2,
    ["col.active_border"] = "rgba(7aa2f7ff)",
    ["col.inactive_border"] = "rgba(41486855)",
  },
  decoration = { rounding = 6 },
})
