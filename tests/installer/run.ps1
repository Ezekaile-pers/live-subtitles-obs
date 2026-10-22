# Tests for installer/LiveSubtitlesSetup.cs. Builds the exe into a temp folder (installer/build.ps1), loads it as an
# assembly and checks the static logic, then runs "--auto" against a fake OBS config (APPDATA, LOCALAPPDATA, PROGRAMDATA
# and TEMP pointed into a temp folder). Prints "ok N" or "FAIL ...". ASCII only: Windows PowerShell 5.1 reads BOM-less
# files as CP1251, so non-ASCII test strings are built from \uXXXX escapes.
param([string]$Exe = '')
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent $here)
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ls-setup-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$failures = New-Object System.Collections.ArrayList
$script:passed = 0

function Check([string]$name, [scriptblock]$body) {
  try { & $body; $script:passed++ } catch { [void]$failures.Add($name + ': ' + $_.Exception.Message) }
}
function Eq($actual, $expected, [string]$what) {
  if ($actual -cne $expected) { throw ($what + ': expected [' + $expected + '], got [' + $actual + ']') }
}
function U([string]$s) { [regex]::Unescape($s) }
function Utf8File([string]$path, [string]$text, [bool]$bom = $false) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  [IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($bom)))
}

$nl = "`n"
$collection = '{' + $nl + '    "name": "Test",' + $nl + '    "sources": [],' + $nl + '    "modules": {' + $nl + '        "scripts-tool": [],' + $nl + '        "output-timer": {}' + $nl + '    }' + $nl + '}'
$ours = 'C:\Users\x\AppData\Local\Programs\LiveSubtitles\live-subtitles.lua'
$oursEntry = '{"path": "C:/Users/x/AppData/Local/Programs/LiveSubtitles/live-subtitles.lua", "settings": {"style": "classic"}}'

# A collection the way OBS writes it, with Live Subtitles already added: another script and another source carry the
# same keys ("device", a LocalVocal filter) and must stay untouched.
function ObsCollection([string]$scriptPath, [string]$scriptSettings, [string]$filterSettings) {
  return '{' + $nl +
    '    "name": "Test",' + $nl +
    '    "sources": [' + $nl +
    '        {' + $nl +
    '            "name": "Desktop",' + $nl +
    '            "id": "wasapi_output_capture",' + $nl +
    '            "settings": {"device": "keep-me", "device_id": "default"},' + $nl +
    '            "filters": [{"id": "transcription_filter_audio_filter", "name": "Other", "settings": {"audio_ctx": 0}}]' + $nl +
    '        },' + $nl +
    '        {' + $nl +
    '            "name": "Mic",' + $nl +
    '            "id": "wasapi_input_capture",' + $nl +
    '            "settings": {"device_id": "{0.0.1.00000000}.{abc}"},' + $nl +
    '            "filters": [' + $nl +
    '                {"id": "noise_suppress_filter_v2", "name": "Noise", "settings": {"method": "rnnoise"}},' + $nl +
    '                {"id": "transcription_filter_audio_filter", "versioned_id": "transcription_filter_audio_filter", "name": "LocalVocal", "settings": ' + $filterSettings + '}' + $nl +
    '            ]' + $nl +
    '        }' + $nl +
    '    ],' + $nl +
    '    "modules": {' + $nl +
    '        "scripts-tool": [' + $nl +
    '            {"path": "C:/x/other.lua", "settings": {"device": "keep-me"}},' + $nl +
    '            {"path": "' + $scriptPath + '", "settings": ' + $scriptSettings + '}' + $nl +
    '        ],' + $nl +
    '        "output-timer": {}' + $nl +
    '    }' + $nl +
    '}'
}

try {
  if (-not $Exe) {
    $out = Join-Path $tmp 'out'
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'installer\build.ps1') -Out $out | Out-Null
    $Exe = Join-Path $out 'LiveSubtitlesSetup.exe'
  }
  if (-not (Test-Path $Exe)) { throw ('no exe built: ' + $Exe) }
  [void][Reflection.Assembly]::LoadFile($Exe)
  $S = [LiveSubtitles.Setup]

  Check 'AddScript: into an empty scripts-tool, the rest of the file byte for byte' {
    $res = $S::AddScript($collection, $ours, '{"style": "classic"}')
    Eq ($res.Replace($oursEntry, '')) $collection 'only the entry is inserted'
    if (-not $res.Contains('"scripts-tool": [' + $oursEntry + ']')) { throw ('entry not in scripts-tool: ' + $res) }
    Eq ($S::AddScript($res, 'D:\Stream\live-subtitles\live-subtitles.lua', '{}')) $res 'already in OBS (any folder) - no second copy'
  }

  Check 'AddScript: next to another script, without scripts-tool, without modules' {
    $other = $collection.Replace('"scripts-tool": []', '"scripts-tool": [{"path": "C:/x/other.lua", "settings": {}}]')
    $res = $S::AddScript($other, $ours, '{"style": "classic"}')
    if (-not $res.Contains('"scripts-tool": [' + $oursEntry + ',{"path": "C:/x/other.lua"')) { throw ('comma placement: ' + $res) }
    $noTool = $collection.Replace('"scripts-tool": [],', '')
    $res = $S::AddScript($noTool, $ours, '{"style": "classic"}')
    Eq ((ConvertFrom-Json $res).modules.'scripts-tool'[0].path) 'C:/Users/x/AppData/Local/Programs/LiveSubtitles/live-subtitles.lua' 'scripts-tool created'
    Eq ((ConvertFrom-Json $res).modules.'output-timer'.GetType().Name) 'PSCustomObject' 'other modules kept'
    $noModules = '{"name": "Bare", "sources": []}'
    $res = $S::AddScript($noModules, $ours, '{}')
    Eq ((ConvertFrom-Json $res).modules.'scripts-tool'[0].path) 'C:/Users/x/AppData/Local/Programs/LiveSubtitles/live-subtitles.lua' 'modules created'
    Eq ((ConvertFrom-Json $res).name) 'Bare' 'root kept'
  }

  Check 'AddScript: Cyrillic path and quotes in the name stay valid JSON; broken file is refused' {
    $p = 'C:\Users\' + (U '\u041f\u0438\u043b\u043e\u0442') + '\Live Subtitles\live-subtitles.lua'
    $res = $S::AddScript($collection, $p, $S::PresetSettings('wow', 'Ez "the" One'))
    $entry = (ConvertFrom-Json $res).modules.'scripts-tool'[0]
    Eq $entry.path ($p.Replace('\', '/')) 'path with forward slashes'
    Eq $entry.settings.name 'Ez "the" One' 'name escaped'
    $refused = $false
    try { [void]$S::AddScript('{"modules": {', $ours, '{}') } catch { $refused = $true }
    if (-not $refused) { throw 'broken JSON was accepted' }
  }

  Check 'PresetSettings: basic by default, EVE and WoW optional' {
    Eq ($S::PresetSettings('basic', '')) '{"style": "classic"}' 'basic'
    Eq ($S::PresetSettings('', '  ')) '{"style": "classic"}' 'unknown -> basic'
    Eq ($S::PresetSettings('eve', 'Pilot')) '{"style": "eve-photon", "pack_eve": true, "name": "Pilot"}' 'eve'
    Eq ($S::PresetSettings('wow', 'Ezekaile')) '{"style": "wow", "pack_wow": true, "name": "Ezekaile"}' 'wow'
    Eq ($S::PresetSettings('basic', '', 'cpu', 'medium')) '{"style": "classic", "device": "cpu"}' 'processor'
    Eq ($S::PresetSettings('wow', 'Ezekaile', 'gpu', 'medium')) '{"style": "wow", "pack_wow": true, "name": "Ezekaile"}' 'graphics card is the script default'
    Eq ($S::PresetSettings('basic', '', 'cpu', 'small')) '{"style": "classic", "device": "cpu", "model": "Whisper Small q5 (181Mb)"}' 'processor with Small'
    Eq ($S::PresetSettings('eve', 'Pilot', 'gpu', 'large')) '{"style": "eve-photon", "pack_eve": true, "name": "Pilot", "model": "Whisper Large v3 q5 (1Gb)"}' 'Large'
    Eq ($S::PresetSettings('wow', '', 'gpu', 'medium')) '{"style": "wow", "pack_wow": true}' 'Medium is the script default'
    Eq ($S::PresetSettings('wow', '', 'gpu', 'tiny')) '{"style": "wow", "pack_wow": true}' 'unknown model: script default'
  }

  Check 'SetScriptSettings: the added script gets the new device and model in place, the rest of the file byte for byte' {
    $before = ObsCollection 'C:/Games/Live Subtitles/live-subtitles.lua' ('{"mic": "' + (U '\u041c\u0438\u043a') + '", "name": "Ez \"the\" One", "device": "gpu", "colors": {"name": "#ff0"}}') '{}'
    $res = $S::SetScriptSettings($before, '{"device": "cpu", "model": "Whisper Small q5 (181Mb)"}')
    $c = ConvertFrom-Json $res
    $entry = $c.modules.'scripts-tool'[1]
    Eq $entry.settings.device 'cpu' 'device replaced'
    Eq $entry.settings.model 'Whisper Small q5 (181Mb)' 'model added'
    Eq $entry.settings.mic (U '\u041c\u0438\u043a') 'Cyrillic kept'
    Eq $entry.settings.name 'Ez "the" One' 'escaped quotes kept'
    Eq $entry.settings.colors.name '#ff0' 'nested object kept'
    Eq $c.modules.'scripts-tool'[0].settings.device 'keep-me' 'another script untouched'
    Eq $c.sources[0].settings.device 'keep-me' 'source settings untouched'
    $open = $before.IndexOf('"settings": {"mic"') + 12
    $close = $before.IndexOf('"#ff0"}}') + 7
    if (-not $res.StartsWith($before.Substring(0, $open + 1))) { throw ('text before the settings changed: ' + $res) }
    if (-not $res.EndsWith($before.Substring($close))) { throw ('text after the settings changed: ' + $res) }
    Eq ($S::SetScriptSettings($before, '{}')) $before 'nothing to change'
    $none = ObsCollection 'C:/x/not-ours.lua' '{"device": "gpu"}' '{}'
    Eq ($S::SetScriptSettings($none, '{"device": "cpu"}')) $none 'no Live Subtitles script: unchanged'
    $refused = $false
    try { [void]$S::SetScriptSettings('{"modules": {', '{"device": "cpu"}') } catch { $refused = $true }
    if (-not $refused) { throw 'broken JSON was accepted' }
  }

  Check 'UpdateLocalVocal: the filter on the script microphone gets the device, model and speed of Set up everything' {
    $dir = Join-Path $tmp ('ulv\' + (U '\u0418\u0433\u0440\u044b'))
    Utf8File (Join-Path $dir 'models\ggml-small-q5_1.bin') 'x'
    $slash = $dir.Replace('\', '/')
    $script = $slash + '/live-subtitles.lua'
    $old = '{"whisper_model_path": "!!!external!!!", "whisper_model_path_external": "' + $slash + '/models/ggml-medium-q5_0.bin", "partial_group": true, "backend_device": 0, "initial_prompt": "Tom, Mage", "vad_threshold": 0.5}'
    $res = $S::UpdateLocalVocal((ObsCollection $script '{"mic": "Mic", "device": "cpu", "model": "Whisper Small q5 (181Mb)"}' $old))
    $c = ConvertFrom-Json $res
    $f = $c.sources[1].filters[1].settings
    Eq $f.backend_device -1 'processor'
    Eq $f.n_threads ($S::CpuThreads([Environment]::ProcessorCount)) 'processor threads'
    Eq $f.partial_group $false 'one translation per phrase'
    Eq $f.partial_latency 1100 'partial latency'
    Eq $f.audio_ctx 576 'audio window'
    Eq $f.'beam_search.beam_size' 2 'two beams'
    Eq $f.whisper_model_path '!!!external!!!' 'model file from the module'
    Eq $f.whisper_model_path_external ($slash + '/models/ggml-small-q5_1.bin') 'Small from the models folder'
    Eq $f.initial_prompt 'Tom, Mage' 'the hint stays'
    Eq $f.vad_threshold 0.5 'other LocalVocal settings stay'
    Eq $c.sources[0].filters[0].settings.audio_ctx 0 'a LocalVocal filter on another source stays'
    Eq ($S::UpdateLocalVocal($res)) $res 'second run: nothing to change'

    $f = (ConvertFrom-Json ($S::UpdateLocalVocal((ObsCollection $script '{"mic": "Mic", "live_text": true}' '{"partial_group": false, "backend_device": -1, "n_threads": 8}')))).sources[1].filters[1].settings
    Eq $f.backend_device 0 'graphics card by default'
    Eq $f.n_threads 4 'four threads on the graphics card'
    Eq $f.partial_group $true 'Text while speaking'
    Eq $f.whisper_model_path 'Whisper Medium q5 (514Mb)' 'Medium by default, by name: no file in the module, LocalVocal downloads it'

    $f = (ConvertFrom-Json ($S::UpdateLocalVocal((ObsCollection $script '{"mic": "Mic", "device": "keep", "model": ""}' '{"backend_device": -1, "whisper_model_path": "Whisper Large v3 q5 (1Gb)"}')))).sources[1].filters[1].settings
    Eq $f.backend_device -1 'device kept'
    if ($f.PSObject.Properties['n_threads']) { throw 'threads written for keep' }
    Eq $f.whisper_model_path 'Whisper Large v3 q5 (1Gb)' 'model kept'
    Eq $f.audio_ctx 576 'speed applied anyway'

    $own = '{"whisper_model_path": "!!!external!!!", "whisper_model_path_external": "D:/Models/my-whisper.bin"}'
    $f = (ConvertFrom-Json ($S::UpdateLocalVocal((ObsCollection $script '{"mic": "Mic", "model": "Whisper Small q5 (181Mb)"}' $own)))).sources[1].filters[1].settings
    Eq $f.whisper_model_path_external 'D:/Models/my-whisper.bin' 'the streamer own model file stays'

    $aux = '{"AuxAudioDevice1": {"name": "Mic/Aux", "id": "wasapi_input_capture", "filters": [{"id": "transcription_filter_audio_filter", "settings": {"backend_device": 0}}]}, "sources": [], "modules": {"scripts-tool": [{"path": "' + $script + '", "settings": {"mic": "Mic/Aux", "device": "cpu"}}]}}'
    Eq (ConvertFrom-Json ($S::UpdateLocalVocal($aux))).AuxAudioDevice1.filters[0].settings.backend_device -1 'the global Mic/Aux device'

    $json = ObsCollection $script '{"device": "cpu"}' '{"backend_device": 0}'
    Eq ($S::UpdateLocalVocal($json)) $json 'no microphone in the script settings yet'
    $json = ObsCollection 'C:/x/not-ours.lua' '{"mic": "Mic", "device": "cpu"}' '{"backend_device": 0}'
    Eq ($S::UpdateLocalVocal($json)) $json 'no Live Subtitles script'
  }

  Check 'CpuThreads, ScriptDevice and ScriptModelId: processor threads and what the window preselects on an update' {
    Eq ($S::CpuThreads(12)) 8 '12 logical processors'
    Eq ($S::CpuThreads(8)) 6 '8 logical processors'
    Eq ($S::CpuThreads(4)) 4 'at least 4'
    Eq ($S::CpuThreads(32)) 8 'at most 8'
    $script = 'C:/Games/LiveSubtitles/live-subtitles.lua'
    Eq ($S::ScriptDevice((ObsCollection $script '{"mic": "Mic"}' '{}'))) 'gpu' 'script default'
    Eq ($S::ScriptDevice((ObsCollection $script '{"device": "cpu"}' '{}'))) 'cpu' 'processor'
    Eq ($S::ScriptDevice((ObsCollection $script '{"device": "keep"}' '{}'))) 'keep' 'keep'
    Eq ($S::ScriptDevice((ObsCollection 'C:/x/no.lua' '{}' '{}'))) $null 'no script'
    Eq ($S::ScriptDevice($null)) $null 'no collection'
    Eq ($S::ScriptModelId((ObsCollection $script '{}' '{}'))) 'medium' 'script default'
    Eq ($S::ScriptModelId((ObsCollection $script '{"model": "Whisper Small q5 (181Mb)"}' '{}'))) 'small' 'Small'
    Eq ($S::ScriptModelId((ObsCollection $script '{"model": ""}' '{}'))) '' 'keep'
    Eq ($S::ScriptModelId((ObsCollection 'C:/x/no.lua' '{}' '{}'))) $null 'no script'
    Eq ($S::ScriptPreset((ObsCollection $script '{"style": "eve-local"}' '{}'))) 'eve' 'EVE Local'
    Eq ($S::ScriptPreset((ObsCollection $script '{"style": "wow"}' '{}'))) 'wow' 'WoW'
    Eq ($S::ScriptPreset((ObsCollection $script '{"style": "box"}' '{}'))) 'basic' 'other styles: basic'
    Eq ($S::ScriptPreset((ObsCollection $script '{}' '{}'))) 'basic' 'script default'
    Eq ($S::ScriptPreset((ObsCollection 'C:/x/no.lua' '{}' '{}'))) $null 'no script: no preset'
    Eq ($S::ScriptSetting((ObsCollection $script '{"name": "Space Pilot"}' '{}'), 'name', '')) 'Space Pilot' 'name'
    Eq ($S::ScriptSetting((ObsCollection $script '{}' '{}'), 'name', '')) '' 'no name'
  }

  Check 'PickLocalVocalAsset: official Windows installer by GPU flavor' {
    $base = 'https://github.com/royshil/obs-localvocal/releases/download/0.6.2/obs-localvocal-0.6.2-windows-x64-'
    $json = '{"tag_name":"0.6.2","assets":[{"name":"a","browser_download_url":"' + $base + 'generic.zip"},{"name":"b","browser_download_url":"' + $base + 'generic-Installer.exe"},{"name":"c","browser_download_url":"' + $base + 'nvidia-Installer.exe"}]}'
    Eq ($S::PickLocalVocalAsset($json, 'generic')) ($base + 'generic-Installer.exe') 'generic'
    Eq ($S::PickLocalVocalAsset($json, 'nvidia')) ($base + 'nvidia-Installer.exe') 'nvidia'
    Eq ($S::PickLocalVocalAsset('{"assets":[]}', 'generic')) $null 'none'
  }

  Check 'ReadIniValue: OBS ini with BOM' {
    $ini = Join-Path $tmp 'ini\user.ini'
    Utf8File $ini ('[General]' + "`r`n" + 'Language=ru-RU' + "`r`n" + '[Basic]' + "`r`n" + 'SceneCollection=My Scenes' + "`r`n" + 'SceneCollectionFile=My_Scenes.json' + "`r`n") $true
    Eq ($S::ReadIniValue($ini, 'Basic', 'SceneCollectionFile')) 'My_Scenes.json' 'value'
    Eq ($S::ReadIniValue($ini, 'General', 'SceneCollectionFile')) $null 'other section'
    Eq ($S::ReadIniValue((Join-Path $tmp 'nope.ini'), 'Basic', 'X')) $null 'no file'
  }

  Check 'CurrentCollectionPath and CurrentCollectionName: from user.ini, the name as OBS shows it' {
    $saved = $env:APPDATA
    try {
      $env:APPDATA = Join-Path $tmp 'names'
      Utf8File (Join-Path $env:APPDATA 'obs-studio\user.ini') ('[Basic]' + "`r`n" + 'SceneCollection=WoW Forever' + "`r`n" + 'SceneCollectionFile=WoW_Forever.json' + "`r`n") $true
      Utf8File (Join-Path $env:APPDATA 'obs-studio\basic\scenes\WoW_Forever.json') $collection
      Eq ($S::CurrentCollectionPath()) (Join-Path $env:APPDATA 'obs-studio\basic\scenes\WoW_Forever.json') 'path'
      Eq ($S::CurrentCollectionName()) 'WoW Forever' 'name with spaces, not the file name'
      $env:APPDATA = Join-Path $tmp 'nothing'
      Eq ($S::CurrentCollectionPath()) $null 'no OBS config'
      Eq ($S::CurrentCollectionName()) $null 'no name'
    } finally { $env:APPDATA = $saved }
  }

  Check 'ExtractModule: the streamer custom pack survives updates, paths outside are refused' {
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zipPath = Join-Path $tmp 'm.zip'
    $zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
    foreach ($pair in @(@('live-subtitles.lua', 'lua'), @('packs/custom.js', 'template'), @('packs/eve.js', 'eve'))) {
      $w = New-Object IO.StreamWriter(($zip.CreateEntry($pair[0])).Open()); $w.Write($pair[1]); $w.Dispose()
    }
    $zip.Dispose()
    $dir = Join-Path $tmp 'install'
    Utf8File (Join-Path $dir 'packs\custom.js') 'MINE'
    Utf8File (Join-Path $dir 'packs\eve.js') 'old'
    $fs = [IO.File]::OpenRead($zipPath); [void]$S::ExtractModule($fs, $dir); $fs.Dispose()
    Eq ([IO.File]::ReadAllText((Join-Path $dir 'packs\custom.js'))) 'MINE' 'custom pack kept'
    Eq ([IO.File]::ReadAllText((Join-Path $dir 'packs\eve.js'))) 'eve' 'pack updated'
    Eq ([IO.File]::ReadAllText((Join-Path $dir 'live-subtitles.lua'))) 'lua' 'script written'
    $evilZip = Join-Path $tmp 'evil.zip'
    $zip = [IO.Compression.ZipFile]::Open($evilZip, 'Create')
    $w = New-Object IO.StreamWriter(($zip.CreateEntry('../evil.txt')).Open()); $w.Write('x'); $w.Dispose(); $zip.Dispose()
    $refused = $false
    $fs = [IO.File]::OpenRead($evilZip)
    try { [void]$S::ExtractModule($fs, $dir) } catch { $refused = $true } finally { $fs.Dispose() }
    if (-not $refused) { throw 'zip entry outside the folder was extracted' }
    if (Test-Path (Join-Path $tmp 'evil.txt')) { throw 'evil.txt written' }
  }

  Check 'Download: local file with SHA-256 check, a wrong hash leaves nothing behind' {
    $src = Join-Path $tmp 'src.bin'
    Utf8File $src 'hello model'
    $sha = (Get-FileHash $src -Algorithm SHA256).Hash.ToLower()
    $target = Join-Path $tmp 'dl\models\m.bin'
    $S::Download((New-Object Uri $src).AbsoluteUri, $target, $sha, $null, $null)
    Eq ([IO.File]::ReadAllText($target)) 'hello model' 'content'
    if (Test-Path ($target + '.part')) { throw 'part file left' }
    $bad = Join-Path $tmp 'dl\models\bad.bin'
    $refused = $false
    try { $S::Download((New-Object Uri $src).AbsoluteUri, $bad, ('0' * 64), $null, $null) } catch { $refused = $true }
    if (-not $refused) { throw 'wrong hash accepted' }
    if ((Test-Path $bad) -or (Test-Path ($bad + '.part'))) { throw 'files left after a wrong hash' }
    $plain = Join-Path $tmp 'dl\LocalVocal-Installer.exe'
    $S::Download((New-Object Uri $src).AbsoluteUri, $plain, '', $null, $null)
    Eq ([IO.File]::ReadAllText($plain)) 'hello model' 'empty hash = no check (LocalVocal installer)'
  }

  Check 'PlaceModel: into the chosen folder\models; reuses the copy LocalVocal has; takes the file next to the installer' {
    $saved = $env:APPDATA
    try {
      $env:APPDATA = Join-Path $tmp 'pm-appdata'
      $payload = Join-Path $tmp 'pm-src.bin'
      Utf8File $payload 'tiny model'
      $sha = (Get-FileHash $payload -Algorithm SHA256).Hash.ToLower()
      $m = New-Object LiveSubtitles.ModelInfo('t', 'Whisper Test', 'ggml-test', 'ggml-test.bin', $sha)
      $dir = Join-Path $tmp ('pm-install\' + (U '\u0418\u0433\u0440\u044b') + '\Live Subtitles')
      $beside = Join-Path (Split-Path -Parent $Exe) 'ggml-test.bin'
      Copy-Item $payload $beside
      try { Eq ($S::PlaceModel($m, $dir, $null, $null, $null)) 'beside' 'from the installer folder' } finally { Remove-Item $beside }
      Eq ([IO.File]::ReadAllText((Join-Path $dir 'models\ggml-test.bin'))) 'tiny model' 'copied into the chosen folder'
      Eq ($S::PlaceModel($m, $dir, $null, $null, $null)) 'present' 'second run: already there'
      $dir2 = Join-Path $tmp 'pm-install2'
      Utf8File (Join-Path $env:APPDATA 'obs-studio\plugin_config\obs-localvocal\models\ggml-test\ggml-test.bin') 'tiny model'
      Eq ($S::PlaceModel($m, $dir2, $null, $null, $null)) 'localvocal' 'the copy LocalVocal downloaded is reused'
      if (Test-Path (Join-Path $dir2 'models\ggml-test.bin')) { throw 'a second copy was made' }
    } finally { $env:APPDATA = $saved }
  }

  Check 'ExistingInstallDir: an update goes where the module already is; EnsureWritable refuses a bad folder' {
    $saved = $env:APPDATA
    try {
      $env:APPDATA = Join-Path $tmp 'ex-appdata'
      $old = Join-Path $tmp 'ex-old\LiveSubtitles'
      Utf8File (Join-Path $old 'live-subtitles.lua') '--'
      Utf8File (Join-Path $env:APPDATA 'obs-studio\user.ini') ('[Basic]' + "`r`n" + 'SceneCollectionFile=Main.json' + "`r`n")
      Utf8File (Join-Path $env:APPDATA 'obs-studio\basic\scenes\Main.json') ($S::AddScript($collection, (Join-Path $old 'live-subtitles.lua'), '{}'))
      Eq ($S::ExistingInstallDir()) $old 'found'
      Remove-Item -Recurse -Force $old
      Eq ($S::ExistingInstallDir()) $null 'folder gone: no suggestion'
    } finally { $env:APPDATA = $saved }
    $S::EnsureWritable((Join-Path $tmp 'writable\Live Subtitles'))
    $refused = $false
    try { $S::EnsureWritable('C:\bad<folder>') } catch { $refused = $true }
    if (-not $refused) { throw 'a bad folder was accepted' }
  }

  Check 'Models: names, folders, files and hashes match the LocalVocal catalog' {
    $catalog = 'C:\ProgramData\obs-studio\plugins\obs-localvocal\data\models\models_directory.json'
    if (-not (Test-Path $catalog)) { return }
    $models = (Get-Content -Raw -Encoding UTF8 $catalog | ConvertFrom-Json).models
    foreach ($m in $S::Models) {
      $entry = $models | Where-Object { $_.friendly_name -eq $m.Name } | Select-Object -First 1
      if ($entry -eq $null) { throw ('not in catalog: ' + $m.Name) }
      Eq $m.Folder $entry.local_folder_name ($m.Name + ' folder')
      Eq $m.Url $entry.files[0].url ($m.Name + ' url')
      Eq $m.Sha256 $entry.files[0].sha256 ($m.Name + ' sha256')
    }
    Eq $S::Models[0].Name 'Whisper Medium q5 (514Mb)' 'Medium is the default, like in the script'
  }

  Check 'auto install against a fake OBS config: module, script in the current collection, backup' {
    if (Get-Process obs64 -ErrorAction SilentlyContinue) { return } # OBS is open: the script step is skipped by design
    $fake = Join-Path $tmp 'fake'
    $appdata = Join-Path $fake 'Roaming'; $local = Join-Path $fake 'Local'; $pd = Join-Path $fake 'ProgramData'; $temp = Join-Path $fake 'Temp'
    foreach ($d in @($local, $pd, $temp)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    Utf8File (Join-Path $appdata 'obs-studio\user.ini') ('[Basic]' + "`r`n" + 'SceneCollection=Test' + "`r`n" + 'SceneCollectionFile=Test.json' + "`r`n") $true
    $scenes = Join-Path $appdata 'obs-studio\basic\scenes\Test.json'
    Utf8File $scenes $collection
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe, '--auto --no-localvocal --model small --no-model --preset eve --name "Space Pilot" --device cpu'
    $psi.UseShellExecute = $false
    $psi.EnvironmentVariables['APPDATA'] = $appdata
    $psi.EnvironmentVariables['LOCALAPPDATA'] = $local
    $psi.EnvironmentVariables['PROGRAMDATA'] = $pd
    $psi.EnvironmentVariables['TEMP'] = $temp
    $psi.EnvironmentVariables['TMP'] = $temp
    $p = [Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit(120000)) { $p.Kill(); throw 'installer did not finish' }
    $log = Join-Path $temp 'LiveSubtitlesSetup.log'
    $logText = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '(no log)' }
    Eq $p.ExitCode 0 ('exit code; log: ' + $logText)
    $dir = Join-Path $local 'Programs\LiveSubtitles'
    foreach ($f in @('live-subtitles.lua', 'overlay\overlay.html', 'overlay\clean.js', 'packs\eve.js', 'packs\profanity.js', 'README.md', 'CREDITS.md', 'LICENSE')) {
      if (-not (Test-Path (Join-Path $dir $f))) { throw ('not installed: ' + $f) }
    }
    if (Test-Path (Join-Path $dir 'tests')) { throw 'dev tests must not be installed' }
    $entry = (Get-Content -Raw -Encoding UTF8 $scenes | ConvertFrom-Json).modules.'scripts-tool'[0]
    Eq $entry.path ((Join-Path $dir 'live-subtitles.lua').Replace('\', '/')) 'script path'
    Eq $entry.settings.style 'eve-photon' 'preset style'
    Eq $entry.settings.pack_eve $true 'preset pack'
    Eq $entry.settings.name 'Space Pilot' 'speaker name'
    Eq $entry.settings.device 'cpu' 'translation on the processor'
    Eq $entry.settings.model 'Whisper Small q5 (181Mb)' 'the chosen model reaches the script'
    if (Test-Path (Join-Path $dir 'models')) { throw '--no-model downloaded a model' }
    Eq ([IO.File]::ReadAllText($scenes + '.before-live-subtitles')) $collection 'backup of the collection'
  }

  Check 'auto install into a chosen folder (another drive, spaces, Cyrillic)' {
    if (Get-Process obs64 -ErrorAction SilentlyContinue) { return }
    $fake = Join-Path $tmp 'fake2'
    $appdata = Join-Path $fake 'Roaming'; $temp = Join-Path $fake 'Temp'
    foreach ($d in @((Join-Path $fake 'Local'), (Join-Path $fake 'ProgramData'), $temp)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    Utf8File (Join-Path $appdata 'obs-studio\user.ini') ('[Basic]' + "`r`n" + 'SceneCollectionFile=Test.json' + "`r`n") $true
    $scenes = Join-Path $appdata 'obs-studio\basic\scenes\Test.json'
    Utf8File $scenes $collection
    $dir = Join-Path $fake ('D drive\' + (U '\u0418\u0433\u0440\u044b') + '\Live Subtitles')
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe, ('--auto --no-localvocal --model none --dir "' + $dir + '"')
    $psi.UseShellExecute = $false
    $psi.EnvironmentVariables['APPDATA'] = $appdata
    $psi.EnvironmentVariables['LOCALAPPDATA'] = (Join-Path $fake 'Local')
    $psi.EnvironmentVariables['PROGRAMDATA'] = (Join-Path $fake 'ProgramData')
    $psi.EnvironmentVariables['TEMP'] = $temp
    $psi.EnvironmentVariables['TMP'] = $temp
    $p = [Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit(120000)) { $p.Kill(); throw 'installer did not finish' }
    $log = Join-Path $temp 'LiveSubtitlesSetup.log'
    Eq $p.ExitCode 0 ('exit code; log: ' + $(if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '(no log)' }))
    if (-not (Test-Path (Join-Path $dir 'live-subtitles.lua'))) { throw 'module not in the chosen folder' }
    if (Test-Path (Join-Path $fake 'Local\Programs\LiveSubtitles')) { throw 'the default folder was used anyway' }
    $entry = (Get-Content -Raw -Encoding UTF8 $scenes | ConvertFrom-Json).modules.'scripts-tool'[0]
    Eq $entry.path ((Join-Path $dir 'live-subtitles.lua').Replace('\', '/')) 'script path in the chosen folder'
    Eq $entry.settings.style 'classic' 'basic style by default'
  }

  Check 'auto update: the added script and its LocalVocal filter move to the processor and Small, OBS needs only a start' {
    if (Get-Process obs64 -ErrorAction SilentlyContinue) { return }
    $fake = Join-Path $tmp 'upd'
    $appdata = Join-Path $fake 'Roaming'; $temp = Join-Path $fake 'Temp'
    foreach ($d in @((Join-Path $fake 'Local'), (Join-Path $fake 'ProgramData'), $temp)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    $dir = Join-Path $fake 'Stream\LiveSubtitles'
    Utf8File (Join-Path $dir 'live-subtitles.lua') '-- old version'
    Utf8File (Join-Path $dir 'models\ggml-small-q5_1.bin') 'x'
    $slash = $dir.Replace('\', '/')
    $filter = '{"whisper_model_path": "!!!external!!!", "whisper_model_path_external": "' + $slash + '/models/ggml-medium-q5_0.bin", "partial_group": true, "backend_device": 0}'
    $old = ObsCollection ($slash + '/live-subtitles.lua') '{"mic": "Mic", "style": "wow", "name": "Space Pilot"}' $filter
    Utf8File (Join-Path $appdata 'obs-studio\user.ini') ('[Basic]' + "`r`n" + 'SceneCollectionFile=Test.json' + "`r`n")
    $scenes = Join-Path $appdata 'obs-studio\basic\scenes\Test.json'
    Utf8File $scenes $old
    $psi = New-Object Diagnostics.ProcessStartInfo $Exe, '--auto --no-localvocal --no-model --model small --device cpu --preset eve'
    $psi.UseShellExecute = $false
    $psi.EnvironmentVariables['APPDATA'] = $appdata
    $psi.EnvironmentVariables['LOCALAPPDATA'] = (Join-Path $fake 'Local')
    $psi.EnvironmentVariables['PROGRAMDATA'] = (Join-Path $fake 'ProgramData')
    $psi.EnvironmentVariables['TEMP'] = $temp
    $psi.EnvironmentVariables['TMP'] = $temp
    $p = [Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit(120000)) { $p.Kill(); throw 'installer did not finish' }
    $log = Join-Path $temp 'LiveSubtitlesSetup.log'
    $logText = if (Test-Path $log) { [IO.File]::ReadAllText($log) } else { '(no log)' }
    Eq $p.ExitCode 0 ('exit code; log: ' + $logText)
    if ([IO.File]::ReadAllText((Join-Path $dir 'live-subtitles.lua')) -eq '-- old version') { throw 'the module was not updated where OBS takes it' }
    $c = Get-Content -Raw -Encoding UTF8 $scenes | ConvertFrom-Json
    $entry = $c.modules.'scripts-tool'[1]
    Eq $entry.settings.device 'cpu' 'script: processor'
    Eq $entry.settings.model 'Whisper Small q5 (181Mb)' 'script: Small'
    Eq $entry.settings.style 'wow' 'the style of an added script stays (presets are for new installs)'
    Eq $entry.settings.name 'Space Pilot' 'name stays'
    $f = $c.sources[1].filters[1].settings
    Eq $f.backend_device -1 'filter: processor'
    Eq $f.partial_group $false 'filter: one translation per phrase'
    Eq $f.audio_ctx 576 'filter: audio window'
    Eq $f.whisper_model_path_external ($slash + '/models/ggml-small-q5_1.bin') 'filter: Small from the module folder'
    Eq ([IO.File]::ReadAllText($scenes + '.before-live-subtitles-' + $S::Version)) $old 'copy of the collection before the update'
    if (Test-Path ($scenes + '.before-live-subtitles')) { throw 'the copy from the first install must stay as it was' }
  }
} catch {
  [void]$failures.Add('setup: ' + $_.Exception.Message)
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
  Write-Output ('FAIL ' + $failures.Count + ' of ' + ($failures.Count + $script:passed))
  foreach ($f in $failures) { Write-Output $f }
  exit 1
}
Write-Output ('ok ' + $script:passed)
