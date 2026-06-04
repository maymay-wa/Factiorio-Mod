-- data.lua — Interplanetary Portals
-- Defines portal entities, items, recipes, and technologies for each planet.

------------------------------------------------------------
-- Configuration
------------------------------------------------------------

-- Set to true for testing: all portals cost 1 steel plate
local DEV_MODE = true

local planets = {
  {
    name = "nauvis",
    label = "Nauvis",
    tint = {r = 0.2, g = 0.9, b = 0.3, a = 0.6},
    ingredients = {
      {type = "item", name = "electronic-circuit", amount = 200},
      {type = "item", name = "iron-plate",         amount = 100},
      {type = "item", name = "copper-plate",        amount = 100},
    },
    tech_prerequisites = {"rocket-silo"},
    science_packs = {
      {"automation-science-pack", 1},
      {"logistic-science-pack",   1},
      {"chemical-science-pack",   1},
      {"space-science-pack",      1},
    },
  },
  {
    name = "vulcanus",
    label = "Vulcanus",
    tint = {r = 1.0, g = 0.45, b = 0.1, a = 0.6},
    ingredients = {
      {type = "item", name = "tungsten-plate",   amount = 200},
      {type = "item", name = "tungsten-carbide",  amount = 100},
      {type = "item", name = "carbon",            amount = 50},
    },
    tech_prerequisites = {"planet-discovery-vulcanus"},
    science_packs = {
      {"automation-science-pack",  1},
      {"logistic-science-pack",    1},
      {"chemical-science-pack",    1},
      {"space-science-pack",       1},
      {"metallurgic-science-pack", 1},
    },
  },
  {
    name = "fulgora",
    label = "Fulgora",
    tint = {r = 0.3, g = 0.5, b = 1.0, a = 0.6},
    ingredients = {
      {type = "item", name = "holmium-plate",    amount = 200},
      {type = "item", name = "superconductor",    amount = 100},
      {type = "item", name = "lightning-rod",      amount = 50},
    },
    tech_prerequisites = {"planet-discovery-fulgora"},
    science_packs = {
      {"automation-science-pack",      1},
      {"logistic-science-pack",        1},
      {"chemical-science-pack",        1},
      {"space-science-pack",           1},
      {"electromagnetic-science-pack", 1},
    },
  },
  {
    name = "gleba",
    label = "Gleba",
    tint = {r = 0.7, g = 0.2, b = 0.9, a = 0.6},
    ingredients = {
      {type = "item", name = "bioflux",       amount = 200},
      {type = "item", name = "carbon-fiber",   amount = 100},
      {type = "item", name = "nutrients",      amount = 50},
    },
    tech_prerequisites = {"planet-discovery-gleba"},
    science_packs = {
      {"automation-science-pack",  1},
      {"logistic-science-pack",    1},
      {"chemical-science-pack",    1},
      {"space-science-pack",       1},
      {"agricultural-science-pack", 1},
    },
  },
  {
    name = "aquilo",
    label = "Aquilo",
    tint = {r = 0.3, g = 0.9, b = 1.0, a = 0.6},
    ingredients = {
      {type = "item",  name = "lithium-plate",       amount = 200},
      {type = "item",  name = "quantum-processor",    amount = 100},
      {type = "item",  name = "ice-platform",         amount = 50},
    },
    tech_prerequisites = {"planet-discovery-aquilo"},
    science_packs = {
      {"automation-science-pack", 1},
      {"logistic-science-pack",   1},
      {"chemical-science-pack",   1},
      {"space-science-pack",      1},
      {"cryogenic-science-pack",  1},
    },
  },
}

------------------------------------------------------------
-- Helper: recursively apply a tint to all sprite layers
------------------------------------------------------------

local function apply_tint_recursive(t, tint)
  if type(t) ~= "table" then return end
  -- If this table has a "filename" key it is a sprite/animation frame
  if t.filename then
    t.tint = tint
  end
  for _, v in pairs(t) do
    if type(v) == "table" then
      apply_tint_recursive(v, tint)
    end
  end
end

------------------------------------------------------------
-- Helper: build a full recipe ingredient list
-- (base cost + planet-specific)
------------------------------------------------------------

local function build_ingredients(planet)
  if DEV_MODE then
    return {{type = "item", name = "steel-plate", amount = 1}}
  end
  local ingredients = {
    {type = "item", name = "concrete",    amount = 1000},
    {type = "item", name = "steel-plate", amount = 1000},
  }
  for _, ing in ipairs(planet.ingredients) do
    table.insert(ingredients, ing)
  end
  return ingredients
end

------------------------------------------------------------
-- Create prototypes for each planet
------------------------------------------------------------

local cargo_pad_base = data.raw["cargo-landing-pad"]["cargo-landing-pad"]

local function make_dumb_pad(base_pad, name, tint)
  local ent = table.deepcopy(base_pad)
  ent.type           = "container"
  ent.name           = name
  ent.inventory_size = 0
  ent.minable        = {mining_time = 2, result = name}
  ent.placeable_by   = {item = name, count = 1}

  ent.picture = {
    filename = "__interplanetary-portals__/sprite.png",
    size     = 256,
    scale    = 0.5,
    tint     = tint,
  }

  -- Remove cargo-landing-pad specific properties
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

  apply_tint_recursive(ent, tint)
  return ent
end

for _, planet in ipairs(planets) do

  local portal_name = planet.name .. "-portal"
  local tech_name   = "interplanetary-portal-" .. planet.name

  ---------- PORTAL (dumb pad) ----------

  local portal_entity = make_dumb_pad(cargo_pad_base, portal_name, planet.tint)

  local portal_item = {
    type           = "item",
    name           = portal_name,
    icon           = "__interplanetary-portals__/sprite.png",
    icon_size      = 256,
    icons          = {
      {icon = "__interplanetary-portals__/sprite.png", icon_size = 256, tint = planet.tint},
    },
    subgroup       = "space-related",
    order          = "z[portal]-" .. planet.name,
    place_result   = portal_name,
    stack_size     = 1,
  }

  local portal_recipe = {
    type        = "recipe",
    name        = portal_name,
    enabled     = false,
    energy_required = DEV_MODE and 0.5 or 30,
    ingredients = build_ingredients(planet),
    results     = {{type = "item", name = portal_name, amount = 1}},
  }


  ---------- TECHNOLOGY ----------

  local tech = {
    type          = "technology",
    name          = tech_name,
    icon          = "__interplanetary-portals__/sprite.png",
    icon_size     = 256,
    icons         = {
      {icon = "__interplanetary-portals__/sprite.png", icon_size = 256, tint = planet.tint},
    },
    prerequisites = planet.tech_prerequisites,
    unit = DEV_MODE and {
      count       = 1,
      ingredients = {{"automation-science-pack", 1}},
      time        = 1,
    } or {
      count       = 500,
      ingredients = planet.science_packs,
      time        = 60,
    },
    effects = {
      {type = "unlock-recipe", recipe = portal_name},
    },
  }



  ---------- Register everything ----------

  data:extend({
    portal_entity,
    portal_item,
    portal_recipe,
    tech,
  })
end