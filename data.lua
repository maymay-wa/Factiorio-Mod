-- data.lua — Interplanetary Portals
-- Single portal with 4 inventory slots for warp modules (one per planet).

------------------------------------------------------------
-- Configuration
------------------------------------------------------------

local DEV_MODE = true

local PORTAL_NAME = "interplanetary-portal"

local planets = {
  {
    name               = "nauvis",
    label              = "Nauvis",
    tint               = {r = 1.0, g = 1.0, b = 1.0, a = 1.0},
    ingredients        = {
      {type = "item", name = "electronic-circuit", amount = 200},
      {type = "item", name = "iron-plate",         amount = 100},
      {type = "item", name = "copper-plate",        amount = 100},
    },
    tech_prerequisites = {},  -- base portal tech already covers rocket-silo
    science_packs      = {
      {"automation-science-pack", 1},
      {"logistic-science-pack",   1},
      {"chemical-science-pack",   1},
      {"space-science-pack",      1},
    },
  },
  {
    name               = "vulcanus",
    label              = "Vulcanus",
    tint               = {r = 0.957, g = 0.714, b = 0.333, a = 1.0},
    ingredients        = {
      {type = "item", name = "tungsten-plate",   amount = 200},
      {type = "item", name = "tungsten-carbide",  amount = 100},
      {type = "item", name = "carbon",            amount = 50},
    },
    tech_prerequisites = {"planet-discovery-vulcanus"},
    science_packs      = {
      {"automation-science-pack",  1},
      {"logistic-science-pack",    1},
      {"chemical-science-pack",    1},
      {"space-science-pack",       1},
      {"metallurgic-science-pack", 1},
    },
  },
  {
    name               = "fulgora",
    label              = "Fulgora",
    tint               = {r = 0.886, g = 0.439, b = 0.725, a = 1.0},
    ingredients        = {
      {type = "item", name = "holmium-plate",  amount = 200},
      {type = "item", name = "superconductor",  amount = 100},
      {type = "item", name = "lightning-rod",   amount = 50},
    },
    tech_prerequisites = {"planet-discovery-fulgora"},
    science_packs      = {
      {"automation-science-pack",      1},
      {"logistic-science-pack",        1},
      {"chemical-science-pack",        1},
      {"space-science-pack",           1},
      {"electromagnetic-science-pack", 1},
    },
  },
  {
    name               = "gleba",
    label              = "Gleba",
    tint               = {r = 0.890, g = 0.871, b = 0.369, a = 1.0},
    ingredients        = {
      {type = "item", name = "bioflux",      amount = 200},
      {type = "item", name = "carbon-fiber",  amount = 100},
      {type = "item", name = "nutrients",     amount = 50},
    },
    tech_prerequisites = {"planet-discovery-gleba"},
    science_packs      = {
      {"automation-science-pack",   1},
      {"logistic-science-pack",     1},
      {"chemical-science-pack",     1},
      {"space-science-pack",        1},
      {"agricultural-science-pack", 1},
    },
  },
  {
    name               = "aquilo",
    label              = "Aquilo",
    tint               = {r = 0.204, g = 0.271, b = 0.737, a = 1.0},
    ingredients        = {
      {type = "item", name = "lithium-plate",    amount = 200},
      {type = "item", name = "quantum-processor", amount = 100},
      {type = "item", name = "ice-platform",      amount = 50},
    },
    tech_prerequisites = {"planet-discovery-aquilo"},
    science_packs      = {
      {"automation-science-pack", 1},
      {"logistic-science-pack",   1},
      {"chemical-science-pack",   1},
      {"space-science-pack",      1},
      {"cryogenic-science-pack",  1},
    },
  },
}

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function apply_tint_recursive(t, tint)
  if type(t) ~= "table" then return end
  if t.filename then
    t.tint = tint
  end
  for _, v in pairs(t) do
    if type(v) == "table" then
      apply_tint_recursive(v, tint)
    end
  end
end

local function make_dumb_pad(base_pad, name, tint)
  local ent = table.deepcopy(base_pad)
  ent.type           = "container"
  ent.name           = name
  ent.inventory_size = 0
  ent.minable        = {mining_time = 2, result = name}
  ent.placeable_by   = {item = name, count = 1}

  ent.picture = {
    filename = "__interplanetary-portals__/Assets/sprite.png",
    size     = 256,
    scale    = 0.75,
    tint     = tint,
  }

  ent.graphics_set              = nil
  ent.trash_inventory_size      = nil
  ent.cargo_station_parameters  = nil
  ent.robot_animation           = nil
  ent.robot_opened_duration     = nil
  ent.circuit_connector         = nil
  ent.circuit_wire_max_distance = nil
  ent.draw_circuit_wires        = nil
  ent.draw_copper_wires         = nil
  ent.radar_range               = nil
  ent.radar_visualisation_color = nil

  if tint then
    apply_tint_recursive(ent, tint)
  end
  return ent
end

------------------------------------------------------------
-- Single portal entity + item + recipe + technology
------------------------------------------------------------

local cargo_pad_base = data.raw["cargo-landing-pad"]["cargo-landing-pad"]

local portal_entity = make_dumb_pad(cargo_pad_base, PORTAL_NAME, nil)
portal_entity.inventory_size = 4

local portal_item = {
  type         = "item",
  name         = PORTAL_NAME,
  icon         = "__interplanetary-portals__/Assets/sprite.png",
  icon_size    = 256,
  subgroup     = "space-related",
  order        = "z[portal]-a",
  place_result = PORTAL_NAME,
  stack_size   = 1,
}

local portal_recipe = {
  type            = "recipe",
  name            = PORTAL_NAME,
  enabled         = false,
  energy_required = DEV_MODE and 0.5 or 30,
  ingredients     = DEV_MODE and
    {{type = "item", name = "steel-plate", amount = 1}} or
    {
      {type = "item", name = "concrete",    amount = 1000},
      {type = "item", name = "steel-plate", amount = 1000},
    },
  results         = {{type = "item", name = PORTAL_NAME, amount = 1}},
}

local portal_tech = {
  type          = "technology",
  name          = PORTAL_NAME,
  icon          = "__interplanetary-portals__/Assets/sprite.png",
  icon_size     = 256,
  prerequisites = {"rocket-silo"},
  unit          = DEV_MODE and {
    count       = 1,
    ingredients = {{"automation-science-pack", 1}},
    time        = 1,
  } or {
    count       = 500,
    ingredients = {
      {"automation-science-pack", 1},
      {"logistic-science-pack",   1},
      {"chemical-science-pack",   1},
      {"space-science-pack",      1},
    },
    time        = 60,
  },
  effects       = {{type = "unlock-recipe", recipe = PORTAL_NAME}},
}

data:extend({portal_entity, portal_item, portal_recipe, portal_tech})

------------------------------------------------------------
-- Warp modules — one per planet
------------------------------------------------------------

for _, planet in ipairs(planets) do
  local module_name = "warp-module-" .. planet.name

  local tech_prereqs = {PORTAL_NAME}
  for _, prereq in ipairs(planet.tech_prerequisites) do
    table.insert(tech_prereqs, prereq)
  end

  local module_item = {
    type      = "item",
    name      = module_name,
    icons     = {
      {icon = "__base__/graphics/icons/plastic-bar.png", icon_size = 64, tint = planet.tint},
    },
    subgroup  = "space-related",
    order     = "z[warp-module]-" .. planet.name,
    stack_size = 1,
  }

  local module_recipe = {
    type            = "recipe",
    name            = module_name,
    enabled         = false,
    energy_required = DEV_MODE and 0.5 or 30,
    ingredients     = DEV_MODE and
      {{type = "item", name = "iron-plate", amount = 1}} or
      planet.ingredients,
    results         = {{type = "item", name = module_name, amount = 1}},
  }

  local module_tech = {
    type          = "technology",
    name          = module_name,
    icons         = {
      {icon = "__base__/graphics/icons/plastic-bar.png", icon_size = 64, tint = planet.tint},
    },
    prerequisites = tech_prereqs,
    unit          = DEV_MODE and {
      count       = 1,
      ingredients = {{"automation-science-pack", 1}},
      time        = 1,
    } or {
      count       = 500,
      ingredients = planet.science_packs,
      time        = 60,
    },
    effects       = {{type = "unlock-recipe", recipe = module_name}},
  }

  data:extend({module_item, module_recipe, module_tech})
end

------------------------------------------------------------
-- Portal animation (used by rendering.draw_animation in control.lua)
------------------------------------------------------------

data:extend({{
  type            = "animation",
  name            = "portal-animation",
  filename        = "__interplanetary-portals__/Assets/final.png",
  width           = 495,
  height          = 485,
  frame_count     = 36,
  line_length     = 6,
  animation_speed = 0.5 / 3,
  scale           = 0.4,
}})
