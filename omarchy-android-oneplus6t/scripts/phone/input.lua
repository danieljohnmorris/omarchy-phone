-- Phone: touchscreen maps to the panel, gb layout for the on-screen keyboard,
-- touch swipe between workspaces.
hl.config({
  input = {
    kb_layout = "gb",
    touchdevice = { output = "DSI-1" },
  },
  gestures = {
    workspace_swipe_touch = true,
    workspace_swipe_touch_invert = false,
  },
})

-- Phone: Omarchy sets QT_IM_MODULE/XMODIFIERS to fcitx, but fcitx5 is masked here
-- (its restart loop fights squeekboard). Qt apps -- including the Omarchy shell
-- itself, so the Wi-Fi passphrase box -- then have no input method at all. Point
-- them at the Wayland text-input protocol squeekboard speaks.
hl.env("QT_IM_MODULE", "wayland")
hl.env("GTK_IM_MODULE", "wayland")
hl.env("XMODIFIERS", "@im=none")
hl.env("SDL_IM_MODULE", "wayland")
