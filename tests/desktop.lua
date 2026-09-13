local binds, layers, env = {}, {}, {}
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
assert(#binds["SUPER + A"] == 2 and binds["SUPER + A"][2].release)
assert(binds["SUPER + A"][1].command:find("summon xpo.wheel", 1, true))
assert(binds["SUPER + A"][2].command:find("commit", 1, true))
assert(#binds["SUPER + W"] == 1 and binds["SUPER + W"][1].command == "omarchy-wheel-close")
assert(layers["omarchy-panel-scrim"].blur and layers["omarchy-panel-scrim"].ignore_alpha == 0.05)
assert(layers["^(omarchy-wheel|omarchy-files)$"].no_anim)
assert(layers["^(omarchy-wheel|omarchy-files)$"].blur == false)
