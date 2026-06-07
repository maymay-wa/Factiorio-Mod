-- settings.lua — Interplanetary Portals
-- Player-facing tuning knobs. See data.lua / control.lua for where each is read.

data:extend({
  {
    -- Scales the ingredient amounts of the portal and every warp-module recipe.
    -- Read at the data stage in data.lua (must be startup).
    type          = "double-setting",
    name          = "portal-recipe-cost-multiplier",
    setting_type  = "startup",
    default_value = 1.0,
    minimum_value = 0.1,
    maximum_value = 10.0,
    order         = "a",
  },
  {
    -- Scales the rocket-fuel fee consumed by the portal per trip.
    -- 0 = free travel for everyone. Read live in control.lua (runtime-global).
    type          = "double-setting",
    name          = "portal-travel-cost-multiplier",
    setting_type  = "runtime-global",
    default_value = 1.0,
    minimum_value = 0.0,
    maximum_value = 10.0,
    order         = "b",
  },
  {
    -- When off, the Cargo Warp Module (item/recipe/tech) is never created and
    -- travellers must always empty their inventory before warping.
    type          = "bool-setting",
    name          = "portal-enable-cargo-module",
    setting_type  = "startup",
    default_value = true,
    order         = "c",
  },
})
