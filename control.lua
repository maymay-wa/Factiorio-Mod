-- control.lua — Interplanetary Portals
-- Handles:
--   1. Click-to-open portal GUI and teleport on button press
--   2. One-per-planet build limit enforcement (players and robots)

------------------------------------------------------------
-- Constants
------------------------------------------------------------

-- Portal entity name → destination planet surface name
local PORTAL_DESTINATIONS = {
  ["nauvis-portal"]   = "nauvis",
  ["vulcanus-portal"] = "vulcanus",
  ["fulgora-portal"]  = "fulgora",
  ["gleba-portal"]    = "gleba",
  ["aquilo-portal"]   = "aquilo",
}

local ALL_PORTALS = {
  "nauvis-portal", "vulcanus-portal", "fulgora-portal",
  "gleba-portal", "aquilo-portal",
}

local PORTAL_GUI = "portal_frame"

------------------------------------------------------------
-- Initialisation
------------------------------------------------------------

local function init_storage()
  -- player_index → {portal_name, surface_name, position}
  storage.player_portal = storage.player_portal or {}
end

script.on_init(init_storage)
script.on_configuration_changed(init_storage)

------------------------------------------------------------
-- Build-limit: one portal of each type per surface
------------------------------------------------------------

local portal_filters = {}
for _, pname in ipairs(ALL_PORTALS) do
  table.insert(portal_filters, {filter = "name", name = pname})
end

local function enforce_build_limit(event)
  local entity = event.entity
  if not entity or not entity.valid then return end

  local name    = entity.name
  local surface = entity.surface

  if not PORTAL_DESTINATIONS[name] then return end

  local count = surface.count_entities_filtered{name = name}
  if count > 1 then
    local pos = entity.position
    entity.destroy()
    local player = event.player_index and game.get_player(event.player_index)
    if player then
      player.insert{name = name, count = 1}
      player.create_local_flying_text{
        text     = {"", "Only one ", name, " allowed per planet!"},
        position = player.position,
        color    = {r = 1, g = 0.3, b = 0.3},
      }
    else
      -- Robot-built: spill item so logistics network picks it back up
      surface.spill_item_stack(pos, {name = name, count = 1}, true)
    end
  end
end

script.on_event(defines.events.on_built_entity,       enforce_build_limit, portal_filters)
script.on_event(defines.events.on_robot_built_entity, enforce_build_limit, portal_filters)

------------------------------------------------------------
-- Portal GUI helpers
------------------------------------------------------------

local function close_portal_gui(player)
  storage.player_portal[player.index] = nil
  local frame = player.gui.screen[PORTAL_GUI]
  if frame and frame.valid then
    frame.destroy()
  end
end

local function open_portal_gui(player, entity)
  close_portal_gui(player)

  local dest = PORTAL_DESTINATIONS[entity.name]

  storage.player_portal[player.index] = {
    portal_name  = entity.name,
    surface_name = entity.surface.name,
    position     = entity.position,
  }

  local frame = player.gui.screen.add{
    type      = "frame",
    name      = PORTAL_GUI,
    caption   = "Interplanetary Portal",
    direction = "vertical",
  }
  frame.auto_center = true

  frame.add{type = "label", caption = {"", "Destination: ", dest}}

  local flow = frame.add{type = "flow", direction = "horizontal"}
  flow.style.horizontal_spacing = 8
  flow.add{
    type    = "button",
    name    = "portal_travel_button",
    caption = {"", "Travel to ", dest},
    style   = "confirm_button",
  }
  flow.add{
    type    = "button",
    name    = "portal_cancel_button",
    caption = "Cancel",
  }

  -- Register frame as the opened GUI so Escape closes it
  player.opened = frame
end

------------------------------------------------------------
-- Open portal GUI when player right-clicks a portal
------------------------------------------------------------

script.on_event(defines.events.on_gui_opened, function(event)
  if not event.entity then return end
  local entity = event.entity
  if not PORTAL_DESTINATIONS[entity.name] then return end

  local player = game.get_player(event.player_index)
  player.opened = nil  -- dismiss native container GUI immediately

  open_portal_gui(player, entity)
end)

------------------------------------------------------------
-- Handle travel / cancel button clicks
------------------------------------------------------------

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not element or not element.valid then return end
  local player = game.get_player(event.player_index)

  if element.name == "portal_cancel_button" then
    close_portal_gui(player)
    return
  end

  if element.name ~= "portal_travel_button" then return end

  local data = storage.player_portal[player.index]
  if not data then return end

  -- Must have empty hands to travel (GUI stays open so they can retry)
  if player.cursor_stack and player.cursor_stack.valid_for_read then
    player.create_local_flying_text{
      text     = "Empty your hands before travelling!",
      position = player.position,
      color    = {r = 1, g = 0.3, b = 0.3},
    }
    return
  end

  -- Verify the portal entity is still there
  local src_surface = game.surfaces[data.surface_name]
  local portal = src_surface and src_surface.find_entity(data.portal_name, data.position)
  if not portal or not portal.valid then
    player.create_local_flying_text{
      text     = "Portal is no longer available!",
      position = player.position,
      color    = {r = 1, g = 0.5, b = 0},
    }
    close_portal_gui(player)
    return
  end

  close_portal_gui(player)

  local dest_planet = PORTAL_DESTINATIONS[data.portal_name]

  if player.surface.name == dest_planet then
    player.create_local_flying_text{
      text     = "You are already on this planet!",
      position = player.position,
      color    = {r = 1, g = 0.5, b = 0},
    }
    return
  end

  local dest_surface
  if game.planets[dest_planet] then
    dest_surface = game.planets[dest_planet].create_surface()
  elseif game.surfaces[dest_planet] then
    dest_surface = game.surfaces[dest_planet]
  end

  if not dest_surface then
    player.create_local_flying_text{
      text     = "Destination planet not available!",
      position = player.position,
      color    = {r = 1, g = 0.5, b = 0},
    }
    return
  end

  local cargo_pads = dest_surface.find_entities_filtered{name = "cargo-landing-pad"}
  local tp_pos
  if #cargo_pads > 0 then
    tp_pos = {x = cargo_pads[1].position.x + 3, y = cargo_pads[1].position.y + 3}
  else
    tp_pos = {x = 3, y = 3}
  end

  local safe_pos = dest_surface.find_non_colliding_position("character", tp_pos, 10, 0.5)
  if safe_pos then
    player.teleport(safe_pos, dest_surface)
    player.create_local_flying_text{
      text     = {"", "Welcome to ", dest_planet, "!"},
      position = safe_pos,
      color    = {r = 0.3, g = 1, b = 0.5},
    }
  else
    player.teleport(tp_pos, dest_surface)
  end
end)

------------------------------------------------------------
-- Clean up GUI state
------------------------------------------------------------

-- Fires when player closes our frame via Escape or the X button
script.on_event(defines.events.on_gui_closed, function(event)
  if event.element and event.element.valid
    and event.element.name == PORTAL_GUI
  then
    storage.player_portal[event.player_index] = nil
  end
end)

script.on_event(defines.events.on_player_left_game, function(event)
  storage.player_portal[event.player_index] = nil
end)
