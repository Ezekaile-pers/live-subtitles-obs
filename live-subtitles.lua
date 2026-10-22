--[[
Live Subtitles for OBS 1.2.0 — английские субтитры вашей речи на стриме. MIT License, (c) 2026 Ezekaile.

LocalVocal (Whisper) слушает микрофон, переводит речь на английский и пишет текст в скрытый текстовый источник.
Этот скрипт раз в 100 мс читает текст и шлёт его событием «live-subtitles» (javascript_event) браузерным источникам
с overlay/overlay.html; страница чистит текст наборами сленга (packs/*.js) и цензурой и рисует строку в выбранном
стиле. Настройки оверлея живут в параметрах его URL — их пишет скрипт. «Настроить всё» создаёт текстовый источник,
оверлей и фильтр LocalVocal на микрофоне. Установка — README.md рядом со скриптом.
]]
obs = obslua

local VERSION = '1.2.0'
local EVENT = 'live-subtitles'
local LOCALVOCAL = 'transcription_filter_audio_filter'
local FILTER_NAME = 'Live Subtitles (LocalVocal)'
local DEFAULT_OVERLAY = 'Live Subtitles'
local DEFAULT_TEXT = 'Live Subtitles (text)'
-- Дружественные имена из каталога LocalVocal (data/models/models_directory.json): плагин сам скачивает выбранную.
-- Пустое значение — не трогать модель фильтра (у кого LocalVocal уже настроен на свой файл).
local MODELS = { 'Whisper Medium q5 (514Mb)', 'Whisper Small q5 (181Mb)', 'Whisper Large v3 q5 (1Gb)' }
-- Файл модели в папке models модуля (туда её кладёт установщик, в любую выбранную папку): есть — LocalVocal берёт его
-- как внешний файл и ничего не качает; нет — модель по имени, LocalVocal найдёт свою или скачает сам.
local MODEL_FILES = {
  ['Whisper Medium q5 (514Mb)'] = 'ggml-medium-q5_0.bin',
  ['Whisper Small q5 (181Mb)'] = 'ggml-small-q5_1.bin',
  ['Whisper Large v3 q5 (1Gb)'] = 'ggml-large-v3-q5_0.bin',
}
local STYLES = { 'classic', 'box', 'eve-photon', 'eve-local', 'wow' }
local LANGUAGES = {
  { 'ru', 'Русский' }, { 'uk', 'Українська' }, { 'be', 'Беларуская' }, { 'kk', 'Қазақ тілі' }, { 'pl', 'Polski' },
  { 'de', 'Deutsch' }, { 'fr', 'Français' }, { 'es', 'Español' }, { 'pt', 'Português' }, { 'it', 'Italiano' },
  { 'tr', 'Türkçe' }, { 'zh', '中文' }, { 'ja', '日本語' }, { 'ko', '한국어' }, { 'en', 'English' },
}
local MIC_TYPES = { wasapi_input_capture = true, coreaudio_input_capture = true, pulse_input_capture = true, alsa_input_capture = true }
local BUILTIN_PACKS = { eve = true, wow = true } -- наборы, которые идут с модулем; остальные — свои
local TEXT_TYPES = { text_gdiplus = true, text_ft2_source = true }
local TICK_MS = 100
local REWRITE_TICKS = 5   -- URL оверлея переписывается через 0,5 с после последней правки (а не на каждую букву ника)
local RESEND_TICKS = 15   -- через 1,5 с после смены URL страница загрузилась — повторяем ей текущую фразу

-- ---------- подписи: по-русски при локали OBS ru-*, иначе по-английски ----------

local L = {
  ru = {
    description = '<b>Live Subtitles</b> %s — английские субтитры вашей речи: LocalVocal → оверлей в стиле EVE, WoW или кино.<br>Первый раз: выбери микрофон, язык и стиль, нажми «Настроить всё». Подробно — README.md рядом со скриптом.',
    status = 'Состояние',
    setup = 'Настроить всё',
    test = 'Показать тест',
    refresh = 'Обновить списки',
    group_speech = 'Речь',
    mic = 'Микрофон',
    model = 'Модель Whisper',
    model_keep = 'не менять (как сейчас в LocalVocal)',
    model_hint = 'LocalVocal скачает модель сам при первой настройке. Medium — лучший перевод, нужна видеокарта; Small — для слабых ПК; Large — лучше всех, но тяжёлая.',
    device = 'Считать на',
    device_gpu = 'видеокарте — быстро (рекомендуем)',
    device_cpu = 'процессоре — не трогает видеокарту, медленнее',
    device_keep = 'не менять (как сейчас в LocalVocal)',
    device_hint = 'Видеокарта переводит фразу примерно за полсекунды. Если игра подлагивает, пока вы говорите: сначала ограничьте частоту кадров в игре — видеокарте нужен запас; не помогло — выберите процессор: субтитры придут на пару секунд позже, модель лучше Small. Новое устройство заработает после перезапуска OBS.',
    live_text = 'Текст по ходу речи',
    live_text_hint = 'Фраза появляется и растёт, пока вы говорите. Whisper при этом каждую секунду заново переводит всю фразу — видеокарта (или процессор) занята всё время речи, игры могут подлагивать. Без галки фраза появляется целиком, когда вы договорили.',
    restart_device = 'Устройство перевода сменится после перезапуска OBS.',
    language = 'Язык речи',
    translate = 'Переводить на английский',
    group_look = 'Вид',
    style = 'Стиль',
    ['style_classic'] = 'Классика — киношные субтитры',
    ['style_box'] = 'Плашка — текст на тёмной подложке',
    ['style_eve-photon'] = 'EVE Online — окно интерфейса',
    ['style_eve-local'] = 'EVE Online — строка Local',
    ['style_wow'] = 'World of Warcraft — /say',
    name = 'Ник говорящего',
    name_mode = 'Ник на экране',
    name_mode_style = 'по стилю',
    name_mode_show = 'показывать',
    name_mode_hide = 'не показывать',
    custom_name_color = 'Свой цвет ника',
    name_color = 'Цвет ника',
    size = 'Размер шрифта (px на 1080p)',
    font = 'Шрифт (пусто — по стилю)',
    position = 'Где',
    position_bottom = 'внизу', position_top = 'вверху', position_middle = 'посередине',
    align = 'Выравнивание',
    align_left = 'слева', align_center = 'по центру', align_right = 'справа',
    offset = 'Отступ от края, %',
    width = 'Ширина, % экрана',
    lines = 'Строк на экране',
    fade = 'Гаснет через, с (0 — когда текст очищен)',
    custom_accent = 'Свой цвет рамки (стили EVE)',
    accent = 'Цвет рамки',
    group_text = 'Текст',
    censor = 'Мат звёздочками',
    hide = 'Свои слова под звёздочки (через запятую)',
    group_sources = 'Источники',
    text_source = 'Текст от LocalVocal',
    overlay = 'Оверлей (браузерный источник)',
    no_localvocal = 'LocalVocal не установлен — README, шаг 1, потом перезапусти OBS.',
    need_mic = 'Нет микрофона: добавь в сцену «Захват входного аудиопотока» и выбери его в поле «Микрофон».',
    mic_missing = 'Микрофон «%s» не найден — выбери другой в поле «Микрофон».',
    need_setup = 'LocalVocal есть, но не настроен — нажми «Настроить всё».',
    no_text = 'Нет текстового источника «%s» — нажми «Настроить всё».',
    no_overlay = 'Нет оверлея «%s» — нажми «Настроить всё».',
    not_overlay = 'Источник «%s» — не оверлей Live Subtitles: выбери в поле «Оверлей» другой или оставь «Live Subtitles».',
    ready = 'Готово: «%s» → LocalVocal → «%s» → оверлей «%s». Первый раз LocalVocal скачивает модель — подожди, потом скажи что-нибудь.',
    working = 'Работает: «%s» → LocalVocal → «%s» → оверлей «%s».',
    test_sent = 'Тест показан в оверлее (%d).',
  },
  en = {
    description = '<b>Live Subtitles</b> %s — English subtitles of your speech: LocalVocal → an overlay styled like EVE, WoW or a movie.<br>First time: pick your microphone, language and style, then press “Set up everything”. Details — README.md next to the script.',
    status = 'Status',
    setup = 'Set up everything',
    test = 'Show test',
    refresh = 'Refresh lists',
    group_speech = 'Speech',
    mic = 'Microphone',
    model = 'Whisper model',
    model_keep = 'keep (as set in LocalVocal)',
    model_hint = 'LocalVocal downloads the model by itself on first setup. Medium translates best and wants a GPU; Small is for weak PCs; Large is the best and the heaviest.',
    device = 'Run on',
    device_gpu = 'graphics card — fast (recommended)',
    device_cpu = 'processor — leaves the graphics card alone, slower',
    device_keep = 'keep (as set in LocalVocal)',
    device_hint = 'A graphics card translates a phrase in about half a second. If your game stutters while you talk: first cap the game frame rate — the graphics card needs headroom; if that is not enough, choose the processor: subtitles come a couple of seconds later, the Small model works best. The new device starts working after you restart OBS.',
    live_text = 'Text while speaking',
    live_text_hint = 'The phrase appears and grows while you speak. Whisper then re-translates the whole phrase every second — your graphics card (or processor) is busy all the time you talk, games may stutter. Off — the whole phrase appears when you finish it.',
    restart_device = 'The translation device changes after you restart OBS.',
    language = 'Spoken language',
    translate = 'Translate to English',
    group_look = 'Look',
    style = 'Style',
    ['style_classic'] = 'Classic — movie subtitles',
    ['style_box'] = 'Box — text on a dark plate',
    ['style_eve-photon'] = 'EVE Online — interface window',
    ['style_eve-local'] = 'EVE Online — Local chat line',
    ['style_wow'] = 'World of Warcraft — /say',
    name = 'Speaker name',
    name_mode = 'Name on screen',
    name_mode_style = 'by style',
    name_mode_show = 'show',
    name_mode_hide = 'hide',
    custom_name_color = 'Custom name color',
    name_color = 'Name color',
    size = 'Font size (px at 1080p)',
    font = 'Font (empty — style default)',
    position = 'Position',
    position_bottom = 'bottom', position_top = 'top', position_middle = 'middle',
    align = 'Alignment',
    align_left = 'left', align_center = 'center', align_right = 'right',
    offset = 'Margin from the edge, %',
    width = 'Width, % of the screen',
    lines = 'Lines on screen',
    fade = 'Fade after, s (0 — when the text is cleared)',
    custom_accent = 'Custom frame color (EVE styles)',
    accent = 'Frame color',
    group_text = 'Text',
    censor = 'Mask profanity with asterisks',
    hide = 'Your own words to mask (comma-separated)',
    group_sources = 'Sources',
    text_source = 'Text from LocalVocal',
    overlay = 'Overlay (browser source)',
    no_localvocal = 'LocalVocal is not installed — README, step 1, then restart OBS.',
    need_mic = 'No microphone: add an “Audio Input Capture” to a scene and pick it in “Microphone”.',
    mic_missing = 'Microphone “%s” not found — pick another one in “Microphone”.',
    need_setup = 'LocalVocal is installed but not set up — press “Set up everything”.',
    no_text = 'No text source “%s” — press “Set up everything”.',
    no_overlay = 'No overlay “%s” — press “Set up everything”.',
    not_overlay = 'Source “%s” is not a Live Subtitles overlay: pick another one in “Overlay” or leave “Live Subtitles”.',
    ready = 'Done: “%s” → LocalVocal → “%s” → overlay “%s”. The first time LocalVocal downloads the model — wait, then say something.',
    working = 'Working: “%s” → LocalVocal → “%s” → overlay “%s”.',
    test_sent = 'Test shown in the overlay (%d).',
  },
}

local function lang()
  local locale = obs.obs_get_locale() or ''
  return locale:sub(1, 2) == 'ru' and 'ru' or 'en'
end

local function T(key, ...)
  local text = L[lang()][key] or L.en[key] or key
  if select('#', ...) > 0 then text = string.format(text, ...) end
  return text
end

-- ---------- строки, адреса, JSON ----------

-- Классы символов Lua (%w, %s, %c) зависят от локали C — с кириллицей в UTF-8 только явные диапазоны.
local function trim(s) return ((s or ''):gsub('^[ \t\r\n]+', ''):gsub('[ \t\r\n]+$', '')) end

local function split(s)
  local out = {}
  for part in (s or ''):gmatch('[^,]+') do
    part = trim(part)
    if part ~= '' then out[#out + 1] = part end
  end
  return out
end

local function url_encode(s, safe)
  return (s:gsub('[^' .. safe .. ']', function(c) return string.format('%%%02X', c:byte()) end))
end

local PATH_SAFE = 'A-Za-z0-9%-%._~/:'
local QUERY_SAFE = 'A-Za-z0-9%-%._~,'

-- Путь к файлу → file:///… (прямые слэши, байты UTF-8 вне безопасных — %XX).
local function file_url(path)
  local p = path:gsub('\\', '/'):gsub('^/+', '')
  return 'file:///' .. url_encode(p, PATH_SAFE)
end

local JSON_ESCAPES = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

-- Строка → JSON-строка в кавычках. obs-browser подставляет JSON в код страницы как есть, поэтому U+2028/2029 тоже экранируются.
local function json_quote(s)
  local out = s:gsub('[%z\1-\31\127"\\]', function(c) return JSON_ESCAPES[c] or string.format('\\u%04x', c:byte()) end)
  out = out:gsub('\226\128\168', '\\u2028'):gsub('\226\128\169', '\\u2029')
  return '"' .. out .. '"'
end

-- Цвет OBS (0xAABBGGRR) → #rrggbb.
local function color_hex(c)
  c = math.floor(tonumber(c) or 0)
  local r, g, b = c % 256, math.floor(c / 256) % 256, math.floor(c / 65536) % 256
  return string.format('#%02x%02x%02x', r, g, b)
end

-- Настройки → адрес страницы оверлея. Порядок параметров постоянный: одинаковые настройки — одинаковый URL.
local function build_url(cfg, overlay_path)
  local params = {}
  local function add(key, value)
    if value == nil then return end
    value = tostring(value)
    if value ~= '' then params[#params + 1] = key .. '=' .. url_encode(value, QUERY_SAFE) end
  end
  add('style', cfg.style)
  add('name', cfg.name)
  add('nameColor', cfg.name_color)
  add('showName', cfg.show_name)
  add('size', cfg.size)
  add('font', cfg.font)
  add('position', cfg.position)
  add('align', cfg.align)
  add('offset', cfg.offset)
  add('width', cfg.width)
  add('lines', cfg.lines)
  add('fade', cfg.fade)
  add('packs', table.concat(cfg.packs or {}, ','))
  if cfg.censor ~= nil then add('censor', cfg.censor and '1' or '0') end
  add('hide', table.concat(cfg.hide or {}, ','))
  add('accent', cfg.accent)
  local url = file_url(overlay_path)
  if #params > 0 then url = url .. '?' .. table.concat(params, '&') end
  return url
end

-- ---------- наборы сленга: packs/<id>.js (правила) + packs/<id>.prompt.txt (подсказка Whisper) ----------

local function read_file(path) return obs.os_quick_read_utf8_file(path) end

local function list_packs(dir)
  local ids = {}
  local d = obs.os_opendir(dir)
  if d == nil then return ids end
  local entry = obs.os_readdir(d)
  while entry ~= nil do
    if not entry.directory then
      local id = tostring(entry.d_name):match('^([A-Za-z0-9_%-]+)%.js$')
      if id and id ~= 'profanity' then ids[#ids + 1] = id end
    end
    entry = obs.os_readdir(d)
  end
  obs.os_closedir(d)
  table.sort(ids)
  return ids
end

local function pack_name(dir, id)
  local js = read_file(dir .. '/' .. id .. '.js')
  local name = js and js:match('registerPack%s*%(%s*{.-name%s*:%s*[\'"]([^\'"]+)[\'"]')
  return name or id
end

local function compose_prompt(dir, ids)
  local parts = {}
  for _, id in ipairs(ids) do
    local text = trim(read_file(dir .. '/' .. id .. '.prompt.txt'))
    if text ~= '' then parts[#parts + 1] = text end
  end
  return table.concat(parts, ' ')
end

-- ---------- источники OBS ----------

local SOURCE_VIDEO = obs.OBS_SOURCE_VIDEO or 1 -- obs-source.h: 1 << 0
local SOURCE_AUDIO = obs.OBS_SOURCE_AUDIO or 2 -- obs-source.h: 1 << 1
local function has_flag(flags, bit) return math.floor((flags or 0) / bit) % 2 == 1 end

local function source_exists(name)
  if name == nil or name == '' then return false end
  local src = obs.obs_get_source_by_name(name)
  if src == nil then return false end
  obs.obs_source_release(src)
  return true
end

-- fn(src) для каждого входа OBS; список освобождается сам.
local function each_source(fn)
  local sources = obs.obs_enum_sources()
  if sources == nil then return end
  for _, src in ipairs(sources) do fn(src) end
  obs.source_list_release(sources)
end

local function names_where(pred)
  local out = {}
  each_source(function(src) if pred(src) then out[#out + 1] = obs.obs_source_get_name(src) end end)
  return out
end

-- Микрофоны: источники со звуком и без картинки, захваты входа — первыми.
local function audio_sources()
  local inputs, others = {}, {}
  each_source(function(src)
    local flags = obs.obs_source_get_output_flags(src)
    if has_flag(flags, SOURCE_AUDIO) and not has_flag(flags, SOURCE_VIDEO) then
      local list = MIC_TYPES[obs.obs_source_get_unversioned_id(src)] and inputs or others
      list[#list + 1] = obs.obs_source_get_name(src)
    end
  end)
  for _, name in ipairs(others) do inputs[#inputs + 1] = name end
  return inputs
end

local function first_input_mic()
  local found
  each_source(function(src)
    if not found and MIC_TYPES[obs.obs_source_get_unversioned_id(src)] then found = obs.obs_source_get_name(src) end
  end)
  return found
end

local function localvocal_installed() return obs.obs_source_get_display_name(LOCALVOCAL) ~= nil end

-- Все фильтры LocalVocal: { source = имя источника, filter = имя фильтра }.
local function find_localvocal()
  local found = {}
  each_source(function(src)
    local filters = obs.obs_source_enum_filters(src)
    if filters == nil then return end
    for _, f in ipairs(filters) do
      if obs.obs_source_get_unversioned_id(f) == LOCALVOCAL then
        found[#found + 1] = { source = obs.obs_source_get_name(src), filter = obs.obs_source_get_name(f) }
      end
    end
    obs.source_list_release(filters)
  end)
  return found
end

-- ---------- состояние скрипта ----------

local MODULE_DIR = (script_path() or ''):gsub('\\', '/')
if MODULE_DIR ~= '' and MODULE_DIR:sub(-1) ~= '/' then MODULE_DIR = MODULE_DIR .. '/' end
local OVERLAY_PATH = MODULE_DIR .. 'overlay/overlay.html'
local PACKS_DIR = MODULE_DIR .. 'packs'

local state = { settings = nil, cfg = nil, last_text = nil, rewrite_ticks = nil, resend_ticks = nil, status = '' }

local function read_config(s)
  local get, int, bool = obs.obs_data_get_string, obs.obs_data_get_int, obs.obs_data_get_bool
  local mode = get(s, 'name_mode')
  local cfg = {
    mic = get(s, 'mic'),
    model = get(s, 'model'),
    device = get(s, 'device'),
    live_text = bool(s, 'live_text'),
    language = get(s, 'language'),
    translate = bool(s, 'translate'),
    style = get(s, 'style'),
    name = trim(get(s, 'name')),
    show_name = mode == 'show' and '1' or mode == 'hide' and '0' or '',
    name_color = bool(s, 'custom_name_color') and color_hex(int(s, 'name_color')) or '',
    size = int(s, 'size'),
    font = trim(get(s, 'font')),
    position = get(s, 'position'),
    align = get(s, 'align'),
    offset = int(s, 'offset'),
    width = int(s, 'width'),
    lines = int(s, 'lines'),
    fade = int(s, 'fade'),
    accent = bool(s, 'custom_accent') and color_hex(int(s, 'accent')) or '',
    packs = {},
    censor = bool(s, 'censor'),
    hide = split(get(s, 'hide')),
    text_source = trim(get(s, 'text_source')),
    overlay = trim(get(s, 'overlay')),
  }
  if cfg.text_source == '' then cfg.text_source = DEFAULT_TEXT end
  if cfg.overlay == '' then cfg.overlay = DEFAULT_OVERLAY end
  -- Сначала встроенные наборы, потом свои (custom и любые новые файлы): правила своих идут последними и могут
  -- поправить вывод игрового набора, а их слова — в конце подсказки, которую Whisper читает с хвоста.
  local own = {}
  for _, id in ipairs(list_packs(PACKS_DIR)) do
    if bool(s, 'pack_' .. id) then
      local list = BUILTIN_PACKS[id] and cfg.packs or own
      list[#list + 1] = id
    end
  end
  for _, id in ipairs(own) do cfg.packs[#cfg.packs + 1] = id end
  return cfg
end

local function config()
  if state.cfg == nil then
    local s = obs.obs_data_create()
    script_defaults(s)
    state.cfg = read_config(s)
    obs.obs_data_release(s)
  end
  return state.cfg
end

-- ---------- текст → оверлеи ----------

-- Оверлей: браузерный источник с overlay/overlay.html в адресе или тот, что выбран в настройках.
local function each_overlay(fn)
  local own = config().overlay
  each_source(function(src)
    if obs.obs_source_get_unversioned_id(src) ~= 'browser_source' then return end
    local s = obs.obs_source_get_settings(src)
    local url = obs.obs_data_get_string(s, 'url')
    obs.obs_data_release(s)
    if url:find('/overlay/overlay.html', 1, true) or obs.obs_source_get_name(src) == own then fn(src) end
  end)
end

local function broadcast(json)
  local n = 0
  each_overlay(function(src)
    local cd = obs.calldata_create()
    obs.calldata_set_string(cd, 'eventName', EVENT)
    obs.calldata_set_string(cd, 'jsonString', json)
    obs.proc_handler_call(obs.obs_source_get_proc_handler(src), 'javascript_event', cd)
    obs.calldata_destroy(cd)
    n = n + 1
  end)
  return n
end

local function send_text(text) return broadcast('{"text":' .. json_quote(text) .. '}') end

local function show_test()
  local n = broadcast('{"test":true}')
  state.status = n > 0 and T('test_sent', n) or T('no_overlay', config().overlay)
  return state.status
end

local function read_text(name)
  local src = obs.obs_get_source_by_name(name)
  if src == nil then return nil end
  local s = obs.obs_source_get_settings(src)
  local text = obs.obs_data_get_string(s, 'text')
  obs.obs_data_release(s)
  obs.obs_source_release(src)
  return text
end

-- Источник из поля «Оверлей»: 'missing' — нет, 'ours' — наш (пустой URL или overlay/overlay.html), 'foreign' — чужой.
-- Чужой браузерный источник (алерты с токеном в адресе и т.п.) скрипт не переписывает.
local function overlay_kind(name)
  local src = obs.obs_get_source_by_name(name)
  if src == nil then return 'missing' end
  local kind = 'foreign'
  if obs.obs_source_get_unversioned_id(src) == 'browser_source' then
    local s = obs.obs_source_get_settings(src)
    local url = obs.obs_data_get_string(s, 'url')
    obs.obs_data_release(s)
    if url == '' or url:find('/overlay/overlay.html', 1, true) then kind = 'ours' end
  end
  obs.obs_source_release(src)
  return kind
end

-- Своему оверлею — адрес из настроек; переписывается, только если изменился (иначе страница перезагрузится зря).
local function update_overlays()
  local cfg = config()
  if overlay_kind(cfg.overlay) ~= 'ours' then return false end
  local src = obs.obs_get_source_by_name(cfg.overlay)
  if src == nil then return false end
  local changed = false
  if obs.obs_source_get_unversioned_id(src) == 'browser_source' then
    local url = build_url(cfg, OVERLAY_PATH)
    local s = obs.obs_source_get_settings(src)
    changed = obs.obs_data_get_string(s, 'url') ~= url or obs.obs_data_get_bool(s, 'is_local_file')
    obs.obs_data_release(s)
    if changed then
      local data = obs.obs_data_create()
      obs.obs_data_set_string(data, 'url', url)
      obs.obs_data_set_bool(data, 'is_local_file', false)
      obs.obs_source_update(src, data)
      obs.obs_data_release(data)
      state.resend_ticks = RESEND_TICKS
    end
  end
  obs.obs_source_release(src)
  return changed
end

-- Первые два слова совпали — та же фраза растёт (LocalVocal шлёт частичные результаты).
local function first_words(s)
  local words = {}
  for w in s:lower():gmatch('[^ \t\r\n,.!?]+') do
    words[#words + 1] = w
    if #words == 2 then break end
  end
  return table.concat(words, ' ')
end

local function log_phrase(previous, text)
  if previous ~= nil and previous ~= '' and (text == '' or first_words(previous) ~= first_words(text)) then
    print('[Whisper] ' .. previous)
  end
end

local function tick()
  if state.resend_ticks then
    state.resend_ticks = state.resend_ticks - 1
    if state.resend_ticks <= 0 then
      state.resend_ticks = nil
      if state.last_text and state.last_text ~= '' then send_text(state.last_text) end
    end
  end
  if state.rewrite_ticks then
    state.rewrite_ticks = state.rewrite_ticks - 1
    if state.rewrite_ticks <= 0 then
      state.rewrite_ticks = nil
      update_overlays()
    end
  end
  local text = read_text(config().text_source)
  if text ~= nil and text ~= state.last_text then
    log_phrase(state.last_text, text)
    state.last_text = text
    send_text(text)
  end
end

-- ---------- LocalVocal ----------

local function module_models_dir() return MODULE_DIR .. 'models/' end

-- Настройки модели для фильтра: файл из папки модуля — внешним файлом, иначе — по имени из каталога LocalVocal.
local function model_values(name)
  local file = MODEL_FILES[name]
  local path = file and module_models_dir() .. file
  if path and obs.os_file_exists(path) then
    return { whisper_model_path = '!!!external!!!', whisper_model_path_external = path }
  end
  return { whisper_model_path = name }
end

-- На процессоре Whisper быстрее с потоками по числу ядер (минус два — игре и OBS), от 4 до 8.
local function cpu_threads()
  local n = tonumber(os.getenv('NUMBER_OF_PROCESSORS') or '') or 0
  return math.max(4, math.min(8, n - 2))
end

local function localvocal_settings(cfg, packs_dir)
  local s = {
    whisper_language_select = cfg.language,
    whisper_translate = cfg.translate == true,
    translate = false,
    subtitle_sources = cfg.text_source,
    initial_prompt = compose_prompt(packs_dir or PACKS_DIR, cfg.packs or {}),
    filter_words_replace = '[]',
    vad_threshold = 0.5,
    -- Скорость (замер на стриме с игрой на той же видеокарте: в момент перевода 8–22 % видеокарты вместо 35–63 %):
    -- один перевод на законченную фразу — промежуточный текст каждую секунду речи заново переводит всю фразу;
    partial_group = cfg.live_text == true,
    partial_latency = 1100,
    -- окно кодировщика ~11,5 с вместо полных 30 — фразы LocalVocal не длиннее ~11 с, прогон в 2–3 раза короче;
    audio_ctx = 576,
    -- подбор слов двумя вариантами вместо пяти — длинная фраза вдвое быстрее, перевод тот же.
    ['beam_search.beam_size'] = 2,
    suppress_blank = true,
    suppress_nst = true,
    buffered_output = false, -- «Buffered output»: строки с прокруткой вместо фразы — лента оверлея с ним ломается
  }
  if cfg.model ~= nil and cfg.model ~= '' then
    for key, value in pairs(model_values(cfg.model)) do s[key] = value end
  end
  -- У LocalVocal по умолчанию -1 — только процессор; 0 — первая видеокарта (нет её — whisper.cpp сам считает на процессоре).
  if cfg.device == 'cpu' then
    s.backend_device = -1
    s.n_threads = cpu_threads()
  elseif cfg.device ~= 'keep' then
    s.backend_device = 0
    s.n_threads = 4
  end
  return s
end

-- Устройство готового фильтра. LocalVocal меняет его только при загрузке модели, поэтому новое «Считать на» у готового
-- фильтра заработает после перезапуска OBS. Не задано — умолчание LocalVocal, -1 (процессор).
local function device_of(filter)
  local current = obs.obs_source_get_settings(filter)
  local device = obs.obs_data_has_user_value(current, 'backend_device') and obs.obs_data_get_int(current, 'backend_device') or -1
  obs.obs_data_release(current)
  return device
end

local function to_data(values)
  local data = obs.obs_data_create()
  for key, value in pairs(values) do
    if type(value) == 'boolean' then obs.obs_data_set_bool(data, key, value)
    elseif type(value) == 'number' and value == math.floor(value) then obs.obs_data_set_int(data, key, value)
    elseif type(value) == 'number' then obs.obs_data_set_double(data, key, value)
    else obs.obs_data_set_string(data, key, tostring(value)) end
  end
  return data
end

local function current_scene_source()
  if obs.obs_frontend_preview_program_mode_active() then return obs.obs_frontend_get_current_preview_scene() end
  return obs.obs_frontend_get_current_scene()
end

local function add_to_scene(src)
  local scene_src = current_scene_source()
  if scene_src == nil then return nil end
  local item = obs.obs_scene_add(obs.obs_scene_from_source(scene_src), src)
  obs.obs_source_release(scene_src)
  return item
end

local function fit_to_canvas(item)
  local ovi = obs.obs_video_info()
  if not obs.obs_get_video_info(ovi) then return end
  local bounds = obs.vec2()
  bounds.x, bounds.y = ovi.base_width, ovi.base_height
  obs.obs_sceneitem_set_bounds_type(item, obs.OBS_BOUNDS_SCALE_INNER)
  obs.obs_sceneitem_set_bounds(item, bounds)
end

local function create_input(id, name, values)
  local data = to_data(values)
  local src = obs.obs_source_create(id, name, data, nil)
  obs.obs_data_release(data)
  return src
end

local function ensure_text_source(name)
  if source_exists(name) then return end
  local id = obs.obs_get_latest_input_type_id('text_gdiplus') or obs.obs_get_latest_input_type_id('text_ft2_source') or 'text_gdiplus'
  local src = create_input(id, name, { text = '' })
  local item = add_to_scene(src)
  if item then obs.obs_sceneitem_set_visible(item, false) end
  obs.obs_source_release(src)
end

local function ensure_overlay(cfg)
  if source_exists(cfg.overlay) then return end
  -- 1920×1080: размер шрифта в настройках — пиксели кадра 1080p; на другом холсте источник растягивается целиком.
  local src = create_input('browser_source', cfg.overlay, {
    url = build_url(cfg, OVERLAY_PATH), is_local_file = false, width = 1920, height = 1080,
    shutdown = false, restart_when_active = false, reroute_audio = false, css = '',
  })
  local item = add_to_scene(src)
  if item then fit_to_canvas(item) end
  obs.obs_source_release(src)
end

-- Уже настроенный фильтр: свой файл модели стримера, его замены LocalVocal и подсказку (если набор не выбран) не стираем.
-- Внешний файл из папки models модуля — наш (его положил установщик), его можно сменить на выбранную модель.
local function keep_own_settings(filter, values)
  local current = obs.obs_source_get_settings(filter)
  local keep = {}
  if obs.obs_data_get_string(current, 'whisper_model_path') == '!!!external!!!' then
    local file = (obs.obs_data_get_string(current, 'whisper_model_path_external'):gsub('\\', '/')):lower()
    local ours = module_models_dir():lower()
    if file:sub(1, #ours) ~= ours then
      keep.whisper_model_path = true
      keep.whisper_model_path_external = true
    end
  end
  local replace = obs.obs_data_get_string(current, 'filter_words_replace')
  if replace ~= '' and replace ~= '[]' then keep.filter_words_replace = true end
  if values.initial_prompt == '' then keep.initial_prompt = true end
  obs.obs_data_release(current)
  local patch = {}
  for key, value in pairs(values) do
    if not keep[key] then patch[key] = value end
  end
  return patch
end

-- Фильтр LocalVocal на микрофоне: уже есть (любое имя) — обновить его, нет — добавить свой.
local function ensure_localvocal(mic, cfg)
  local values = localvocal_settings(cfg)
  local done = false
  local filters = obs.obs_source_enum_filters(mic)
  if filters ~= nil then
    for _, f in ipairs(filters) do
      if not done and obs.obs_source_get_unversioned_id(f) == LOCALVOCAL then
        if values.backend_device ~= nil and device_of(f) ~= values.backend_device then state.restart_device = true end
        local data = to_data(keep_own_settings(f, values))
        obs.obs_source_update(f, data)
        obs.obs_data_release(data)
        done = true
      end
    end
    obs.source_list_release(filters)
  end
  if not done then
    if values.whisper_model_path == nil then
      for key, value in pairs(model_values(MODELS[1])) do values[key] = value end
    end
    local data = to_data(values)
    local f = obs.obs_source_create(LOCALVOCAL, FILTER_NAME, data, nil)
    obs.obs_data_release(data)
    obs.obs_source_filter_add(mic, f)
    obs.obs_source_release(f)
  end
end

local function restart_note() return state.restart_device and (' ' .. T('restart_device')) or '' end

local function compute_status()
  local cfg = config()
  if not localvocal_installed() then return T('no_localvocal') end
  if cfg.mic ~= '' and not source_exists(cfg.mic) then return T('mic_missing', cfg.mic) end
  local found = find_localvocal()
  if #found == 0 then return T('need_setup') end
  if not source_exists(cfg.text_source) then return T('no_text', cfg.text_source) end
  local overlay = overlay_kind(cfg.overlay)
  if overlay == 'missing' then return T('no_overlay', cfg.overlay) end
  if overlay == 'foreign' then return T('not_overlay', cfg.overlay) end
  local mic = cfg.mic ~= '' and cfg.mic or found[1].source
  return T('working', mic, cfg.text_source, cfg.overlay) .. restart_note()
end

local function setup_all()
  local cfg = config()
  if not localvocal_installed() then
    state.status = T('no_localvocal')
    return state.status
  end
  if cfg.mic == '' then
    local auto = first_input_mic()
    if auto == nil then
      state.status = T('need_mic')
      return state.status
    end
    cfg.mic = auto
    if state.settings ~= nil then obs.obs_data_set_string(state.settings, 'mic', auto) end
  end
  if overlay_kind(cfg.overlay) == 'foreign' then
    state.status = T('not_overlay', cfg.overlay)
    return state.status
  end
  local mic = obs.obs_get_source_by_name(cfg.mic)
  if mic == nil then
    state.status = T('mic_missing', cfg.mic)
    return state.status
  end
  ensure_text_source(cfg.text_source)
  ensure_overlay(cfg)
  ensure_localvocal(mic, cfg)
  obs.obs_source_release(mic)
  update_overlays()
  state.status = T('ready', cfg.mic, cfg.text_source, cfg.overlay) .. restart_note()
  return state.status
end

-- ---------- окно настроек ----------

local function set_status(text)
  state.status = text
  if state.settings ~= nil then obs.obs_data_set_string(state.settings, 'status', text) end
end

local function add_list(props, name, items, editable)
  local p = obs.obs_properties_add_list(props, name, T(name), editable and obs.OBS_COMBO_TYPE_EDITABLE or obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING)
  for _, item in ipairs(items or {}) do obs.obs_property_list_add_string(p, item[2], item[1]) end
  return p
end

-- Списки источников (микрофоны, тексты, браузеры) — заново при открытии окна и по кнопке «Обновить списки».
local function fill_source_lists(props)
  local cfg = config()
  local function fill(name, names, current)
    local p = obs.obs_properties_get(props, name)
    if p == nil then return end
    obs.obs_property_list_clear(p)
    local seen = false
    for _, n in ipairs(names) do
      obs.obs_property_list_add_string(p, n, n)
      if n == current then seen = true end
    end
    if current ~= nil and current ~= '' and not seen then obs.obs_property_list_add_string(p, current, current) end
  end
  fill('mic', audio_sources(), cfg.mic)
  fill('text_source', names_where(function(src) return TEXT_TYPES[obs.obs_source_get_unversioned_id(src)] end), cfg.text_source)
  fill('overlay', names_where(function(src) return obs.obs_source_get_unversioned_id(src) == 'browser_source' end), cfg.overlay)
end

-- Колбэк изменения свойства: OBS вызывает его как (props, property, settings).
local function toggles(props, _, settings)
  local function show(name, on) local p = obs.obs_properties_get(props, name); if p then obs.obs_property_set_visible(p, on) end end
  show('name_color', obs.obs_data_get_bool(settings, 'custom_name_color'))
  show('accent', obs.obs_data_get_bool(settings, 'custom_accent'))
  return true
end

function script_description() return T('description', VERSION) end

function script_defaults(s)
  obs.obs_data_set_default_string(s, 'model', MODELS[1])
  obs.obs_data_set_default_string(s, 'device', 'gpu')
  obs.obs_data_set_default_bool(s, 'live_text', false)
  obs.obs_data_set_default_string(s, 'language', 'ru')
  obs.obs_data_set_default_bool(s, 'translate', true)
  obs.obs_data_set_default_string(s, 'style', 'classic')
  obs.obs_data_set_default_string(s, 'name_mode', 'style')
  obs.obs_data_set_default_int(s, 'name_color', 0xFFBA8CF5)
  obs.obs_data_set_default_int(s, 'size', 40)
  obs.obs_data_set_default_string(s, 'position', 'bottom')
  obs.obs_data_set_default_string(s, 'align', 'center')
  obs.obs_data_set_default_int(s, 'offset', 8)
  obs.obs_data_set_default_int(s, 'width', 70)
  obs.obs_data_set_default_int(s, 'lines', 2)
  obs.obs_data_set_default_int(s, 'fade', 6)
  obs.obs_data_set_default_int(s, 'accent', 0xFFE0D456)
  obs.obs_data_set_default_bool(s, 'censor', true)
  obs.obs_data_set_default_string(s, 'text_source', DEFAULT_TEXT)
  obs.obs_data_set_default_string(s, 'overlay', DEFAULT_OVERLAY)
end

function script_properties()
  local props = obs.obs_properties_create()
  set_status(state.status ~= '' and state.status or compute_status())
  obs.obs_properties_add_text(props, 'status', T('status'), obs.OBS_TEXT_INFO)
  obs.obs_properties_add_button(props, 'setup', T('setup'), function(p) set_status(setup_all()); fill_source_lists(p); return true end)
  obs.obs_properties_add_button(props, 'test', T('test'), function() set_status(show_test()); return true end)
  obs.obs_properties_add_button(props, 'refresh', T('refresh'), function(p) fill_source_lists(p); set_status(compute_status()); return true end)

  local speech = obs.obs_properties_create()
  add_list(speech, 'mic', {})
  local models = { { '', T('model_keep') } }
  for _, m in ipairs(MODELS) do models[#models + 1] = { m, m } end
  obs.obs_property_set_long_description(add_list(speech, 'model', models), T('model_hint'))
  obs.obs_property_set_long_description(add_list(speech, 'device', { { 'gpu', T('device_gpu') }, { 'cpu', T('device_cpu') }, { 'keep', T('device_keep') } }), T('device_hint'))
  obs.obs_property_set_long_description(obs.obs_properties_add_bool(speech, 'live_text', T('live_text')), T('live_text_hint'))
  add_list(speech, 'language', LANGUAGES)
  obs.obs_properties_add_bool(speech, 'translate', T('translate'))
  obs.obs_properties_add_group(props, 'group_speech', T('group_speech'), obs.OBS_GROUP_NORMAL, speech)

  local look = obs.obs_properties_create()
  local styles = {}
  for _, id in ipairs(STYLES) do styles[#styles + 1] = { id, T('style_' .. id) } end
  add_list(look, 'style', styles)
  obs.obs_properties_add_text(look, 'name', T('name'), obs.OBS_TEXT_DEFAULT)
  add_list(look, 'name_mode', { { 'style', T('name_mode_style') }, { 'show', T('name_mode_show') }, { 'hide', T('name_mode_hide') } })
  obs.obs_property_set_modified_callback(obs.obs_properties_add_bool(look, 'custom_name_color', T('custom_name_color')), toggles)
  obs.obs_properties_add_color(look, 'name_color', T('name_color'))
  obs.obs_properties_add_int_slider(look, 'size', T('size'), 12, 160, 1)
  obs.obs_properties_add_text(look, 'font', T('font'), obs.OBS_TEXT_DEFAULT)
  add_list(look, 'position', { { 'bottom', T('position_bottom') }, { 'top', T('position_top') }, { 'middle', T('position_middle') } })
  add_list(look, 'align', { { 'center', T('align_center') }, { 'left', T('align_left') }, { 'right', T('align_right') } })
  obs.obs_properties_add_int_slider(look, 'offset', T('offset'), 0, 45, 1)
  obs.obs_properties_add_int_slider(look, 'width', T('width'), 20, 100, 1)
  obs.obs_properties_add_int_slider(look, 'lines', T('lines'), 1, 4, 1)
  obs.obs_properties_add_int_slider(look, 'fade', T('fade'), 0, 60, 1)
  obs.obs_property_set_modified_callback(obs.obs_properties_add_bool(look, 'custom_accent', T('custom_accent')), toggles)
  obs.obs_properties_add_color(look, 'accent', T('accent'))
  obs.obs_properties_add_group(props, 'group_look', T('group_look'), obs.OBS_GROUP_NORMAL, look)

  local text = obs.obs_properties_create()
  for _, id in ipairs(list_packs(PACKS_DIR)) do obs.obs_properties_add_bool(text, 'pack_' .. id, pack_name(PACKS_DIR, id)) end
  obs.obs_properties_add_bool(text, 'censor', T('censor'))
  obs.obs_properties_add_text(text, 'hide', T('hide'), obs.OBS_TEXT_DEFAULT)
  obs.obs_properties_add_group(props, 'group_text', T('group_text'), obs.OBS_GROUP_NORMAL, text)

  local sources = obs.obs_properties_create()
  add_list(sources, 'text_source', {}, true)
  add_list(sources, 'overlay', {}, true)
  obs.obs_properties_add_group(props, 'group_sources', T('group_sources'), obs.OBS_GROUP_NORMAL, sources)

  fill_source_lists(props)
  if state.settings ~= nil then toggles(props, nil, state.settings) end
  return props
end

function script_load(settings)
  state.settings = settings
  state.cfg = read_config(settings)
  state.status = ''
  update_overlays()
  obs.timer_add(tick, TICK_MS)
end

function script_update(settings)
  state.settings = settings
  state.cfg = read_config(settings)
  state.rewrite_ticks = REWRITE_TICKS
end

function script_unload()
  obs.timer_remove(tick)
end

-- Функции для тестов и для своих скриптов поверх (в OBS у каждого скрипта своё Lua-окружение — глобал никому не мешает).
LiveSubtitles = {
  version = VERSION,
  text = T,
  json_quote = json_quote,
  file_url = file_url,
  build_url = build_url,
  color_hex = color_hex,
  list_packs = list_packs,
  pack_name = pack_name,
  compose_prompt = compose_prompt,
  localvocal_installed = localvocal_installed,
  find_localvocal = find_localvocal,
  localvocal_settings = localvocal_settings,
  compute_status = compute_status,
  read_config = read_config,
  tick = tick,
  send_text = send_text,
  show_test = show_test,
  update_overlays = update_overlays,
  setup_all = setup_all,
  status = compute_status,
}
