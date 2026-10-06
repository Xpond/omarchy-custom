-- The compositor exports this before its startup callbacks launch Quickshell.
hl.env("QSG_RENDER_LOOP", "threaded")

-- The wheel's backdrop row saves "off" here at 0%, as data; anything else keeps the backdrop blurred.
local blur_file = io.open(os.getenv("HOME") .. "/.config/omarchy/wheel-blur")
local backdrop_blur = not (blur_file and blur_file:read("*l") or ""):match("^%s*off%s*$")
if blur_file then blur_file:close() end
-- Omarchy leaves Hyprland's blur off; only the backdrop turns it on.
if backdrop_blur then hl.config({ decoration = { blur = { enabled = true, size = 4, passes = 2 } } }) end

-- Blur only the shared backdrop; blurring the overlays doubles the work. No ignore_alpha, so a light
-- dim keeps its blur.
hl.layer_rule({
  match = { namespace = "omarchy-panel-scrim" },
  blur = backdrop_blur,
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

-- A press while the wheel is up closes it, so the release cannot reopen it by landing first.
hl.unbind(wheel_key)
o.bind(wheel_key, "Wheel", "omarchy-shell -q shell toggle xpo.wheel")
o.bind(wheel_key, nil, "omarchy-shell -q shell call xpo.wheel commit ''", { release = true })

-- SUPER+W normally closes a window; the helper retains that fallback.
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close wheel or window", "omarchy-wheel-close")
