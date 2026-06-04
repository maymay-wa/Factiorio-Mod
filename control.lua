-- control.lua — Interplanetary Portals
-- Handles:
--   1. Teleportation when a player walks into a portal
--   2. One-per-planet build limit enforcement
--   3. Nauvis portal technology unlock (after any planet discovery)

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local SCAN_INTERVAL     = 30          -- ticks between proximity checks
local COOLDOWN_TICKS    = 180         -- 3 seconds at 60 UPS
local PORTAL_RADIUS     = 5.0         -- detection radius around portal center

-- Portal name → destination planet surface name
local PORTAL_DESTINATIONS = {
  ["nauvis-portal"]    = "nauvis",
  ["vulcanus-portal"]  = "vulcanus",
  ["fulgora-portal"]   = "fulgora",
  ["gleba-portal"]     = "gleba",
  ["aquilo-portal"]    = "aquilo",
}

-- All portal entity names (for build-limit checks — senders only)
local ALL_PORTALS = {
  "nauvis-portal", "vulcanus-portal", "fulgora-portal",
  "gleba-portal", "aquilo-portal",
}


------------------------------------------------------------
-- Initialisation
------------------------------------------------------------

local function init_storage()
  storage.portal_cooldowns = storage.portal_cooldowns or {}     -- player_index → tick
end

script.on_init(init_storage)
script.on_configuration_changed(init_storage)

------------------------------------------------------------
-- Build-limit: only one portal of each type per surface
------------------------------------------------------------

local function enforce_build_limit(event)
  local entity = event.entity
  if not entity or not entity.valid then return end

  local name    = entity.name
  local surface = entity.surface

  local is_portal = PORTAL_DESTINATIONS[name] ~= nil
  if not is_portal then return end

  -- Count how many of this entity already exist on this surface
  local count = surface.count_entities_filtered{name = name}
  -- count includes the one just built, so limit is > 1
  if count > 1 then
    local pos = entity.position
    entity.destroy()
    -- Return the item: to the player if player-built, spill to ground if robot-built
    local player = event.player_index and game.get_player(event.player_index)
    if player then
      player.insert{name = name, count = 1}
      player.create_local_flying_text{
        text = {"", "Only one ", name, " allowed per planet!"},
        position = player.position,
        color = {r = 1, g = 0.3, b = 0.3},
      }
    else
      surface.spill_item_stack(pos, {name = name, count = 1}, true)
    end
  end
end

script.on_event(defines.events.on_built_entity, enforce_build_limit)
script.on_event(defines.events.on_robot_built_entity, enforce_build_limit)

------------------------------------------------------------
-- Teleportation on proximity
------------------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
  if event.tick % SCAN_INTERVAL ~= 0 then return end

  for _, player in pairs(game.connected_players) do
    if player.character and player.character.valid then

      -- Check cooldown
      local cd = storage.portal_cooldowns[player.index]
      if cd and event.tick < cd then
        goto continue
      end

      -- Search for portal entities near the player
      local nearby = player.surface.find_entities_filtered{
        name     = ALL_PORTALS,
        position = player.position,
        radius   = PORTAL_RADIUS,
      }

      for _, portal in pairs(nearby) do
        local dest_planet = PORTAL_DESTINATIONS[portal.name]
        if not dest_planet then goto next_portal end

        -- Don't teleport if already on the destination surface
        if player.surface.name == dest_planet then goto next_portal end

        -- Ensure the destination surface exists
        local dest_surface
        if game.planets[dest_planet] then
          dest_surface = game.planets[dest_planet].create_surface()
        elseif game.surfaces[dest_planet] then
          dest_surface = game.surfaces[dest_planet]
        end

        if not dest_surface then
          player.create_local_flying_text{
            text = "Destination planet not available!",
            position = player.position,
            color = {r = 1, g = 0.5, b = 0},
          }
          storage.portal_cooldowns[player.index] = event.tick + COOLDOWN_TICKS
          goto next_portal
        end

        local tp_pos
        local cargo_pads = dest_surface.find_entities_filtered{name = "cargo-landing-pad"}
        if #cargo_pads > 0 then
          tp_pos = {x = cargo_pads[1].position.x, y = cargo_pads[1].position.y}
        else
          tp_pos = {x = 0, y = 0}
        end

        -- Offset slightly so the player doesn't land inside the entity
        tp_pos.x = tp_pos.x + 3
        tp_pos.y = tp_pos.y + 3

        -- Find a safe non-colliding position
        local safe_pos = dest_surface.find_non_colliding_position(
          "character", tp_pos, 10, 0.5
        )

        if safe_pos then
          player.teleport(safe_pos, dest_surface)
          player.create_local_flying_text{
            text = {"", "Welcome to ", dest_planet, "!"},
            position = safe_pos,
            color = {r = 0.3, g = 1, b = 0.5},
          }
        else
          player.teleport(tp_pos, dest_surface)
        end

        -- Set cooldown
        storage.portal_cooldowns[player.index] = event.tick + COOLDOWN_TICKS
        break  -- only teleport once per scan

        ::next_portal::
      end

      ::continue::
    end
  end
end)


------------------------------------------------------------
-- Clean up cooldowns when a player disconnects
------------------------------------------------------------

script.on_event(defines.events.on_player_left_game, function(event)
  storage.portal_cooldowns[event.player_index] = nil
end)