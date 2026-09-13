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

hl.unbind("SUPER + A")
o.bind("SUPER + A", "Wheel", "omarchy-shell -q shell summon xpo.wheel")
o.bind("SUPER + A", nil, "omarchy-shell -q shell call xpo.wheel commit ''", { release = true })

-- SUPER+W normally closes a window; the helper retains that fallback.
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close wheel or window", "omarchy-wheel-close")
