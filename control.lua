-- control.lua — Interplanetary Portals
-- Handles portal GUI, warp module reading, teleport, and build-limit enforcement.

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local PORTAL_NAME = "interplanetary-portal"

local WARP_MODULES = {
  ["warp-module-nauvis"]   = {surface = "nauvis",   label = "Nauvis"},
  ["warp-module-vulcanus"] = {surface = "vulcanus",  label = "Vulcanus"},
  ["warp-module-fulgora"]  = {surface = "fulgora",   label = "Fulgora"},
  ["warp-module-gleba"]    = {surface = "gleba",     label = "Gleba"},
  ["warp-module-aquilo"]   = {surface = "aquilo",    label = "Aquilo"},
}

local PORTAL_GUI = "portal_frame"

------------------------------------------------------------
-- Initialisation
------------------------------------------------------------

local function init_storage()
  storage.player_portal          = storage.player_portal or {}
  storage.player_managing_portal = storage.player_managing_portal or {}
end

script.on_init(init_storage)
script.on_configuration_changed(init_storage)

------------------------------------------------------------
-- Build limit: one portal per surface
------------------------------------------------------------

local function enforce_build_limit(event)
  local entity = event.entity
  if not entity or not entity.valid or entity.name ~= PORTAL_NAME then return end

  local surface = entity.surface
  if surface.count_entities_filtered{name = PORTAL_NAME} <= 1 then return end

  local pos = entity.position
  entity.destroy()

  local player = event.player_index and game.get_player(event.player_index)
  if player then
    player.insert{name = PORTAL_NAME, count = 1}
    player.create_local_flying_text{
      text     = "Only one portal allowed per planet!",
      position = player.position,
      color    = {r = 1, g = 0.3, b = 0.3},
    }
  else
    surface.spill_item_stack(pos, {name = PORTAL_NAME, count = 1}, true)
  end
end

script.on_event(defines.events.on_built_entity,       enforce_build_limit,
  {{filter = "name", name = PORTAL_NAME}})
script.on_event(defines.events.on_robot_built_entity, enforce_build_limit,
  {{filter = "name", name = PORTAL_NAME}})

------------------------------------------------------------
-- Portal GUI helpers
------------------------------------------------------------

local function get_installed_destinations(portal_entity)
  local inv  = portal_entity.get_inventory(defines.inventory.chest)
  local seen = {}
  local dests = {}
  for i = 1, #inv do
    local stack = inv[i]
    if stack.valid_for_read then
      local mod = WARP_MODULES[stack.name]
      if mod and not seen[mod.surface] then
        seen[mod.surface] = true
        table.insert(dests, {surface = mod.surface, label = mod.label})
      end
    end
  end
  return dests
end

local function close_portal_gui(player)
  storage.player_portal[player.index] = nil
  local frame = player.gui.screen[PORTAL_GUI]
  if frame and frame.valid then
    frame.destroy()
  end
end

local function open_portal_gui(player, entity)
  close_portal_gui(player)

  storage.player_portal[player.index] = {
    surface_name = entity.surface.name,
    position     = entity.position,
  }

  local dests = get_installed_destinations(entity)

  local frame = player.gui.screen.add{
    type      = "frame",
    name      = PORTAL_GUI,
    caption   = "Interplanetary Portal",
    direction = "vertical",
  }
  frame.auto_center = true

  if #dests == 0 then
    frame.add{type = "label", caption = "No warp modules installed."}
  else
    frame.add{type = "label", caption = "Select destination:"}
    for _, dest in ipairs(dests) do
      frame.add{
        type    = "button",
        name    = "portal_travel_" .. dest.surface,
        caption = "Travel to " .. dest.label,
        style   = "confirm_button",
      }
    end
  end

  frame.add{type = "line"}

  local flow = frame.add{type = "flow", direction = "horizontal"}
  flow.style.horizontal_spacing = 8
  flow.add{
    type    = "button",
    name    = "portal_manage_button",
    caption = "Manage Modules",
  }
  flow.add{
    type    = "button",
    name    = "portal_cancel_button",
    caption = "Close",
  }

  player.opened = frame
end

------------------------------------------------------------
-- Intercept portal GUI opens
------------------------------------------------------------

script.on_event(defines.events.on_gui_opened, function(event)
  if not event.entity then return end
  local entity = event.entity
  if entity.name ~= PORTAL_NAME then return end

  local player = game.get_player(event.player_index)

  if player.controller_type ~= defines.controllers.character then
    player.opened = nil
    return
  end

  -- "Manage Modules" was clicked: let the native inventory open once, then clear the flag
  if storage.player_managing_portal[player.index] then
    storage.player_managing_portal[player.index] = nil
    return
  end

  player.opened = nil
  open_portal_gui(player, entity)
end)

------------------------------------------------------------
-- GUI button handlers
------------------------------------------------------------

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not element or not element.valid then return end
  local player = game.get_player(event.player_index)

  if element.name == "portal_cancel_button" then
    close_portal_gui(player)
    return
  end

  if element.name == "portal_manage_button" then
    local pdata = storage.player_portal[player.index]
    if not pdata then return end

    local src_surface = game.surfaces[pdata.surface_name]
    local portal = src_surface and src_surface.find_entity(PORTAL_NAME, pdata.position)

    close_portal_gui(player)  -- clears storage.player_portal before we use portal below

    if portal and portal.valid then
      storage.player_managing_portal[player.index] = true
      player.opened = portal
    end
    return
  end

  -- Travel buttons are named "portal_travel_<surface>"
  local prefix = "portal_travel_"
  if element.name:sub(1, #prefix) ~= prefix then return end
  local dest_planet = element.name:sub(#prefix + 1)

  local pdata = storage.player_portal[player.index]
  if not pdata then return end

  local src_surface = game.surfaces[pdata.surface_name]
  local portal = src_surface and src_surface.find_entity(PORTAL_NAME, pdata.position)
  if not portal or not portal.valid then
    player.create_local_flying_text{
      text     = "Portal is no longer available!",
      position = player.position,
      color    = {r = 1, g = 0.5, b = 0},
    }
    close_portal_gui(player)
    return
  end

  if player.cursor_stack and player.cursor_stack.valid_for_read then
    player.create_local_flying_text{
      text     = "Empty your hands before travelling!",
      position = player.position,
      color    = {r = 1, g = 0.3, b = 0.3},
    }
    return
  end

  if player.surface.name == dest_planet then
    player.create_local_flying_text{
      text     = "You are already on this planet!",
      position = player.position,
      color    = {r = 1, g = 0.5, b = 0},
    }
    return
  end

  close_portal_gui(player)

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
  player.teleport(safe_pos or tp_pos, dest_surface)
  player.create_local_flying_text{
    text     = {"", "Welcome to ", dest_planet, "!"},
    position = safe_pos or tp_pos,
    color    = {r = 0.3, g = 1, b = 0.5},
  }
end)

------------------------------------------------------------
-- Clean up GUI state
------------------------------------------------------------

script.on_event(defines.events.on_gui_closed, function(event)
  if event.element and event.element.valid
    and event.element.name == PORTAL_GUI
  then
    storage.player_portal[event.player_index] = nil
  end
end)

script.on_event(defines.events.on_player_left_game, function(event)
  storage.player_portal[event.player_index]          = nil
  storage.player_managing_portal[event.player_index] = nil
end)
