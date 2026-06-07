-- control.lua — factorio-puppy
-- Uses the engine's native unit command system for smooth movement
-- instead of manual teleportation.

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local PUPPY_NAME      = "factorio-puppy-entity"
local FOLLOW_RADIUS   = 3.0    -- tiles: puppy idles when this close
local UPDATE_INTERVAL = 6      -- ticks between movement checks (~10/sec)
local TELEPORT_DIST   = 15     -- tiles: teleport if further than this
local CMD_RETHINK     = 2.0    -- tiles: re-issue move command when player moved this far
local RESPAWN_DELAY   = 180    -- ticks (~3 s) before respawning after death
local WANDER_RADIUS   = 1.5    -- tiles: gentle wander range when idle
local SPAWN_OFFSET    = { x = 2, y = 0 }

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function dist(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function is_space_surface(surface)
  return surface.platform ~= nil
end

------------------------------------------------------------
-- Storage initialisation
------------------------------------------------------------
-- storage.puppies[player_index] = {
--   entity       : LuaEntity | nil
--   respawn_tick : number | nil
--   in_space     : boolean
--   last_cmd_pos : {x,y} | nil    -- last position we commanded the puppy to walk to
--   idle         : boolean         -- true when puppy is wandering near the player
-- }

local function make_entry(overrides)
  local e = {
    entity       = nil,
    respawn_tick = nil,
    in_space     = false,
    last_cmd_pos = nil,
    idle         = false,
  }
  if overrides then
    for k, v in pairs(overrides) do e[k] = v end
  end
  return e
end

local function init_storage()
  storage.puppies = storage.puppies or {}
end

--- Schedule a puppy for every connected player who doesn't have one yet.
--- Called on first load AND whenever mod config changes (e.g. adding the mod
--- to an existing save).
local function ensure_puppies_for_all_players()
  init_storage()
  for _, player in pairs(game.players) do
    local entry = storage.puppies[player.index]
    if not entry then
      -- Brand-new player for this mod — schedule a spawn.
      if player.connected and player.character and player.character.valid
         and not is_space_surface(player.surface) then
        storage.puppies[player.index] = make_entry{
          respawn_tick = game.tick + 60,
        }
      end
    else
      -- Existing entry — re-validate the entity reference.
      if entry.entity and not entry.entity.valid then
        entry.entity = nil
        if not entry.in_space then
          entry.respawn_tick = game.tick + RESPAWN_DELAY
        end
      end
      entry.last_cmd_pos = nil
      entry.idle = false
    end
  end
end

script.on_init(ensure_puppies_for_all_players)
script.on_configuration_changed(ensure_puppies_for_all_players)

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

  -- Destroy any stale entity before creating a new one.
  local existing = storage.puppies[player.index]
  if existing and existing.entity and existing.entity.valid then
    existing.entity.destroy()
  end

  local entity = surface.create_entity{
    name     = PUPPY_NAME,
    position = safe,
    -- "neutral" force: at ceasefire with everyone by default,
    -- so biters, turrets, and spitters all ignore the puppy.
    force    = "neutral",
  }
  if not entity or not entity.valid then return nil end

  storage.puppies[player.index] = make_entry{ entity = entity }
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
-- Command helpers — smooth native movement
------------------------------------------------------------

local function cmd_follow(puppy, target_pos, entry)
  puppy.set_command{
    type        = defines.command.go_to_location,
    destination = target_pos,
    radius      = FOLLOW_RADIUS,
    distraction = defines.distraction.none,
    pathfind_flags = {
      allow_paths_through_own_military = true,
      prefer_straight_paths            = true,
    },
  }
  entry.last_cmd_pos = { x = target_pos.x, y = target_pos.y }
  entry.idle = false
end

local function cmd_wander(puppy, entry)
  puppy.set_command{
    type            = defines.command.wander,
    radius          = WANDER_RADIUS,
    wander_in_group = false,
    distraction     = defines.distraction.none,
  }
  entry.idle = true
  entry.last_cmd_pos = nil
end

------------------------------------------------------------
-- Movement — called every UPDATE_INTERVAL ticks
------------------------------------------------------------

local function update_movement(player, entry)
  local puppy = entry.entity
  if not puppy or not puppy.valid then return end
  if not player.character or not player.character.valid then return end
  if puppy.surface ~= player.surface then return end

  local pp = player.character.position
  local ep = puppy.position
  local d  = dist(pp, ep)

  -- 1) Too far behind → teleport near the player, then walk the last bit
  if d > TELEPORT_DIST then
    local offset = { x = pp.x + 2, y = pp.y }
    local safe = puppy.surface.find_non_colliding_position(PUPPY_NAME, offset, 5, 0.5) or offset
    puppy.teleport(safe)
    cmd_follow(puppy, pp, entry)
    return
  end

  -- 2) Close enough → gentle wander
  if d <= FOLLOW_RADIUS then
    if not entry.idle then
      cmd_wander(puppy, entry)
    end
    return
  end

  -- 3) Medium distance → walk toward the player (only re-issue if player moved enough)
  if entry.idle then
    -- Was idling, player moved away — start chasing
    cmd_follow(puppy, pp, entry)
    return
  end

  if entry.last_cmd_pos then
    if dist(pp, entry.last_cmd_pos) < CMD_RETHINK then
      return  -- player hasn't moved much; let the current command finish
    end
  end

  cmd_follow(puppy, pp, entry)
end

------------------------------------------------------------
-- Event: AI command completed — re-evaluate immediately
------------------------------------------------------------

script.on_event(defines.events.on_ai_command_completed, function(event)
  for player_index, entry in pairs(storage.puppies) do
    if entry.entity and entry.entity.valid
       and entry.entity.unit_number == event.unit_number then
      -- Reset state so the next tick-check re-evaluates
      entry.last_cmd_pos = nil
      entry.idle = false
      break
    end
  end
end)

------------------------------------------------------------
-- Player joined / created
------------------------------------------------------------

local function schedule_spawn(player_index)
  local existing = storage.puppies[player_index]
  if existing and existing.entity and existing.entity.valid then return end
  storage.puppies[player_index] = make_entry{
    respawn_tick = game.tick + 60,   -- 1 sec delay for character to be placed
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
        entry.entity = nil
        entry.respawn_tick = event.tick + RESPAWN_DELAY
        entry.last_cmd_pos = nil
        entry.idle = false
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
    entry = make_entry()
    storage.puppies[event.player_index] = entry
  end

  if is_space_surface(player.surface) then
    -- Going to space: remove the puppy.
    if entry.entity and entry.entity.valid then
      entry.entity.destroy()
      entry.entity = nil
    end
    entry.in_space     = true
    entry.respawn_tick = nil
    entry.last_cmd_pos = nil
    entry.idle         = false

  else
    -- Landing on a planet: move or schedule respawn.
    if entry.entity and entry.entity.valid then
      local ok = entry.entity.teleport(player.position, player.surface)
      if not ok then
        entry.entity.destroy()
        entry.entity = nil
      end
    end
    entry.in_space     = false
    entry.last_cmd_pos = nil
    entry.idle         = false
    if not entry.entity or not entry.entity.valid then
      entry.respawn_tick = entry.respawn_tick or (game.tick + 60)
    end
  end
end)

------------------------------------------------------------
-- Tick loop — smooth movement + respawn
------------------------------------------------------------

script.on_nth_tick(UPDATE_INTERVAL, function(event)
  for player_index, entry in pairs(storage.puppies) do
    local player = game.get_player(player_index)

    if not player or not player.valid then
      despawn_puppy(player_index)

    elseif entry.in_space then
      -- No puppy in space; nothing to do.

    elseif entry.entity and entry.entity.valid then
      update_movement(player, entry)

    elseif entry.respawn_tick and event.tick >= entry.respawn_tick then
      local new_puppy = spawn_puppy(player)
      if not new_puppy then
        entry.respawn_tick = event.tick + RESPAWN_DELAY
      end
    end
  end
end)
