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

-- When installed in a portal, lets travellers carry their inventory through
-- instead of having to empty it first. Not a destination, so it's deliberately
-- absent from WARP_MODULES.
local CARGO_MODULE = "warp-module-cargo"

local PORTAL_GUI = "portal_frame"

------------------------------------------------------------
-- Initialisation
------------------------------------------------------------

local function init_storage()
  storage.player_portal          = storage.player_portal or {}
  storage.player_managing_portal = storage.player_managing_portal or {}
  storage.portal_renders         = storage.portal_renders or {}
  storage.teleporting            = storage.teleporting or {}
end

local function create_portal_animation(entity)
  local render_obj = rendering.draw_animation{
    animation    = "portal-animation",
    surface      = entity.surface,
    target       = entity,
    render_layer = "higher-object-above",
  }
  storage.portal_renders[entity.unit_number] = render_obj
end

local function restore_portal_animations()
  for _, surface in pairs(game.surfaces) do
    for _, entity in pairs(surface.find_entities_filtered{name = PORTAL_NAME}) do
      local existing = storage.portal_renders[entity.unit_number]
      if not existing or not existing.valid then
        create_portal_animation(entity)
      end
    end
  end
end

script.on_init(init_storage)
script.on_configuration_changed(function()
  init_storage()
  restore_portal_animations()
end)

------------------------------------------------------------
-- Portal animation cleanup
------------------------------------------------------------

local function cleanup_portal_render(event)
  local unit_number = event.entity and event.entity.unit_number
  if not unit_number then return end
  local render_obj = storage.portal_renders[unit_number]
  if render_obj and render_obj.valid then
    render_obj.destroy()
  end
  storage.portal_renders[unit_number] = nil
end

script.on_event(defines.events.on_player_mined_entity, cleanup_portal_render,
  {{filter = "name", name = PORTAL_NAME}})
script.on_event(defines.events.on_robot_mined_entity, cleanup_portal_render,
  {{filter = "name", name = PORTAL_NAME}})
script.on_event(defines.events.on_entity_died, cleanup_portal_render,
  {{filter = "name", name = PORTAL_NAME}})

------------------------------------------------------------
-- Teleport screen effect
------------------------------------------------------------
--
-- A 5-second sequence driven by on_tick:
--   ticks   0..90   fade a dark vignette + swirling vortex IN  (1.5s)
--   ticks  90..150  hold at full intensity                     (1.0s)
--   tick     150    perform the actual teleport, rebuild overlay on destination
--   ticks 150..300  fade the overlay back OUT                  (2.5s)
-- The overlay is anchored to the player's character, so it stays
-- screen-centred even if they move, and is only drawn for that player.

local TP_FADE_IN  = 90
local TP_TELEPORT = 150
local TP_TOTAL    = 300

local TP_DARK_MAX  = 0.92
local TP_DARK_RGB  = {r = 0.02, g = 0.0, b = 0.08}

local function draw_teleport_overlay(player, alpha)
  local char = player.character
  if not char then return {} end
  local surface = player.surface
  local dark = rendering.draw_rectangle{
    color        = {r = TP_DARK_RGB.r, g = TP_DARK_RGB.g, b = TP_DARK_RGB.b, a = alpha},
    filled       = true,
    left_top     = {entity = char, offset = {-80, -80}},
    right_bottom = {entity = char, offset = { 80,  80}},
    surface      = surface,
    players      = {player},
    render_layer = "higher-object-above",
  }
  local swirl = rendering.draw_animation{
    animation       = "portal-animation",
    surface         = surface,
    target          = char,
    x_scale         = 7,
    y_scale         = 7,
    animation_speed = 2,
    tint            = {r = 1, g = 1, b = 1, a = alpha},
    players         = {player},
    render_layer    = "higher-object-above",
  }
  return {dark = dark, swirl = swirl}
end

local function set_overlay_alpha(renders, dark_a, swirl_a)
  if renders.dark and renders.dark.valid then
    renders.dark.color = {r = TP_DARK_RGB.r, g = TP_DARK_RGB.g, b = TP_DARK_RGB.b, a = dark_a}
  end
  if renders.swirl and renders.swirl.valid then
    renders.swirl.color = {r = 1, g = 1, b = 1, a = swirl_a}
  end
end

local function destroy_overlay(renders)
  if renders.dark and renders.dark.valid then renders.dark.destroy() end
  if renders.swirl and renders.swirl.valid then renders.swirl.destroy() end
end

local function start_teleport(player, dest_surface, dest_pos, dest_planet)
  storage.teleporting[player.index] = {
    t                 = 0,
    dest_surface_name = dest_surface.name,
    dest_pos          = dest_pos,
    dest_planet       = dest_planet,
    renders           = draw_teleport_overlay(player, 0),
  }
end

local function drive_teleports()
  if next(storage.teleporting) == nil then return end

  for player_index, tp in pairs(storage.teleporting) do
    local player = game.get_player(player_index)
    if not player or not player.valid then
      storage.teleporting[player_index] = nil
    else
      tp.t = tp.t + 1

      if tp.t <= TP_FADE_IN then
        -- Dark vignette ramps steadily to black; the swirl rises then falls
        -- so it has fully vanished by the time the screen is black.
        local f      = tp.t / TP_FADE_IN
        local half   = TP_FADE_IN / 2
        local swirl_a = (tp.t <= half) and (tp.t / half) or (1 - (tp.t - half) / half)
        set_overlay_alpha(tp.renders, TP_DARK_MAX * f, swirl_a)

      elseif tp.t < TP_TELEPORT then
        set_overlay_alpha(tp.renders, TP_DARK_MAX, 0)

      elseif tp.t == TP_TELEPORT then
        destroy_overlay(tp.renders)
        local dest_surface = game.surfaces[tp.dest_surface_name]
        if dest_surface and dest_surface.valid then
          player.teleport(tp.dest_pos, dest_surface)
        end
        tp.renders = draw_teleport_overlay(player, TP_DARK_MAX)
        set_overlay_alpha(tp.renders, TP_DARK_MAX, 0)

      else
        local f = (tp.t - TP_TELEPORT) / (TP_TOTAL - TP_TELEPORT)
        local a = 1 - f
        set_overlay_alpha(tp.renders, TP_DARK_MAX * a, 0)
        if tp.t >= TP_TOTAL then
          destroy_overlay(tp.renders)
          storage.teleporting[player_index] = nil
          player.create_local_flying_text{
            text     = {"", "Welcome to ", tp.dest_planet, "!"},
            position = player.position,
            color    = {r = 0.3, g = 1, b = 0.5},
          }
        end
      end
    end
  end
end

script.on_event(defines.events.on_tick, drive_teleports)

------------------------------------------------------------
-- Build limit: one portal per surface
------------------------------------------------------------

local function enforce_build_limit(event)
  local entity = event.entity
  if not entity or not entity.valid or entity.name ~= PORTAL_NAME then return end

  local surface = entity.surface
  if surface.count_entities_filtered{name = PORTAL_NAME} <= 1 then
    create_portal_animation(entity)
    return
  end

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

local function portal_allows_cargo(portal_entity)
  local inv = portal_entity.get_inventory(defines.inventory.chest)
  for i = 1, #inv do
    local stack = inv[i]
    if stack.valid_for_read and stack.name == CARGO_MODULE then
      return true
    end
  end
  return false
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

  -- A cargo warp module in the portal lets the traveller bring everything with them.
  if not portal_allows_cargo(portal) then
    local main_inv = player.get_main_inventory()
    local ammo_inv = player.get_inventory(defines.inventory.character_ammo)
    local holding_items =
      (player.cursor_stack and player.cursor_stack.valid_for_read)
      or player.cursor_ghost
      or (main_inv and not main_inv.is_empty())
      or (ammo_inv and not ammo_inv.is_empty())

    if holding_items then
      player.create_local_flying_text{
        text     = "Empty your inventory before travelling, or install a Cargo Warp Module!",
        position = player.position,
        color    = {r = 1, g = 0.3, b = 0.3},
      }
      return
    end
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

  if storage.teleporting[player.index] then return end  -- already mid-teleport
  start_teleport(player, dest_surface, safe_pos or tp_pos, dest_planet)
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
  local tp = storage.teleporting[event.player_index]
  if tp then
    destroy_overlay(tp.renders)
    storage.teleporting[event.player_index] = nil
  end
end)
