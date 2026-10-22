-- Тесты live-subtitles.lua на поддельном obslua. Запуск: tests/lua/run.ps1 (LuaJIT из OBS), итог — строка «ok N» или «FAIL …».
-- TEST_DIR — папка этого файла (с «/» на конце), её задаёт run.ps1.
local mock = dofile(TEST_DIR .. 'mock_obslua.lua')
local SCRIPT = TEST_DIR .. '../../live-subtitles.lua'
local MODULE = 'C:/LS/'
local PACKS = 'C:/LS/packs'
local OVERLAY = 'file:///C:/LS/overlay/overlay.html'

local passed, failures = {}, {}
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed[#passed + 1] = name else failures[#failures + 1] = name .. ': ' .. tostring(err) end
end
local function eq(actual, expected, what)
  if actual ~= expected then error(string.format('%s: ждали %q, вышло %q', what or 'значение', tostring(expected), tostring(actual)), 2) end
end
local function ok(cond, what) if not cond then error(what or 'условие не выполнено', 2) end end
local function has(s, part, what) ok(type(s) == 'string' and s:find(part, 1, true), string.format('%s: в %q нет %q', what or 'строка', tostring(s), part)) end

-- Мир с модулем в C:/LS/: наборы eve, wow, custom и цензура, у eve и wow есть подсказки Whisper.
local function with_packs(w)
  w.fs[PACKS] = { 'custom.js', 'custom.prompt.txt', 'eve.js', 'eve.prompt.txt', 'profanity.js', 'README.md', 'wow.js', 'wow.prompt.txt' }
  w.files[PACKS .. '/eve.js'] = "  LS.registerPack({ id: 'eve', name: 'EVE Online', rules: [] });"
  w.files[PACKS .. '/wow.js'] = 'LS.registerPack({ id: "wow", name: "World of Warcraft", rules: [] });'
  w.files[PACKS .. '/custom.js'] = "LS.registerPack({ id: 'custom', name: 'Custom', rules: [] });"
  w.files[PACKS .. '/eve.prompt.txt'] = 'Jita, Amarr, tackle, point.\n'
  w.files[PACKS .. '/wow.prompt.txt'] = '  Hogger, Westfall.  \r\n'
  w.files[PACKS .. '/custom.prompt.txt'] = ''
end

local function boot(prepare)
  mock.reset()
  with_packs(mock.world)
  if prepare then prepare(mock.world, mock) end
  obslua = mock
  script_path = function() return MODULE end
  LiveSubtitles = nil
  dofile(SCRIPT)
  return LiveSubtitles
end

local function settings(values)
  local d = mock.obs_data_create()
  for k, v in pairs(values or {}) do d.values[k] = v end
  return d
end

-- Скрипт загружен так, как это делает OBS: умолчания, загрузка, применение настроек.
local function start(values, prepare)
  local LS = boot(prepare)
  local s = settings(values)
  script_defaults(s)
  script_load(s)
  script_update(s)
  return LS, s
end

local function localvocal(w) w.types.transcription_filter_audio_filter = 'LocalVocal Transcription' end
local function mic(w, m) return m.add_source('wasapi_input_capture', 'Mic', {}, m.OBS_SOURCE_AUDIO) end

-- ---------- текст в событие ----------

test('json_quote: кавычки, слэш, перевод строки, управляющие, UTF-8 как есть', function()
  local LS = boot()
  eq(LS.json_quote('a"b\\c\nd'), '"a\\"b\\\\c\\nd"', 'базовый')
  eq(LS.json_quote('\t\r\1'), '"\\t\\r\\u0001"', 'управляющие')
  eq(LS.json_quote('привет 🙂'), '"привет 🙂"', 'UTF-8')
  eq(LS.json_quote('a\226\128\168b'), '"a\\u2028b"', 'U+2028 ломает JS-строку в старых движках')
end)

-- ---------- адрес оверлея ----------

test('file_url: кириллица и пробелы в пути кодируются, слэши прямые', function()
  local LS = boot()
  eq(LS.file_url('C:\\Users\\Пилот\\live subtitles\\overlay\\overlay.html'),
    'file:///C:/Users/%D0%9F%D0%B8%D0%BB%D0%BE%D1%82/live%20subtitles/overlay/overlay.html')
  eq(LS.file_url('C:/LS/overlay/overlay.html'), OVERLAY, 'путь OBS с прямыми слэшами')
end)

test('build_url: параметры по порядку, пустые пропускаются, значения кодируются', function()
  local LS = boot()
  local url = LS.build_url({ style = 'eve-local', name = 'Space Pilot', size = 40, font = '', packs = { 'eve' }, censor = true, hide = {} }, 'C:/LS/overlay/overlay.html')
  has(url, OVERLAY .. '?style=eve-local&', 'начало')
  has(url, 'name=Space%20Pilot', 'ник')
  has(url, 'packs=eve', 'наборы')
  has(url, 'censor=1', 'цензура')
  ok(not url:find('font=', 1, true), 'пустой шрифт не пишется: ' .. url)
  ok(not url:find('hide=', 1, true), 'пустой список слов не пишется: ' .. url)
  local tricky = LS.build_url({ style = 'wow', name = 'Пилот & Co #1', packs = { 'eve', 'wow' }, hide = { 'Tom', 'Вася' }, censor = false }, 'C:/LS/overlay/overlay.html')
  has(tricky, 'name=%D0%9F%D0%B8%D0%BB%D0%BE%D1%82%20%26%20Co%20%231', 'спецсимволы в нике')
  has(tricky, 'packs=eve,wow', 'несколько наборов через запятую')
  has(tricky, 'hide=Tom,%D0%92%D0%B0%D1%81%D1%8F', 'свои слова')
  has(tricky, 'censor=0', 'цензура выключена')
end)

test('color_hex: цвет OBS (ABGR) → #rrggbb', function()
  local LS = boot()
  eq(LS.color_hex(0xFFBA8CF5), '#f58cba')
  eq(LS.color_hex(0xFF000000), '#000000')
end)

-- ---------- наборы ----------

test('list_packs: *.js из папки packs, без цензуры, по алфавиту; pack_name — из registerPack', function()
  local LS = boot()
  local ids = LS.list_packs(PACKS)
  eq(table.concat(ids, ','), 'custom,eve,wow')
  eq(LS.pack_name(PACKS, 'eve'), 'EVE Online')
  eq(LS.pack_name(PACKS, 'wow'), 'World of Warcraft', 'двойные кавычки')
  eq(LS.pack_name(PACKS, 'nope'), 'nope', 'нет файла — имя по id')
  eq(#LS.list_packs('C:/nowhere'), 0, 'нет папки — пусто')
end)

test('compose_prompt: подсказки выбранных наборов по порядку, обрезанные, пустые пропускаются', function()
  local LS = boot()
  eq(LS.compose_prompt(PACKS, { 'wow', 'custom', 'eve', 'missing' }), 'Hogger, Westfall. Jita, Amarr, tackle, point.')
  eq(LS.compose_prompt(PACKS, {}), '')
end)

-- ---------- LocalVocal ----------

test('localvocal_installed и find_localvocal: нет плагина, нет фильтров, есть фильтр', function()
  local LS = boot()
  eq(LS.localvocal_installed(), false, 'нет плагина')
  LS = boot(function(w, m) localvocal(w); mic(w, m) end)
  eq(LS.localvocal_installed(), true, 'плагин есть')
  eq(#LS.find_localvocal(), 0, 'фильтров нет')
  LS = boot(function(w, m) localvocal(w); local src = mic(w, m); m.add_filter(src, 'transcription_filter_audio_filter', 'Subs') end)
  local found = LS.find_localvocal()
  eq(#found, 1, 'один фильтр')
  eq(found[1].source, 'Mic')
  eq(found[1].filter, 'Subs')
end)

test('localvocal_settings: язык, перевод, вывод, подсказка, модель, без замен', function()
  local LS = boot()
  local s = LS.localvocal_settings({ language = 'ru', translate = true, text_source = 'Live Subtitles (text)', model = 'Whisper Medium q5 (514Mb)', packs = { 'eve' } }, PACKS)
  eq(s.whisper_language_select, 'ru')
  eq(s.whisper_translate, true)
  eq(s.translate, false, 'второй перевод LocalVocal выключен')
  eq(s.subtitle_sources, 'Live Subtitles (text)')
  eq(s.initial_prompt, 'Jita, Amarr, tackle, point.')
  eq(s.whisper_model_path, 'Whisper Medium q5 (514Mb)')
  eq(s.filter_words_replace, '[]')
  eq(s.vad_threshold, 0.5)
  eq(s.suppress_blank, true)
  eq(s.suppress_nst, true)
  -- Скорость (замер на стриме: видеокарта в момент перевода 8–22 % вместо 35–63 %, игра не подлагивает):
  eq(s.partial_group, false, 'один перевод на законченную фразу: промежуточный текст гоняет Whisper каждую секунду речи')
  eq(s.partial_latency, 1100)
  eq(s.audio_ctx, 576, 'окно ~11,5 с вместо 30: фразы LocalVocal не длиннее ~11 с')
  eq(s['beam_search.beam_size'], 2, 'подбор слов двумя вариантами вместо пяти')
  eq(s.n_threads, 4, 'на видеокарте процессору хватает 4 потоков')
  eq(LS.localvocal_settings({ live_text = true, packs = {} }, PACKS).partial_group, true, 'галка «Текст по ходу речи»')
  eq(s.backend_device, 0, 'по умолчанию — первая видеокарта (у LocalVocal по умолчанию -1, только процессор)')
  local cpu = LS.localvocal_settings({ device = 'cpu', packs = {} }, PACKS)
  eq(cpu.backend_device, -1, 'только процессор')
  ok(cpu.n_threads >= 4 and cpu.n_threads <= 8, 'на процессоре потоков больше: ядра минус два, 4–8')
  local keep = LS.localvocal_settings({ device = 'keep', packs = {} }, PACKS)
  eq(keep.backend_device, nil, 'не менять')
  eq(keep.n_threads, nil, 'не менять — и потоки не трогаем')
end)

test('«Считать на» сменили у готового фильтра — статус просит перезапустить OBS (LocalVocal меняет устройство только при загрузке модели)', function()
  local LS = start({ mic = 'Mic', device = 'cpu' }, function(w, m)
    localvocal(w)
    m.add_filter(mic(w, m), 'transcription_filter_audio_filter', 'Subs', { backend_device = 0 })
  end)
  local status = LS.setup_all()
  eq(mock.source('Mic').filters[1].settings.values.backend_device, -1, 'устройство в фильтре сменено')
  has(status, 'restart OBS', 'и сказано, что заработает после перезапуска')
  has(LS.compute_status(), 'restart OBS', 'подсказка держится до перезапуска')

  LS = start({ mic = 'Mic', device = 'gpu' }, function(w, m)
    localvocal(w)
    m.add_filter(mic(w, m), 'transcription_filter_audio_filter', 'Subs', { backend_device = 0 })
  end)
  ok(not LS.setup_all():find('restart OBS', 1, true), 'то же устройство — перезапуск не нужен')

  LS = start({ mic = 'Mic' }, function(w, m)
    localvocal(w)
    m.add_filter(mic(w, m), 'transcription_filter_audio_filter', 'Subs', {})
  end)
  has(LS.setup_all(), 'restart OBS', 'устройство не задано — LocalVocal считал на процессоре (его умолчание -1)')

  LS = start({ mic = 'Mic', device = 'cpu' }, function(w, m) localvocal(w); mic(w, m) end)
  ok(not LS.setup_all():find('restart OBS', 1, true), 'новый фильтр сразу грузит модель куда надо')
end)

test('модель из папки models модуля (её кладёт установщик, хоть на диск D) — внешним файлом LocalVocal', function()
  local LS = boot(function(w) w.files['C:/LS/models/ggml-medium-q5_0.bin'] = 'model' end)
  local s = LS.localvocal_settings({ model = 'Whisper Medium q5 (514Mb)', packs = {} }, PACKS)
  eq(s.whisper_model_path, '!!!external!!!', 'свой файл, LocalVocal ничего не качает')
  eq(s.whisper_model_path_external, 'C:/LS/models/ggml-medium-q5_0.bin')
  local small = LS.localvocal_settings({ model = 'Whisper Small q5 (181Mb)', packs = {} }, PACKS)
  eq(small.whisper_model_path, 'Whisper Small q5 (181Mb)', 'файла Small нет — по имени, LocalVocal найдёт или скачает сам')
  eq(small.whisper_model_path_external, nil)
end)

test('«Настроить всё»: новый фильтр берёт модель из папки модуля; наша внешняя модель меняется на выбранную, чужая — нет', function()
  local LS = start({ mic = 'Mic' }, function(w, m)
    localvocal(w); mic(w, m)
    w.files['C:/LS/models/ggml-medium-q5_0.bin'] = 'model'
  end)
  LS.setup_all()
  local v = mock.source('Mic').filters[1].settings.values
  eq(v.whisper_model_path, '!!!external!!!', 'новый фильтр — файл из папки модуля')
  eq(v.whisper_model_path_external, 'C:/LS/models/ggml-medium-q5_0.bin')

  LS = start({ mic = 'Mic', model = 'Whisper Small q5 (181Mb)' }, function(w, m)
    localvocal(w)
    local src = mic(w, m)
    m.add_filter(src, 'transcription_filter_audio_filter', 'Live Subtitles (LocalVocal)', {
      whisper_model_path = '!!!external!!!', whisper_model_path_external = 'C:\\LS\\models\\ggml-medium-q5_0.bin',
    })
  end)
  LS.setup_all()
  v = mock.source('Mic').filters[1].settings.values
  eq(v.whisper_model_path, 'Whisper Small q5 (181Mb)', 'наша прошлая модель из папки модуля — меняется на выбранную')

  LS = start({ mic = 'Mic', model = 'Whisper Small q5 (181Mb)' }, function(w, m)
    localvocal(w)
    local src = mic(w, m)
    m.add_filter(src, 'transcription_filter_audio_filter', 'Mine', { whisper_model_path = '!!!external!!!', whisper_model_path_external = 'D:/my/model.bin' })
  end)
  LS.setup_all()
  v = mock.source('Mic').filters[1].settings.values
  eq(v.whisper_model_path, '!!!external!!!', 'свой файл стримера не трогаем')
  eq(v.whisper_model_path_external, 'D:/my/model.bin')
end)

-- ---------- слежение за текстом ----------

local function with_overlays(w, m)
  m.add_source('text_gdiplus_v3', 'Live Subtitles (text)', { text = '' })
  m.add_source('browser_source', 'Live Subtitles', { url = OVERLAY .. '?style=classic' })
  m.add_source('browser_source', 'Copy in another scene', { url = 'file:///D:/Stream/live-subtitles/overlay/overlay.html?style=wow' })
  m.add_source('browser_source', 'Alerts', { url = 'https://streamelements.com/overlay/xyz' })
end

test('tick без текстового источника не падает и ничего не шлёт', function()
  local LS = start({ text_source = 'Gone' }, function(w, m) m.add_source('browser_source', 'Live Subtitles', { url = OVERLAY }) end)
  LS.tick()
  LS.tick()
  eq(#mock.source('Live Subtitles').events, 0)
end)

test('tick: новый текст — одно событие live-subtitles каждому оверлею, чужим браузерам — ничего', function()
  local LS = start({}, with_overlays)
  mock.source('Live Subtitles (text)').settings.values.text = 'Hello "chat"'
  LS.tick()
  LS.tick()
  for _, name in ipairs({ 'Live Subtitles', 'Copy in another scene' }) do
    local ev = mock.source(name).events
    eq(#ev, 1, name .. ': событий')
    eq(ev[1].proc, 'javascript_event')
    eq(ev[1].eventName, 'live-subtitles')
    eq(ev[1].json, '{"text":"Hello \\"chat\\""}')
  end
  eq(#mock.source('Alerts').events, 0, 'чужой браузерный источник')
  mock.source('Live Subtitles (text)').settings.values.text = ''
  LS.tick()
  eq(mock.source('Live Subtitles').events[2].json, '{"text":""}', 'очистка тоже доходит')
end)

test('update_overlays: URL меняется только у своего оверлея, последний текст повторяется после перезагрузки', function()
  local LS, s = start({}, with_overlays)
  mock.source('Live Subtitles (text)').settings.values.text = 'Warp to zero'
  LS.tick()
  s.values.style = 'eve-photon'
  s.values.name = 'Pilot'
  script_update(s)
  for _ = 1, 4 do LS.tick() end
  has(mock.source('Live Subtitles').settings.values.url, '?style=classic', 'пока печатают — URL прежний')
  LS.tick()
  local url = mock.source('Live Subtitles').settings.values.url
  has(url, OVERLAY .. '?style=eve-photon', 'через 0,5 с после правки — новый')
  has(url, 'name=Pilot')
  eq(mock.source('Copy in another scene').settings.values.url, 'file:///D:/Stream/live-subtitles/overlay/overlay.html?style=wow', 'копия со своим URL не трогается')
  local before = #mock.source('Live Subtitles').events
  for _ = 1, 14 do LS.tick() end
  eq(#mock.source('Live Subtitles').events, before, 'до 1,5 с повтора нет')
  LS.tick()
  local ev = mock.source('Live Subtitles').events
  eq(#ev, before + 1, 'повтор через 1,5 с')
  eq(ev[#ev].json, '{"text":"Warp to zero"}')
  for _ = 1, 30 do LS.tick() end
  eq(#mock.source('Live Subtitles').events, before + 1, 'повтор один раз')
end)

test('update_overlays: тот же URL не переписывается (оверлей не перезагружается зря)', function()
  local LS, s = start({}, with_overlays)
  local updates = mock.source('Live Subtitles').updates or 0
  ok(updates >= 1, 'при загрузке скрипта URL выставлен сразу')
  script_update(s)
  for _ = 1, 10 do LS.tick() end
  eq(mock.source('Live Subtitles').updates or 0, updates)
end)

test('show_test шлёт оверлеям {"test":true}', function()
  local LS = start({}, with_overlays)
  LS.show_test()
  eq(mock.source('Live Subtitles').events[1].json, '{"test":true}')
  eq(mock.source('Copy in another scene').events[1].json, '{"test":true}')
end)

-- ---------- «Настроить всё» ----------

test('setup_all без LocalVocal: только строка статуса, ничего не создаётся', function()
  local LS = start({ mic = 'Mic' }, function(w, m) mic(w, m) end)
  local before = #mock.world.order
  local status = LS.setup_all()
  has(status, 'LocalVocal', 'статус')
  eq(#mock.world.order, before, 'источников не прибавилось')
  eq(#mock.source('Mic').filters, 0, 'фильтров нет')
end)

test('setup_all без единого микрофона просит выбрать микрофон и ничего не создаёт', function()
  local LS = start({ mic = '' }, function(w, m) localvocal(w); m.add_source('wasapi_output_capture', 'Desktop Audio', {}, m.OBS_SOURCE_AUDIO) end)
  local before = #mock.world.order
  eq(LS.setup_all(), LS.text('need_mic'))
  eq(#mock.world.order, before)
  eq(#mock.source('Desktop Audio').filters, 0, 'звук рабочего стола — не микрофон')
end)

test('setup_all с пустым полем микрофона берёт первый захват входа звука и запоминает его', function()
  local LS, s = start({ mic = '' }, function(w, m)
    localvocal(w)
    m.add_source('wasapi_output_capture', 'Desktop Audio', {}, m.OBS_SOURCE_AUDIO)
    m.add_source('wasapi_input_capture', 'Mic/Aux', {}, m.OBS_SOURCE_AUDIO)
  end)
  LS.setup_all()
  eq(#mock.source('Mic/Aux').filters, 1, 'фильтр на микрофоне')
  eq(s.values.mic, 'Mic/Aux', 'выбор записан в настройки')
end)

test('setup_all с нуля: скрытый текст, оверлей на весь холст, фильтр LocalVocal с нашими настройками', function()
  local LS = start({ mic = 'Mic', style = 'eve-local', name = 'Space Pilot', pack_eve = true }, function(w, m)
    localvocal(w); mic(w, m); w.locale = 'ru-RU'; w.canvas = { 2560, 1440 }
  end)
  local status = LS.setup_all()
  local text = mock.source('Live Subtitles (text)')
  ok(text and text.created, 'текстовый источник создан')
  eq(text.id, 'text_gdiplus_v3', 'тип текста — последняя версия')
  local overlay = mock.source('Live Subtitles')
  ok(overlay and overlay.created, 'оверлей создан')
  eq(overlay.id, 'browser_source')
  has(overlay.settings.values.url, OVERLAY .. '?style=eve-local', 'URL оверлея')
  has(overlay.settings.values.url, 'name=Space%20Pilot')
  has(overlay.settings.values.url, 'packs=eve')
  eq(overlay.settings.values.is_local_file, false, 'режим URL, не локальный файл')
  eq(overlay.settings.values.width, 1920)
  eq(overlay.settings.values.height, 1080)
  eq(overlay.settings.values.shutdown, false, 'не выгружать, когда не виден')
  local items = {}
  for _, item in ipairs(mock.world.scene.items) do items[item.source.name] = item end
  eq(items['Live Subtitles (text)'].visible, false, 'текст скрыт')
  eq(items['Live Subtitles'].visible, true, 'оверлей виден')
  eq(items['Live Subtitles'].bounds.x, 2560, 'оверлей растянут на холст')
  eq(items['Live Subtitles'].bounds.y, 1440)
  local filters = mock.source('Mic').filters
  eq(#filters, 1, 'один фильтр')
  eq(filters[1].name, 'Live Subtitles (LocalVocal)')
  local v = filters[1].settings.values
  eq(v.whisper_language_select, 'ru')
  eq(v.whisper_translate, true)
  eq(v.subtitle_sources, 'Live Subtitles (text)')
  eq(v.initial_prompt, 'Jita, Amarr, tackle, point.')
  eq(v.whisper_model_path, 'Whisper Medium q5 (514Mb)', 'модель по умолчанию')
  has(status, 'Готово', 'статус по-русски')
end)

test('setup_all второй раз ничего не дублирует, чужой фильтр LocalVocal переиспользуется', function()
  local LS = start({ mic = 'Mic', model = 'Whisper Small q5 (181Mb)' }, function(w, m)
    localvocal(w)
    local src = mic(w, m)
    m.add_filter(src, 'transcription_filter_audio_filter', 'My captions', { whisper_language_select = 'en', subtitle_sources = 'Old text', some_user_key = 7 })
  end)
  LS.setup_all()
  LS.setup_all()
  eq(mock.count('Live Subtitles (text)'), 1, 'текст один')
  eq(mock.count('Live Subtitles'), 1, 'оверлей один')
  eq(#mock.world.scene.items, 2, 'в сцене два элемента')
  local filters = mock.source('Mic').filters
  eq(#filters, 1, 'фильтр не добавлен второй раз')
  eq(filters[1].name, 'My captions', 'имя чужого фильтра не меняется')
  eq(filters[1].settings.values.subtitle_sources, 'Live Subtitles (text)')
  eq(filters[1].settings.values.whisper_model_path, 'Whisper Small q5 (181Mb)')
  eq(filters[1].settings.values.some_user_key, 7, 'остальные настройки фильтра целы')
end)

test('«Настроить всё» на своём LocalVocal: внешний файл модели, свои замены и подсказка без набора целы, буфер вывода выключен', function()
  local LS = start({ mic = 'Mic' }, function(w, m)
    localvocal(w)
    local src = mic(w, m)
    m.add_filter(src, 'transcription_filter_audio_filter', 'Mine', {
      whisper_model_path = '!!!external!!!', whisper_model_path_external = 'D:/m.bin',
      filter_words_replace = '[{"key":"x","value":"y"}]', initial_prompt = 'My words', buffered_output = true,
    })
  end)
  LS.setup_all()
  local v = mock.source('Mic').filters[1].settings.values
  eq(v.whisper_model_path, '!!!external!!!', 'свой файл модели не меняется на Medium с закачкой')
  eq(v.filter_words_replace, '[{"key":"x","value":"y"}]', 'свои замены LocalVocal не стираются')
  eq(v.initial_prompt, 'My words', 'без выбранного набора своя подсказка не стирается')
  eq(v.buffered_output, false, 'буферный вывод LocalVocal (строки с прокруткой) ломает ленту')
  eq(v.subtitle_sources, 'Live Subtitles (text)')
  eq(v.whisper_language_select, 'ru')
end)

test('чужой браузерный источник в поле «Оверлей»: URL не переписывается, «Настроить всё» его не трогает, статус объясняет', function()
  local alerts = 'https://streamelements.com/overlay/xyz?token=secret'
  local LS = start({ overlay = 'Alerts', mic = 'Mic' }, function(w, m)
    localvocal(w)
    local src = mic(w, m)
    m.add_filter(src, 'transcription_filter_audio_filter', 'Subs', {})
    m.add_source('text_gdiplus_v3', 'Live Subtitles (text)', { text = '' })
    m.add_source('browser_source', 'Alerts', { url = alerts })
  end)
  for _ = 1, 10 do LS.tick() end
  eq(mock.source('Alerts').settings.values.url, alerts, 'при загрузке и правках чужой URL цел')
  eq(LS.update_overlays(), false)
  eq(LS.status(), LS.text('not_overlay', 'Alerts'))
  eq(LS.setup_all(), LS.text('not_overlay', 'Alerts'))
  eq(mock.source('Alerts').settings.values.url, alerts, '«Настроить всё» тоже не трогает')
  -- пустой браузерный источник с этим именем — можно занять
  LS = start({ overlay = 'Blank' }, function(w, m) m.add_source('browser_source', 'Blank', { url = '' }) end)
  has(mock.source('Blank').settings.values.url, OVERLAY, 'пустой — становится оверлеем')
end)

test('свои наборы идут после встроенных: их правила — последними, их слова — в конце подсказки (Whisper берёт хвост)', function()
  local LS = start({ pack_custom = true, pack_eve = true, pack_friends = true }, function(w, m)
    table.insert(w.fs[PACKS], 'friends.js')
    w.files[PACKS .. '/friends.js'] = "LS.registerPack({ id: 'friends', name: 'Friends', rules: [] });"
    w.files[PACKS .. '/custom.prompt.txt'] = 'Vasyan, Petrovich.'
    m.add_source('browser_source', 'Live Subtitles', { url = OVERLAY })
  end)
  local cfg = LS.read_config(settings({ pack_custom = true, pack_eve = true, pack_friends = true }))
  eq(table.concat(cfg.packs, ','), 'eve,custom,friends')
  has(mock.source('Live Subtitles').settings.values.url, 'packs=eve,custom,friends')
  eq(LS.localvocal_settings(cfg, PACKS).initial_prompt, 'Jita, Amarr, tackle, point. Vasyan, Petrovich.')
end)

-- ---------- окно настроек ----------

test('галки «Свой цвет …»: колбэк OBS (props, property, settings) показывает и прячет выбор цвета без ошибки', function()
  start({})
  local props = script_properties()
  for _, pair in ipairs({ { 'custom_name_color', 'name_color' }, { 'custom_accent', 'accent' } }) do
    local box = mock.obs_properties_get(props, pair[1])
    local fine, err = pcall(box.modified, props, box, settings({ [pair[1]] = true }))
    ok(fine, pair[1] .. ': колбэк упал: ' .. tostring(err))
    eq(mock.obs_properties_get(props, pair[2]).visible, true, pair[2] .. ' виден')
    box.modified(props, box, settings({ [pair[1]] = false }))
    eq(mock.obs_properties_get(props, pair[2]).visible, false, pair[2] .. ' спрятан')
  end
end)

test('script_properties: подписи по локали, микрофоны из аудиоисточников, галка на каждый набор, кнопки', function()
  local LS = start({}, function(w, m)
    w.locale = 'ru-RU'
    mic(w, m)
    m.add_source('browser_source', 'Live Subtitles', { url = OVERLAY })
    m.add_source('text_gdiplus_v3', 'Some text', {})
  end)
  local props = script_properties()
  local p = mock.obs_properties_get(props, 'mic')
  eq(p.desc, 'Микрофон')
  local values = {}
  for _, item in ipairs(p.items) do values[#values + 1] = item.value end
  ok(table.concat(values, ','):find('Mic', 1, true), 'аудиоисточник в списке микрофонов')
  ok(not table.concat(values, ','):find('Live Subtitles', 1, true), 'браузер без звука не микрофон')
  for _, id in ipairs({ 'pack_custom', 'pack_eve', 'pack_wow' }) do ok(mock.obs_properties_get(props, id), 'галка ' .. id) end
  eq(mock.obs_properties_get(props, 'pack_eve').desc, 'EVE Online')
  ok(mock.obs_properties_get(props, 'live_text'), 'галка «Текст по ходу речи»')
  ok(mock.obs_properties_get(props, 'setup').kind == 'button', 'кнопка «Настроить всё»')
  ok(mock.obs_properties_get(props, 'test').kind == 'button', 'кнопка «Показать тест»')
  LS = start({}, function(w) w.locale = 'en-US' end)
  eq(mock.obs_properties_get(script_properties(), 'mic').desc, 'Microphone', 'по-английски')
end)

test('script_load запускает таймер 100 мс, script_unload снимает', function()
  start({})
  eq(#mock.world.timers, 1)
  eq(mock.world.timers[1].ms, 100)
  script_unload()
  eq(#mock.world.timers, 0)
end)

if #failures > 0 then return 'FAIL ' .. #failures .. ' of ' .. (#failures + #passed) .. '\n' .. table.concat(failures, '\n') end
return 'ok ' .. #passed
