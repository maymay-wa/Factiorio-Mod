-- control.lua — factorio-puppy

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local PUPPY_NAME      = "factorio-puppy-entity"
local FOLLOW_RADIUS   = 2.0   -- tiles: puppy stops this far from the player
local FOLLOW_INTERVAL = 20    -- ticks between movement updates
local RESPAWN_DELAY   = 180   -- ticks (~3 s) before respawning after death
local BASE_PUPPY_SPEED = 0.18 -- tiles/tick at base player speed (player base ≈ 0.15)
local SPAWN_OFFSET    = { x = 2, y = 0 }

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function is_space_surface(surface)
  -- Space platform surfaces have surface.platform set; planet surfaces do not.
  return surface.platform ~= nil
end

------------------------------------------------------------
-- Storage initialisation
------------------------------------------------------------
-- storage.puppies[player_index] = {
--   entity       : LuaEntity | nil
--   respawn_tick : number | nil
--   in_space     : boolean
-- }

local function init_storage()
  storage.puppies = storage.puppies or {}
end

script.on_init(init_storage)

script.on_configuration_changed(function()
  init_storage()
  -- Re-validate entity references after a mod update or save/load.
  for player_index, entry in pairs(storage.puppies) do
    if entry.entity and not entry.entity.valid then
      entry.entity = nil
      if not entry.in_space then
        entry.respawn_tick = game.tick + RESPAWN_DELAY
      end
    end
  end
end)

------------------------------------------------------------
-- Spawning / despawning
------------------------------------------------------------

local function spawn_puppy(player)
  if not player or not player.valid then return end
  if not player.character or not player.character.valid then return end

  local surface = player.surface
  local pos     = player.position
  local target  = { x = pos.x + SPAWN_OFFSET.x, y = pos.y + SPAWN_OFFSET.y }
  local safe    = surface.find_non_colliding_position(PUPPY_NAME, target, 5, 0.5) or target

  local entity = surface.create_entity{
    name     = PUPPY_NAME,
    position = safe,
    -- "neutral" force is at ceasefire with all forces by default,
    -- so biters and spitters will never target the puppy.
    force    = "neutral",
  }
  if not entity or not entity.valid then return nil end

  -- Destroy any stale entity before replacing.
  local existing = storage.puppies[player.index]
  if existing and existing.entity and existing.entity.valid then
    existing.entity.destroy()
  end

  storage.puppies[player.index] = { entity = entity, respawn_tick = nil, in_space = false }
  return entity
end

local function despawn_puppy(player_index)
  local entry = storage.puppies[player_index]
  if not entry then return end
  if entry.entity and entry.entity.valid then
    entry.entity.destroy()
  end
  storage.puppies[player_index] = nil
end

------------------------------------------------------------
-- Movement (manual teleport for runtime speed scaling)
------------------------------------------------------------

local function move_puppy_toward_player(player, entry)
  local puppy = entry.entity
  if not puppy or not puppy.valid then return end
  if not player.character or not player.character.valid then return end
  if puppy.surface ~= player.surface then return end

  local pp   = player.character.position
  local ep   = puppy.position
  local dx   = pp.x - ep.x
  local dy   = pp.y - ep.y
  local dist = math.sqrt(dx * dx + dy * dy)

  if dist <= FOLLOW_RADIUS then return end

  -- Scale speed with the player's current running speed modifier so the puppy
  -- keeps up even with late-game exoskeletons.
  local modifier       = player.character_running_speed_modifier
  local effective_speed = BASE_PUPPY_SPEED * math.max(1, 1 + modifier)
  local max_move       = effective_speed * FOLLOW_INTERVAL
  local step           = math.min(max_move, dist - FOLLOW_RADIUS)

  puppy.teleport({
    x = ep.x + (dx / dist) * step,
    y = ep.y + (dy / dist) * step,
  })
end

------------------------------------------------------------
-- Player joined / created
------------------------------------------------------------

local function schedule_spawn(player_index)
  local existing = storage.puppies[player_index]
  if existing and existing.entity and existing.entity.valid then return end
  storage.puppies[player_index] = {
    entity       = nil,
    -- Wait ~1 second so the character entity is placed before we try to spawn.
    respawn_tick = game.tick + 60,
    in_space     = false,
  }
end

script.on_event(defines.events.on_player_created,     function(e) schedule_spawn(e.player_index) end)
script.on_event(defines.events.on_player_joined_game, function(e) schedule_spawn(e.player_index) end)

------------------------------------------------------------
-- Player left
------------------------------------------------------------

script.on_event(defines.events.on_pre_player_left_game, function(e)
  despawn_puppy(e.player_index)
end)

------------------------------------------------------------
-- Puppy died — schedule respawn
------------------------------------------------------------

script.on_event(
  defines.events.on_entity_died,
  function(event)
    for player_index, entry in pairs(storage.puppies) do
      if entry.entity == event.entity then
        entry.entity      = nil
        entry.respawn_tick = event.tick + RESPAWN_DELAY
        break
      end
    end
  end,
  {{ filter = "name", name = PUPPY_NAME }}
)

------------------------------------------------------------
-- Surface change — space / planet handling
------------------------------------------------------------

script.on_event(defines.events.on_player_changed_surface, function(event)
  local player = game.get_player(event.player_index)
  if not player or not player.valid then return end

  local entry = storage.puppies[event.player_index]
  if not entry then
    entry = { entity = nil, respawn_tick = nil, in_space = false }
    storage.puppies[event.player_index] = entry
  end

  if is_space_surface(player.surface) then
    -- Player launched to a space platform: remove the puppy.
    if entry.entity and entry.entity.valid then
      entry.entity.destroy()
      entry.entity = nil
    end
    entry.in_space     = true
    entry.respawn_tick = nil
  else
    -- Player landed on a planet: schedule a fresh spawn.
    if entry.entity and entry.entity.valid then
      -- Move existing puppy to the new surface.
      local ok = entry.entity.teleport(player.position, player.surface)
      if not ok then
        entry.entity.destroy()
        entry.entity = nil
      end
    end
    entry.in_space     = false
    entry.respawn_tick = entry.respawn_tick or (game.tick + 60)
  end
end)

------------------------------------------------------------
-- Tick loop — movement + respawn
------------------------------------------------------------

script.on_nth_tick(FOLLOW_INTERVAL, function(event)
  for player_index, entry in pairs(storage.puppies) do
    local player = game.get_player(player_index)

    if not player or not player.valid then
      despawn_puppy(player_index)

    elseif entry.in_space then
      -- Puppy doesn't exist in space; nothing to do.

    elseif entry.entity and entry.entity.valid then
      move_puppy_toward_player(player, entry)

    elseif entry.respawn_tick and event.tick >= entry.respawn_tick then
      local new_puppy = spawn_puppy(player)
      if not new_puppy then
        -- Character not ready yet; retry after another delay.
        entry.respawn_tick = event.tick + RESPAWN_DELAY
      end
    end
  end
end)
