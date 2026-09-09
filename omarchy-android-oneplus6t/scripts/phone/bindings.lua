-- ~/.config/hypr/bindings.lua on the phone. Loaded after Omarchy's defaults.

-- Omarchy binds the power key straight to the power menu. On the phone the
-- same key also has to wake the panel after fajita-screen-off, so route it
-- through a script that checks DPMS first.
hl.unbind("XF86PowerOff")
o.bind("XF86PowerOff", "Power key: wake screen or power menu", "fajita-power-key", { locked = true })
