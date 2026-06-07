-- data.lua — factorio-puppy
-- Defines the puppy unit entity prototype.

require("util")
require("__base__/prototypes/entity/biter-animations")

local PUPPY_NAME = "factorio-puppy-entity"

-- Smaller than a small biter (0.5), our puppy is extra tiny.
local puppy_scale = 0.35
local puppy_tint1 = {0.75, 0.55, 0.40, 1}   -- warm brown body
local puppy_tint2 = {0.90, 0.70, 0.55, 0.7}  -- light tan highlights

local puppy_entity = {
  type = "unit",
  name = PUPPY_NAME,

  icon      = "__base__/graphics/icons/small-biter.png",
  icon_size = 64,

  flags = {"not-on-map", "not-repairable"},

  -- High HP + near-invulnerable resistances so stray bullets can't kill it.
  max_health       = 1000,
  healing_per_tick = 1,
  resistances = {
    { type = "physical",  percent = 90 },
    { type = "explosion", percent = 90 },
    { type = "fire",      percent = 90 },
    { type = "laser",     percent = 90 },
    { type = "electric",  percent = 90 },
    { type = "poison",    percent = 90 },
    { type = "impact",    percent = 90 },
  },

  -- Small collision box; empty layer mask so it phases through buildings/terrain.
  collision_box  = {{ -0.2, -0.2 }, { 0.2, 0.2 }},
  selection_box  = {{ -0.4, -0.4 }, { 0.4, 0.4 }},
  collision_mask = { layers = {} },

  -- Fast enough to keep up with an early/mid-game player (base ~0.15).
  -- Late-game exoskeleton speeds are handled by teleport fallback in control.lua.
  movement_speed     = 0.35,
  distance_per_frame = 0.15,
  distraction_cooldown = 300,

  -- Critical: prevent the unit AI from doing unwanted things.
  ai_settings = {
    destroy_when_commands_fail    = false,  -- don't self-destruct on bad pathfind
    allow_try_return_to_spawner   = false,  -- FIXES "running away" — no spawner to return to
  },

  has_belt_immunity          = true,
  absorptions_to_join_attack = {},
  vision_distance            = 0,   -- don't alert enemy nests

  -- No loot or corpse: puppy simply vanishes on death.
  loot = {},

  -- Animations from the base game biter sprite helpers (multi-file sheets).
  run_animation = biterrunanimation(puppy_scale, puppy_tint1, puppy_tint2),

  -- attack_parameters is mandatory for unit type even with zero damage.
  attack_target_mask = { layers = {} },
  attack_parameters = {
    type          = "projectile",
    ammo_category = "melee",
    cooldown      = 9999,
    range         = 0,
    animation     = biterattackanimation(puppy_scale, puppy_tint1, puppy_tint2),
    ammo_type = {
      action = {
        type = "direct",
        action_delivery = {
          type = "instant",
          target_effects = {
            type   = "damage",
            damage = { amount = 0, type = "physical" },
          },
        },
      },
    },
  },
}

data:extend({ puppy_entity })
