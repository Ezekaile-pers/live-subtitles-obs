-- Поддельный obslua для тестов live-subtitles.lua: источники, настройки, фильтры, сцена, таймеры, файлы и вызовы
-- javascript_event живут в таблицах. mock.reset() — чистый мир; помощники add_* раскладывают его под тест.
local M = {}

M.OBS_COMBO_TYPE_EDITABLE = 1
M.OBS_COMBO_TYPE_LIST = 2
M.OBS_COMBO_FORMAT_STRING = 3
M.OBS_TEXT_DEFAULT = 0
M.OBS_TEXT_INFO = 3
M.OBS_GROUP_NORMAL = 1
M.OBS_SOURCE_VIDEO = 1
M.OBS_SOURCE_AUDIO = 2
M.OBS_BOUNDS_SCALE_INNER = 2
M.LOG_WARNING = 200
M.LOG_INFO = 300

local world

local function new_data(values)
  local copy = {}
  for k, v in pairs(values or {}) do copy[k] = v end
  return { values = copy, defaults = {} }
end

function M.reset()
  world = {
    order = {},          -- источники (входы) в порядке создания
    types = {},          -- id типа → отображаемое имя (то, что знает OBS)
    latest = { text_gdiplus = 'text_gdiplus_v3' },
    locale = 'en-US',
    timers = {},
    fs = {},             -- папка → список файлов
    files = {},          -- путь → содержимое
    canvas = { 1920, 1080 },
    log = {},
  }
  world.scene = { name = 'Scene', items = {} }
  M.world = world
end

-- ---------- помощники тестов ----------

function M.add_source(id, name, settings, flags)
  local src = { id = id, unversioned = (id:gsub('_v%d+$', '')), name = name, settings = new_data(settings), filters = {}, events = {}, flags = flags or 0 }
  table.insert(world.order, src)
  return src
end

function M.add_filter(src, id, name, settings)
  local f = { id = id, unversioned = id, name = name, settings = new_data(settings), filters = {}, events = {}, flags = 0, is_filter = true }
  table.insert(src.filters, f)
  return f
end

function M.source(name)
  for _, s in ipairs(world.order) do if s.name == name then return s end end
end

function M.count(name)
  local n = 0
  for _, s in ipairs(world.order) do if s.name == name then n = n + 1 end end
  return n
end

-- ---------- obs_data ----------

function M.obs_data_create() return new_data() end
function M.obs_data_release(d) end
local function get(d, k) local v = d.values[k]; if v == nil then v = d.defaults[k] end; return v end
function M.obs_data_get_string(d, k) local v = get(d, k); return type(v) == 'string' and v or '' end
function M.obs_data_get_int(d, k) local v = get(d, k); return type(v) == 'number' and math.floor(v) or 0 end
function M.obs_data_get_double(d, k) local v = get(d, k); return type(v) == 'number' and v or 0 end
function M.obs_data_get_bool(d, k) return get(d, k) == true end
function M.obs_data_set_string(d, k, v) d.values[k] = v end
function M.obs_data_set_int(d, k, v) d.values[k] = v end
function M.obs_data_set_double(d, k, v) d.values[k] = v end
function M.obs_data_set_bool(d, k, v) d.values[k] = v end
function M.obs_data_set_default_string(d, k, v) d.defaults[k] = v end
function M.obs_data_set_default_int(d, k, v) d.defaults[k] = v end
function M.obs_data_set_default_double(d, k, v) d.defaults[k] = v end
function M.obs_data_set_default_bool(d, k, v) d.defaults[k] = v end

-- ---------- источники ----------

function M.obs_get_source_by_name(name) return M.source(name) end
function M.obs_source_release(s) end
function M.obs_source_get_settings(s) return s.settings end
function M.obs_source_update(s, d)
  for k, v in pairs(d.values) do s.settings.values[k] = v end
  s.updates = (s.updates or 0) + 1
end
function M.obs_enum_sources()
  local list = {}
  for _, s in ipairs(world.order) do list[#list + 1] = s end
  return list
end
function M.source_list_release(list) end
function M.obs_source_get_unversioned_id(s) return s.unversioned end
function M.obs_source_get_id(s) return s.id end
function M.obs_source_get_name(s) return s.name end
function M.obs_source_get_output_flags(s) return s.flags end
function M.obs_source_get_display_name(id) return world.types[id] end
function M.obs_get_latest_input_type_id(unversioned) return world.latest[unversioned] end
function M.obs_source_create(id, name, settings, hotkeys)
  local src = { id = id, unversioned = (id:gsub('_v%d+$', '')), name = name, settings = new_data(settings and settings.values), filters = {}, events = {}, flags = 0 }
  src.created = true
  if world.types[id] == nil and world.types[src.unversioned] == nil then src.unknown_type = true end
  -- Фильтры живут в своём источнике, входы — в общем списке (как public_sources в OBS).
  if id ~= 'transcription_filter_audio_filter' then table.insert(world.order, src) end
  return src
end
function M.obs_source_filter_add(src, filter)
  filter.is_filter = true
  table.insert(src.filters, filter)
end
function M.obs_source_enum_filters(src)
  local list = {}
  for _, f in ipairs(src.filters) do list[#list + 1] = f end
  return list
end
function M.obs_source_get_filter_by_name(src, name)
  for _, f in ipairs(src.filters) do if f.name == name then return f end end
end

-- ---------- javascript_event ----------

function M.obs_source_get_proc_handler(src) return src end
function M.calldata_create() return {} end
function M.calldata_set_string(cd, k, v) cd[k] = v end
function M.calldata_destroy(cd) end
function M.proc_handler_call(ph, name, cd)
  table.insert(ph.events, { proc = name, eventName = cd.eventName, json = cd.jsonString })
  return true
end

-- ---------- сцена и холст ----------

function M.obs_frontend_get_current_scene() return world.scene end
function M.obs_frontend_preview_program_mode_active() return false end
function M.obs_frontend_get_current_preview_scene() return world.scene end
function M.obs_scene_from_source(s) return s end
function M.obs_scene_add(scene, src)
  local item = { source = src, visible = true }
  table.insert(scene.items, item)
  return item
end
function M.obs_sceneitem_set_visible(item, v) item.visible = v end
function M.obs_sceneitem_set_bounds_type(item, t) item.bounds_type = t end
function M.obs_sceneitem_set_bounds(item, v) item.bounds = { x = v.x, y = v.y } end
function M.vec2() return { x = 0, y = 0 } end
function M.obs_video_info() return {} end
function M.obs_get_video_info(ovi)
  ovi.base_width, ovi.base_height = world.canvas[1], world.canvas[2]
  return true
end

-- ---------- файлы ----------

function M.os_opendir(path)
  local files = world.fs[path]
  if not files then return nil end
  return { files = files, i = 0 }
end
function M.os_readdir(d)
  d.i = d.i + 1
  local name = d.files[d.i]
  if not name then return nil end
  return { d_name = name, directory = false }
end
function M.os_closedir(d) end
function M.os_quick_read_utf8_file(path) return world.files[path] end
function M.os_file_exists(path) return world.files[path] ~= nil end

-- ---------- таймеры, локаль, лог ----------

function M.timer_add(fn, ms) world.timers[#world.timers + 1] = { fn = fn, ms = ms } end
function M.timer_remove(fn)
  for i = #world.timers, 1, -1 do if world.timers[i].fn == fn then table.remove(world.timers, i) end end
end
function M.obs_get_locale() return world.locale end
function M.script_log(level, msg) world.log[#world.log + 1] = msg end

-- ---------- окно настроек ----------

local function new_props() return { list = {} } end
local function add(props, p) props.list[#props.list + 1] = p; return p end
function M.obs_properties_create() return new_props() end
function M.obs_properties_add_list(props, name, desc, t, f) return add(props, { kind = 'list', name = name, desc = desc, combo = t, items = {} }) end
function M.obs_property_list_add_string(p, label, value) p.items[#p.items + 1] = { label = label, value = value } end
function M.obs_property_list_clear(p) p.items = {} end
function M.obs_properties_add_text(props, name, desc, t) return add(props, { kind = 'text', name = name, desc = desc, type = t }) end
function M.obs_properties_add_bool(props, name, desc) return add(props, { kind = 'bool', name = name, desc = desc }) end
function M.obs_properties_add_int_slider(props, name, desc, a, b, s) return add(props, { kind = 'int', name = name, desc = desc, min = a, max = b, step = s }) end
function M.obs_properties_add_color(props, name, desc) return add(props, { kind = 'color', name = name, desc = desc }) end
function M.obs_properties_add_button(props, name, text, cb) return add(props, { kind = 'button', name = name, desc = text, cb = cb }) end
function M.obs_properties_add_group(props, name, desc, t, group) return add(props, { kind = 'group', name = name, desc = desc, group = group }) end
function M.obs_properties_get(props, name)
  for _, p in ipairs(props.list) do
    if p.name == name then return p end
    if p.group then
      local inner = M.obs_properties_get(p.group, name)
      if inner then return inner end
    end
  end
end
function M.obs_property_set_modified_callback(p, cb) p.modified = cb end
function M.obs_property_set_visible(p, v) p.visible = v end
function M.obs_property_set_long_description(p, text) p.long = text end
function M.obs_property_set_description(p, text) p.desc = text end

M.reset()
return M
