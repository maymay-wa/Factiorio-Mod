-- data.lua — Interplanetary Portals
-- Single portal with 4 inventory slots for warp modules (one per planet).

------------------------------------------------------------
-- Configuration
------------------------------------------------------------

local DEV_MODE = false

-- Player-facing tuning (see settings.lua).
local RECIPE_MULT   = settings.startup["portal-recipe-cost-multiplier"].value
local CARGO_ENABLED = settings.startup["portal-enable-cargo-module"].value

local PORTAL_NAME = "interplanetary-portal"

local planets = {
  {
    name               = "nauvis",
    label              = "Nauvis",
    tint               = {r = 1.0, g = 1.0, b = 1.0, a = 1.0},
    ingredients        = {
      {type = "item", name = "processing-unit",       amount = 200},
      {type = "item", name = "low-density-structure", amount = 100},
      {type = "item", name = "rocket-fuel",           amount = 100},
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
      {type = "item", name = "tungsten-plate",   amount = 500},
      {type = "item", name = "tungsten-carbide",  amount = 500},
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
      {type = "item", name = "holmium-plate",  amount = 500},
      {type = "item", name = "superconductor",  amount = 500},
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
      {type = "item", name = "carbon-fiber",  amount = 300},
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
      {type = "item", name = "ice-platform",      amount = 500},
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

-- Copy an ingredient list with each amount scaled by mult (never below 1).
local function scale_ingredients(list, mult)
  local out = {}
  for i, ing in ipairs(list) do
    out[i] = {type = ing.type, name = ing.name, amount = math.max(1, math.floor(ing.amount * mult))}
  end
  return out
end

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

  -- The cargo-landing-pad base carries "no-automated-item-insertion", which blocks
  -- inserters from loading the entity. Drop it so warp fuel/resources can be
  -- inserted by automation (it survives the type change to a plain container).
  if ent.flags then
    local kept = {}
    for _, flag in ipairs(ent.flags) do
      if flag ~= "no-automated-item-insertion" then kept[#kept + 1] = flag end
    end
    ent.flags = kept
  end

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
-- The portal's warp modules and per-trip resources live in its own filtered native
-- inventory, shown as standard item slots in the entity window (like a rocket silo).
-- Planet modules + optional cargo + free-travel module + 8 dedicated slots for the
-- per-trip warp resources (1 processing unit, 2 LDS, 5 rocket fuel — see WARP_COST
-- in control.lua, which must stay in sync with this count).
portal_entity.inventory_size = #planets + (CARGO_ENABLED and 1 or 0) + 1 + 8
-- Per-slot filters (applied in control.lua) give each warp module and warp resource
-- its own dedicated slot instead of a flat, undifferentiated grid.
portal_entity.inventory_type = "with_filters_and_bar"

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
    scale_ingredients({
      {type = "item", name = "concrete",    amount = 1000},
      {type = "item", name = "steel-plate", amount = 1000},
    }, RECIPE_MULT),
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
      {icon = "__interplanetary-portals__/Assets/disk_sprite.png", icon_size = 256, tint = planet.tint},
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
      scale_ingredients(planet.ingredients, RECIPE_MULT),
    results         = {{type = "item", name = module_name, amount = 1}},
  }

  local module_tech = {
    type          = "technology",
    name          = module_name,
    icons         = {
      {icon = "__interplanetary-portals__/Assets/disk_sprite.png", icon_size = 256, tint = planet.tint},
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
-- Cargo warp module — bring items through the portal
------------------------------------------------------------
-- A capstone module: installing it in a portal lets travellers carry their
-- inventory through instead of having to empty it first. Its technology requires
-- every planet module, so you can only build it once you already own every other
-- module.

local CARGO_MODULE_NAME = "warp-module-cargo"
local CARGO_TINT        = {r = 0.25, g = 0.25, b = 0.25, a = 1.0}

-- The tech still requires every planet module as a prerequisite, so you can only
-- build the cargo module once you already own every other module.
local cargo_prereqs = {PORTAL_NAME}
for _, planet in ipairs(planets) do
  table.insert(cargo_prereqs, "warp-module-" .. planet.name)
end

local cargo_item = {
  type       = "item",
  name       = CARGO_MODULE_NAME,
  icons      = {
    {icon = "__interplanetary-portals__/Assets/disk_sprite.png", icon_size = 256, tint = CARGO_TINT},
  },
  subgroup   = "space-related",
  order      = "z[warp-module]-zz-cargo",
  stack_size = 1,
}

-- Collect all planet ingredients so the cargo module demands resources from every planet.
local cargo_planet_ingredients = {}
for _, planet in ipairs(planets) do
  for _, ing in ipairs(planet.ingredients) do
    table.insert(cargo_planet_ingredients, {type = ing.type, name = ing.name, amount = ing.amount})
  end
end

local cargo_recipe = {
  type            = "recipe",
  name            = CARGO_MODULE_NAME,
  enabled         = false,
  energy_required = DEV_MODE and 0.5 or 60,
  ingredients     = DEV_MODE and
    {{type = "item", name = "iron-plate", amount = 1}} or
    scale_ingredients(cargo_planet_ingredients, RECIPE_MULT),
  results         = {{type = "item", name = CARGO_MODULE_NAME, amount = 1}},
}

local cargo_tech = {
  type          = "technology",
  name          = CARGO_MODULE_NAME,
  icons         = {
    {icon = "__interplanetary-portals__/Assets/disk_sprite.png", icon_size = 256, tint = CARGO_TINT},
  },
  prerequisites = cargo_prereqs,
  unit          = DEV_MODE and {
    count       = 1,
    ingredients = {{"automation-science-pack", 1}},
    time        = 1,
  } or {
    count       = 1000,
    ingredients = {
      {"automation-science-pack",      1},
      {"logistic-science-pack",        1},
      {"chemical-science-pack",        1},
      {"space-science-pack",           1},
      {"metallurgic-science-pack",     1},
      {"electromagnetic-science-pack", 1},
      {"agricultural-science-pack",    1},
      {"cryogenic-science-pack",       1},
    },
    time        = 60,
  },
  effects       = {{type = "unlock-recipe", recipe = CARGO_MODULE_NAME}},
}

if CARGO_ENABLED then
  data:extend({cargo_item, cargo_recipe, cargo_tech})
end

------------------------------------------------------------
-- Free travel module — removes the per-trip warp fuel fee
------------------------------------------------------------
-- A capstone upgrade: installing it in a portal lets travellers warp without
-- consuming rocket fuel. Its technology is deliberately cheap ("research it for
-- free"); the recipe — a rocket-launch's worth of materials — is the real gate.

local FREE_TRAVEL_NAME = "warp-module-free-travel"
local FREE_TRAVEL_TINT = {r = 0.3, g = 0.85, b = 0.85, a = 1.0}

local free_travel_item = {
  type       = "item",
  name       = FREE_TRAVEL_NAME,
  icons      = {
    {icon = "__interplanetary-portals__/Assets/disk_sprite.png", icon_size = 256, tint = FREE_TRAVEL_TINT},
  },
  subgroup   = "space-related",
  order      = "z[warp-module]-zz-free-travel",
  stack_size = 1,
}

local free_travel_recipe = {
  type            = "recipe",
  name            = FREE_TRAVEL_NAME,
  enabled         = false,
  energy_required = DEV_MODE and 0.5 or 120,
  ingredients     = DEV_MODE and
    {{type = "item", name = "iron-plate", amount = 1}} or
    scale_ingredients({
      {type = "item", name = "processing-unit",       amount = 2000},
      {type = "item", name = "low-density-structure", amount = 2000},
      {type = "item", name = "rocket-fuel",           amount = 500},
      {type = "item", name = "tungsten-carbide",      amount = 1000},
    }, RECIPE_MULT),
  results         = {{type = "item", name = FREE_TRAVEL_NAME, amount = 1}},
}

local free_travel_tech = {
  type          = "technology",
  name          = FREE_TRAVEL_NAME,
  icons         = {
    {icon = "__interplanetary-portals__/Assets/disk_sprite.png", icon_size = 256, tint = FREE_TRAVEL_TINT},
  },
  prerequisites = {PORTAL_NAME},
  unit          = DEV_MODE and {
    count       = 1,
    ingredients = {{"automation-science-pack", 1}},
    time        = 1,
  } or {
    count       = 50,
    ingredients = {
      {"automation-science-pack", 1},
      {"logistic-science-pack",   1},
      {"chemical-science-pack",   1},
      {"space-science-pack",      1},
    },
    time        = 30,
  },
  effects       = {{type = "unlock-recipe", recipe = FREE_TRAVEL_NAME}},
}

data:extend({free_travel_item, free_travel_recipe, free_travel_tech})

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
