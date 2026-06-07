-- data.lua — factorio-puppy
-- Defines the puppy unit entity prototype.

local PUPPY_NAME = "factorio-puppy-entity"

local puppy_entity = {
  type = "unit",
  name = PUPPY_NAME,

  icon      = "__base__/graphics/icons/compilatron.png",
  icon_size = 64,

  flags = {"not-on-map", "not-repairable"},

  -- High HP + near-invulnerable resistances so stray bullets can't kill it.
  max_health    = 1000,
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

  -- Small collision box; empty layer mask so it phases through terrain.
  collision_box  = {{ -0.2, -0.2 }, { 0.2, 0.2 }},
  selection_box  = {{ -0.4, -0.4 }, { 0.4, 0.4 }},
  collision_mask = { layers = {} },

  -- movement_speed is the prototype baseline; actual movement is driven by
  -- script teleportation scaled to the player's current speed modifier.
  movement_speed = 0.18,
  distance_from_target_when_stopped = 1.5,

  has_belt_immunity    = true,
  pollution_to_join_attack = 0,
  -- vision_distance = 0 prevents the unit from alerting enemy nests.
  vision_distance = 0,

  -- No loot or corpse: puppy simply vanishes on death.
  loot = {},

  -- run_animation uses the small-biter sprite sheet; well-documented dimensions.
  run_animation = {
    type = "rotated-animation",
    direction_count = 8,
    animation = {
      filename        = "__base__/graphics/entity/small-biter/small-biter-run.png",
      width           = 102,
      height          = 80,
      frame_count     = 7,
      line_length     = 7,
      animation_speed = 0.4,
      scale           = 0.4,
      shift           = { 0, -0.2 },
    },
  },

  -- attack_parameters is mandatory for the unit type even with zero damage.
  attack_target_mask = { layers = {} },
  attack_parameters = {
    type          = "projectile",
    ammo_category = "melee",
    cooldown      = 9999,
    range         = 0,
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
