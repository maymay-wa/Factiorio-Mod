-- control.lua — Interplanetary Portals
-- Handles portal GUI, warp module reading, teleport, and build-limit enforcement.

------------------------------------------------------------
-- Constants
------------------------------------------------------------

local PORTAL_NAME = "interplanetary-portal"

-- Ordered list of travel destinations, each tied to the warp module that unlocks it.
local DESTINATIONS = {
  {module = "warp-module-nauvis",   surface = "nauvis",   label = "Nauvis"},
  {module = "warp-module-vulcanus", surface = "vulcanus", label = "Vulcanus"},
  {module = "warp-module-fulgora",  surface = "fulgora",  label = "Fulgora"},
  {module = "warp-module-gleba",    surface = "gleba",    label = "Gleba"},
  {module = "warp-module-aquilo",   surface = "aquilo",   label = "Aquilo"},
}

-- When installed in a portal, lets travellers carry their inventory through
-- instead of having to empty it first. Not a destination, so it's deliberately
-- absent from DESTINATIONS.
local CARGO_MODULE = "warp-module-cargo"

-- When installed in a portal, warping no longer consumes the per-trip resource cost.
local FREE_TRAVEL_MODULE = "warp-module-free-travel"

-- Resources consumed from the portal's own inventory on every teleport (scaled by
-- the travel-cost-multiplier setting). A Free Travel Module waives the whole cost.
-- `slots` is how many dedicated, filtered inventory slots to reserve for each.
local WARP_COST = {
  {name = "processing-unit",       amount = 50, slots = 1},
  {name = "low-density-structure", amount = 50, slots = 2},
  {name = "rocket-fuel",           amount = 50, slots = 5},
}

-- Friendly names for the "insufficient resources" warning.
local WARP_COST_LABEL = {
  ["processing-unit"]       = "processing units",
  ["low-density-structure"] = "low density structures",
  ["rocket-fuel"]           = "rocket fuel",
}

-- Whether the cargo module exists this game (mirrors the data-stage setting), so
-- the slot layout lines up with the portal's actual inventory size.
local CARGO_ENABLED = settings.startup["portal-enable-cargo-module"].value

local COLOR_READY    = "[color=#5fd35f]"
local COLOR_MISSING  = "[color=#9e9e9e]"
local COLOR_END      = "[/color]"

-- Custom panel docked onto the portal's native inventory window.
local PORTAL_RELATIVE = "portal_travel_panel"

------------------------------------------------------------
-- Initialisation
------------------------------------------------------------

local function init_storage()
  storage.player_portal  = storage.player_portal or {}
  storage.portal_renders = storage.portal_renders or {}
  storage.teleporting    = storage.teleporting or {}
  storage.warnings       = storage.warnings or {}
end

-- Screen-anchored warning that draws on TOP of the open portal menu (flying text
-- renders in the world, so it gets hidden behind GUI windows).
local WARNING_NAME     = "portal_travel_warning"
local WARNING_DURATION = 180  -- ticks (~3s)

local function show_warning(player, text, color)
  local screen = player.gui.screen
  if screen[WARNING_NAME] then screen[WARNING_NAME].destroy() end

  local frame = screen.add{type = "frame", name = WARNING_NAME}
  frame.style.minimal_width = 460
  frame.style.horizontal_align = "center"

  local label = frame.add{type = "label", caption = text}
  label.style.font       = "default-large-bold"
  label.style.font_color = color or {r = 1, g = 0.4, b = 0.4}
  label.style.single_line   = false
  label.style.maximal_width = 430
  label.style.horizontal_align = "center"

  local res   = player.display_resolution
  local scale = player.display_scale
  frame.location = {x = math.floor((res.width - 460 * scale) / 2), y = math.floor(90 * scale)}

  storage.warnings[player.index] = game.tick + WARNING_DURATION
end

-- Ordered list of items each filtered slot should accept. Anything past the end
-- of this list (the remaining slots) is reserved for warp fuel.
local function portal_filter_layout()
  local layout = {}
  for _, dest in ipairs(DESTINATIONS) do
    layout[#layout + 1] = dest.module
  end
  if CARGO_ENABLED then layout[#layout + 1] = CARGO_MODULE end
  layout[#layout + 1] = FREE_TRAVEL_MODULE
  for _, c in ipairs(WARP_COST) do
    for _ = 1, c.slots do layout[#layout + 1] = c.name end
  end
  return layout
end

-- Give each module and the rocket fuel its own dedicated slot. Snapshot/clear/
-- re-insert so contents settle into their filtered slots even on existing portals.
local function apply_portal_filters(portal)
  local inv = portal.get_inventory(defines.inventory.chest)
  if not inv or not inv.supports_filters() then return end

  local layout   = portal_filter_layout()
  local contents = inv.get_contents()
  inv.clear()
  for i = 1, #inv do
    inv.set_filter(i, layout[i])
  end
  for _, stack in pairs(contents) do
    local inserted = inv.insert{name = stack.name, count = stack.count, quality = stack.quality}
    if inserted < stack.count then
      portal.surface.spill_item_stack{
        position      = portal.position,
        stack         = {name = stack.name, count = stack.count - inserted, quality = stack.quality},
        enable_looted = true,
      }
    end
  end
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
      apply_portal_filters(entity)
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

-- The portal grows brighter as the screen darkens, then fades out. TP_SWIRL_OUT
-- is how many ticks the fade-out lasts; TP_SWIRL_LINGER lets it hang on a touch
-- past the darkest point so it doesn't snap away the instant the screen blacks.
local TP_SWIRL_OUT    = 18
local TP_SWIRL_LINGER = 12
local TP_SWIRL_OFF    = TP_FADE_IN --+ TP_SWIRL_LINGER

local TP_DARK_MAX    = 0.92
local TP_DARK_RGB    = {r = 0.02, g = 0.0, b = 0.08}
-- Half-size (in tiles) of the blackout rectangle. Big enough to cover the whole
-- screen even when fully zoomed out, so the fade isn't just a square in the middle.
local TP_DARK_RADIUS = 250

-- with_swirl controls whether the giant floating portal is drawn. It only
-- belongs to the darken-IN phase; once the screen is black it's destroyed and
-- never recreated, so the destination/fade-out overlay is drawn without it.
local function draw_teleport_overlay(player, alpha, with_swirl)
  local char = player.character
  if not char then return {} end
  local surface = player.surface
  local dark = rendering.draw_rectangle{
    color        = {r = TP_DARK_RGB.r, g = TP_DARK_RGB.g, b = TP_DARK_RGB.b, a = alpha},
    filled       = true,
    left_top     = {entity = char, offset = {-TP_DARK_RADIUS, -TP_DARK_RADIUS}},
    right_bottom = {entity = char, offset = { TP_DARK_RADIUS,  TP_DARK_RADIUS}},
    surface      = surface,
    players      = {player},
    render_layer = "higher-object-above",
  }
  local swirl
  if with_swirl then
    swirl = rendering.draw_animation{
      animation       = "portal-animation",
      surface         = surface,
      target          = char,
      x_scale         = 7,
      y_scale         = 7,
      animation_speed = 2,
      tint            = {r = 1, g = 1, b = 1, a = 0},
      players         = {player},
      render_layer    = "higher-object-above",
    }
  end
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

local function destroy_swirl(renders)
  if renders.swirl and renders.swirl.valid then renders.swirl.destroy() end
  renders.swirl = nil
end

local function destroy_overlay(renders)
  if renders.dark and renders.dark.valid then renders.dark.destroy() end
  destroy_swirl(renders)
end

local function start_teleport(player, dest_surface, dest_pos, dest_planet)
  storage.teleporting[player.index] = {
    t                 = 0,
    dest_surface_name = dest_surface.name,
    dest_pos          = dest_pos,
    dest_planet       = dest_planet,
    renders           = draw_teleport_overlay(player, 0, true),
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

      if tp.t < TP_SWIRL_OFF then
        -- Dark vignette ramps steadily to black (reaching max at TP_FADE_IN, then
        -- holding); the swirl grows brighter as the screen darkens, then fades out,
        -- lingering a touch past the darkest point.
        local dark_a    = TP_DARK_MAX * math.min(tp.t / TP_FADE_IN, 1)
        local out_start = TP_SWIRL_OFF - TP_SWIRL_OUT
        local swirl_a
        if tp.t <= out_start then
          swirl_a = tp.t / out_start
        else
          swirl_a = (TP_SWIRL_OFF - tp.t) / TP_SWIRL_OUT
        end
        set_overlay_alpha(tp.renders, dark_a, swirl_a)

      elseif tp.t == TP_SWIRL_OFF then
        -- Floating portal is fully faded: hard-destroy it so it's truly gone,
        -- not just alpha-zeroed.
        destroy_swirl(tp.renders)
        set_overlay_alpha(tp.renders, TP_DARK_MAX, 0)

      elseif tp.t < TP_TELEPORT then
        set_overlay_alpha(tp.renders, TP_DARK_MAX, 0)

      elseif tp.t == TP_TELEPORT then
        destroy_overlay(tp.renders)
        local dest_surface = game.surfaces[tp.dest_surface_name]
        if dest_surface and dest_surface.valid then
          player.teleport(tp.dest_pos, dest_surface)
        end
        -- No swirl on the destination side; just hold the darkness and fade out.
        tp.renders = draw_teleport_overlay(player, TP_DARK_MAX, false)

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

-- on_tick is registered near the end of the file so it can also refresh open panels.

------------------------------------------------------------
-- Build limit: one portal per surface
------------------------------------------------------------

local function enforce_build_limit(event)
  local entity = event.entity
  if not entity or not entity.valid or entity.name ~= PORTAL_NAME then return end

  local surface = entity.surface
  if surface.count_entities_filtered{name = PORTAL_NAME} <= 1 then
    create_portal_animation(entity)
    apply_portal_filters(entity)
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
    surface.spill_item_stack{
      position      = pos,
      stack         = {name = PORTAL_NAME, count = 1},
      enable_looted = true,
    }
  end
end

script.on_event(defines.events.on_built_entity,       enforce_build_limit,
  {{filter = "name", name = PORTAL_NAME}})
script.on_event(defines.events.on_robot_built_entity, enforce_build_limit,
  {{filter = "name", name = PORTAL_NAME}})

------------------------------------------------------------
-- Portal GUI helpers
------------------------------------------------------------

local function portal_module_count(portal_entity, item_name)
  local inv = portal_entity.get_inventory(defines.inventory.chest)
  return inv and inv.get_item_count(item_name) or 0
end

local function portal_allows_cargo(portal_entity)
  return portal_module_count(portal_entity, CARGO_MODULE) > 0
end

local function portal_allows_free_travel(portal_entity)
  return portal_module_count(portal_entity, FREE_TRAVEL_MODULE) > 0
end

-- A cost amount after the travel-cost-multiplier setting (0 disables travel cost).
local function cost_amount(base)
  return math.max(0, math.floor(base * settings.global["portal-travel-cost-multiplier"].value))
end

-- Does the portal hold a full trip's worth of every cost resource?
local function portal_can_afford(portal)
  local inv = portal.get_inventory(defines.inventory.chest)
  if not inv then return false end
  for _, c in ipairs(WARP_COST) do
    if inv.get_item_count(c.name) < cost_amount(c.amount) then return false end
  end
  return true
end

-- Consume one trip's worth of every cost resource from the portal.
local function charge_warp(portal)
  local inv = portal.get_inventory(defines.inventory.chest)
  if not inv then return end
  for _, c in ipairs(WARP_COST) do
    local amt = cost_amount(c.amount)
    if amt > 0 then inv.remove{name = c.name, count = amt} end
  end
end

-- Human-readable list of the per-trip cost, e.g. "50 processing units, ...".
local function warp_cost_text()
  local parts = {}
  for _, c in ipairs(WARP_COST) do
    parts[#parts + 1] = cost_amount(c.amount) .. " " .. (WARP_COST_LABEL[c.name] or c.name)
  end
  return table.concat(parts, ", ")
end

-- Resolve the portal entity the player currently has open from stored coords.
local function get_player_portal(player)
  local pdata = storage.player_portal[player.index]
  if not pdata then return nil end
  local surface = game.surfaces[pdata.surface_name]
  local portal  = surface and surface.find_entity(PORTAL_NAME, pdata.position)
  if portal and portal.valid then return portal end
  return nil
end

local function close_portal_gui(player)
  storage.player_portal[player.index] = nil
  local panel = player.gui.relative[PORTAL_RELATIVE]
  if panel and panel.valid then
    panel.destroy()
  end
end

-- A titled divider bar that opens a new section of the panel.
local function add_section_header(parent, title)
  local bar = parent.add{type = "frame", style = "subheader_frame", direction = "horizontal"}
  bar.style.horizontally_stretchable = true
  bar.add{type = "label", caption = title, style = "subheader_caption_label"}
end

-- The padded body that holds a section's cards/rows.
local function add_section_body(parent)
  local body = parent.add{type = "flow", direction = "vertical"}
  body.style.padding = 8
  body.style.vertical_spacing = 6
  body.style.horizontally_stretchable = true
  return body
end

-- A boxed card: icon on the left, a title + status line in the middle.
-- Returns the card and its row so callers can append controls (e.g. a button).
local function add_card(parent, sprite, title, status)
  local card = parent.add{type = "frame", style = "deep_frame_in_shallow_frame", direction = "horizontal"}
  card.style.padding = 8
  card.style.horizontally_stretchable = true

  local row = card.add{type = "flow", direction = "horizontal"}
  row.style.vertical_align = "center"
  row.style.horizontal_spacing = 12
  row.style.horizontally_stretchable = true

  local icon = row.add{type = "sprite", sprite = sprite, resize_to_sprite = false}
  icon.style.size = 32

  local info = row.add{type = "flow", direction = "vertical"}
  info.style.horizontally_stretchable = true
  info.style.vertical_spacing = 2
  info.add{type = "label", caption = title, style = "caption_label"}
  info.add{type = "label", caption = status}

  return card, row
end

-- One destination: planet card + travel button (grey until its module is installed).
local function add_destination_card(parent, dest, installed)
  local _, row = add_card(
    parent,
    "item/" .. dest.module,
    dest.label,
    installed
      and (COLOR_READY .. "Ready" .. COLOR_END)
      or  (COLOR_MISSING .. "Module required" .. COLOR_END)
  )

  local btn = row.add{
    type    = "button",
    name    = "portal_travel_" .. dest.surface,
    caption = "Travel",
    style   = installed and "confirm_button" or "button",
    enabled = installed,
    tooltip = installed and ("Travel to " .. dest.label)
      or "Drop the warp module into the portal to enable travel",
  }
  btn.style.minimal_width = 90
end

-- One warp-resource row: icon + name on the left, have / need on the right.
local function add_resource_row(parent, item, have, need)
  local enough = have >= need

  local frame = parent.add{type = "frame", style = "deep_frame_in_shallow_frame", direction = "horizontal"}
  frame.style.padding = 6
  frame.style.horizontally_stretchable = true

  local row = frame.add{type = "flow", direction = "horizontal"}
  row.style.vertical_align = "center"
  row.style.horizontal_spacing = 8
  row.style.horizontally_stretchable = true

  local icon = row.add{type = "sprite", sprite = "item/" .. item}
  icon.style.size = 24

  local name = row.add{type = "label", caption = WARP_COST_LABEL[item] or item}
  name.style.horizontally_stretchable = true

  row.add{
    type    = "label",
    caption = (enough and COLOR_READY or COLOR_MISSING) .. have .. " / " .. need .. COLOR_END,
    style   = "caption_label",
  }
end

-- (Re)fill the panel from current portal contents, grouped into sections.
local function populate_list(content, portal)
  content.clear()

  -- Section: travel destinations.
  add_section_header(content, "Destinations")
  local dests = add_section_body(content)
  dests.add{type = "label", caption = "Load a warp module, then pick where to go.", style = "label"}
  for _, dest in ipairs(DESTINATIONS) do
    add_destination_card(dests, dest, portal_module_count(portal, dest.module) > 0)
  end

  -- Section: modifier modules (cargo, free travel) — shown with their install state
  -- so players know what's available even before slotting one in.
  add_section_header(content, "Modules")
  local mods = add_section_body(content)
  if CARGO_ENABLED then
    local cargo_on = portal_allows_cargo(portal)
    add_card(mods, "item/" .. CARGO_MODULE, "Cargo Module",
      cargo_on
        and (COLOR_READY   .. "Inventory travels with you" .. COLOR_END)
        or  (COLOR_MISSING .. "Empty your inventory before travelling" .. COLOR_END))
  end
  local free_on = portal_allows_free_travel(portal)
  add_card(mods, "item/" .. FREE_TRAVEL_MODULE, "Free Travel Module",
    free_on
      and (COLOR_READY   .. "Warps cost no resources" .. COLOR_END)
      or  (COLOR_MISSING .. "Not installed" .. COLOR_END))

  -- Section: per-trip resource cost.
  add_section_header(content, "Warp Resources")
  local res = add_section_body(content)
  if free_on then
    res.add{type = "label", caption = COLOR_READY .. "Free Travel Module installed — warps are free." .. COLOR_END}
  elseif settings.global["portal-travel-cost-multiplier"].value <= 0 then
    res.add{type = "label", caption = COLOR_READY .. "Travel cost disabled — warps are free." .. COLOR_END}
  else
    res.add{type = "label", caption = "Consumed from the portal each trip:", style = "label"}
    for _, c in ipairs(WARP_COST) do
      add_resource_row(res, c.name, portal_module_count(portal, c.name), cost_amount(c.amount))
    end
  end
end

-- Dock the destination panel onto the portal's native inventory window.
local function open_portal_gui(player, entity)
  close_portal_gui(player)

  storage.player_portal[player.index] = {
    surface_name = entity.surface.name,
    position     = entity.position,
  }

  local frame = player.gui.relative.add{
    type      = "frame",
    name      = PORTAL_RELATIVE,
    caption   = "Travel",
    direction = "vertical",
    anchor    = {
      gui      = defines.relative_gui_type.container_gui,
      position = defines.relative_gui_position.right,
      name     = PORTAL_NAME,  -- only dock onto the portal, not other chests
    },
  }

  local content = frame.add{
    type      = "frame",
    name      = "portal_content",
    style     = "inside_shallow_frame",
    direction = "vertical",
  }
  content.style.minimal_width = 340

  -- Sections (subheader bars + bodies) are added straight into this flow so each
  -- divider spans the full panel width.
  local list = content.add{type = "flow", name = "portal_list", direction = "vertical"}
  list.style.horizontally_stretchable = true
  list.style.vertical_spacing = 0

  populate_list(list, entity)
end

-- Track the installed-module signature so the panel only rebuilds when it changes.
local panel_signatures = {}

local function portal_signature(portal)
  local parts = {}
  for _, dest in ipairs(DESTINATIONS) do
    parts[#parts + 1] = portal_module_count(portal, dest.module) > 0 and "1" or "0"
  end
  parts[#parts + 1] = portal_allows_cargo(portal) and "1" or "0"
  parts[#parts + 1] = portal_allows_free_travel(portal) and "1" or "0"
  -- Live cost-resource counts so the per-trip cost readout stays accurate.
  for _, c in ipairs(WARP_COST) do
    parts[#parts + 1] = c.name .. portal_module_count(portal, c.name)
  end
  return table.concat(parts, ",")
end

-- Refresh open panels as players drag modules in/out (no inventory-change event for chests).
local function refresh_open_panels()
  for player_index in pairs(storage.player_portal) do
    local player = game.get_player(player_index)
    local panel  = player and player.gui.relative[PORTAL_RELATIVE]
    local portal = player and get_player_portal(player)
    if player and panel and panel.valid and portal then
      local sig = portal_signature(portal)
      if panel_signatures[player_index] ~= sig then
        panel_signatures[player_index] = sig
        populate_list(panel.portal_content.portal_list, portal)
      end
    end
  end
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

  -- Let the native inventory window open (modules are dragged in/out there);
  -- dock the destination panel onto it.
  open_portal_gui(player, entity)
end)

------------------------------------------------------------
-- GUI button handlers
------------------------------------------------------------

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not element or not element.valid then return end
  local player = game.get_player(event.player_index)
  local name   = element.name

  -- Travel buttons are named "portal_travel_<surface>"
  local prefix = "portal_travel_"
  if name:sub(1, #prefix) ~= prefix then return end
  local dest_planet = name:sub(#prefix + 1)

  local portal = get_player_portal(player)
  if not portal then
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
      show_warning(player, "Empty your inventory before travelling, or install a Cargo Warp Module!")
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

  -- Per-trip warp fee, paid from the portal's own inventory (travellers without a
  -- cargo module arrive empty-handed, so the player can't be charged directly).
  if not portal_allows_free_travel(portal) then
    if not portal_can_afford(portal) then
      show_warning(player, "Portal needs " .. warp_cost_text() ..
        " per warp. Stock the portal or install a Free Travel Module.")
      return
    end
    charge_warp(portal)
  end

  close_portal_gui(player)
  player.opened = nil  -- close the native portal window too

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
  -- When the native portal window closes, tear down the docked panel.
  if event.entity and event.entity.valid and event.entity.name == PORTAL_NAME then
    local player = game.get_player(event.player_index)
    if player then close_portal_gui(player) end
    panel_signatures[event.player_index] = nil
  end
end)

script.on_event(defines.events.on_player_left_game, function(event)
  storage.player_portal[event.player_index] = nil
  panel_signatures[event.player_index] = nil
  storage.warnings[event.player_index] = nil
  local tp = storage.teleporting[event.player_index]
  if tp then
    destroy_overlay(tp.renders)
    storage.teleporting[event.player_index] = nil
  end
end)

------------------------------------------------------------
-- Per-tick: drive teleports and keep open destination panels in sync
------------------------------------------------------------

script.on_event(defines.events.on_tick, function(event)
  drive_teleports()

  if next(storage.warnings) ~= nil then
    for index, expire in pairs(storage.warnings) do
      if event.tick >= expire then
        local player = game.get_player(index)
        if player and player.gui.screen[WARNING_NAME] then
          player.gui.screen[WARNING_NAME].destroy()
        end
        storage.warnings[index] = nil
      end
    end
  end

  if event.tick % 12 == 0 then
    refresh_open_panels()
  end
end)
