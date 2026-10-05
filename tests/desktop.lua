local binds, layers, env = {}, {}, {}
-- The key the shortcut file under $HOME should produce.
local key = arg[2] or "SUPER + A"
hl = {
  unbind = function(key) binds[key] = {} end,
  env = function(key, value) env[key] = value end,
  config = function(cfg) assert(cfg.decoration.blur.enabled) end,
  layer_rule = function(rule) layers[rule.match.namespace] = rule end,
}
o = { bind = function(key, label, command, options)
  table.insert(binds[key], { command = command, release = options and options.release })
end }

dofile(arg[1])

assert(env.QSG_RENDER_LOOP == "threaded")
assert(#binds[key] == 2 and binds[key][2].release, "no press/release pair on " .. key)
assert(binds[key][1].command:find("toggle xpo.wheel", 1, true))
assert(binds[key][2].command:find("commit", 1, true))
assert(key == "SUPER + A" or binds["SUPER + A"] == nil, "SUPER + A was taken as well as " .. key)
assert(#binds["SUPER + W"] == 1 and binds["SUPER + W"][1].command == "omarchy-wheel-close")
assert(layers["omarchy-panel-scrim"].blur and layers["omarchy-panel-scrim"].ignore_alpha == 0.05)
assert(layers["^(omarchy-wheel|omarchy-files)$"].no_anim)
assert(layers["^(omarchy-wheel|omarchy-files)$"].blur == false)
