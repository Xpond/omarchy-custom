-- The compositor exports this before its startup callbacks launch Quickshell.
hl.env("QSG_RENDER_LOOP", "threaded")
hl.config({ decoration = { blur = { enabled = true, size = 4, passes = 2 } } })

-- Blur only the shared backdrop; blurring the overlays doubles the work.
hl.layer_rule({
  match = { namespace = "omarchy-panel-scrim" },
  blur = true,
  ignore_alpha = 0.05,
  no_anim = true,
  animation = "none",
})
hl.layer_rule({
  match = { namespace = "^(omarchy-wheel|omarchy-files)$" },
  blur = false,
  no_anim = true,
  animation = "none",
})

-- The wheel's shortcut row saves its key here, as data; anything unreadable keeps SUPER+A.
local wheel_key = "SUPER + A"
do
  local file = io.open(os.getenv("HOME") .. "/.config/omarchy/wheel-shortcut")
  local saved = (file and file:read("*l") or ""):match("^%s*(.-)%s*$")
  if file then file:close() end
  if saved:match("^[%u%d_][%u%d_ +]*[%u%d_]$") and saved:find(" + ", 1, true) then wheel_key = saved end
end

hl.unbind(wheel_key)
o.bind(wheel_key, "Wheel", "omarchy-shell -q shell summon xpo.wheel")
o.bind(wheel_key, nil, "omarchy-shell -q shell call xpo.wheel commit ''", { release = true })

-- SUPER+W normally closes a window; the helper retains that fallback.
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close wheel or window", "omarchy-wheel-close")
