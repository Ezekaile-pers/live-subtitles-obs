# Builds the Live Subtitles installer with the C# compiler that ships with Windows (.NET Framework 4.x, no SDK needed):
#   out\LiveSubtitlesSetup.exe          - downloads the Whisper model and LocalVocal from their official sites
#   out\LiveSubtitlesSetup-offline.exe  - only with -Model <ggml-medium-q5_0.bin>: the model is inside (no Hugging Face needed)
#   out\live-subtitles-<version>.zip    - the module for manual installation (also embedded in both installers)
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File installer\build.ps1 [-Model path] [-Out folder]
# ASCII only: Windows PowerShell 5.1 reads BOM-less files as CP1251.
param([string]$Model = '', [string]$Out = '')
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
if (-not $Out) { $Out = Join-Path $here 'out' }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'csc.exe from .NET Framework 4.x not found' }
$version = ([regex]::Match([IO.File]::ReadAllText((Join-Path $root 'live-subtitles.lua')), "local VERSION = '([^']+)'")).Groups[1].Value
if (-not $version) { throw 'VERSION not found in live-subtitles.lua' }

# Module archive: what a streamer needs, without tests and installer sources; entry names with "/" for any unzip tool.
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zipPath = Join-Path $Out ('live-subtitles-' + $version + '.zip')
if (Test-Path $zipPath) { Remove-Item $zipPath }
$items = @()
foreach ($f in @('live-subtitles.lua', 'preview.html', 'README.md', 'README.ru.md', 'LICENSE', 'CREDITS.md')) { $items += Get-Item (Join-Path $root $f) }
foreach ($d in @('overlay', 'packs', 'docs')) { $items += Get-ChildItem -Recurse -File (Join-Path $root $d) }
$zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
  foreach ($item in $items) {
    $rel = $item.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $item.FullName, $rel)
  }
} finally { $zip.Dispose() }

$src = Join-Path $here 'LiveSubtitlesSetup.cs'
$common = @('/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', '/codepage:65001',
  ('/win32manifest:' + (Join-Path $here 'app.manifest')), ('/resource:' + $zipPath + ',module.zip'),
  '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll', '/r:System.IO.Compression.dll',
  '/r:System.IO.Compression.FileSystem.dll', '/r:System.Web.Extensions.dll')

$exe = Join-Path $Out 'LiveSubtitlesSetup.exe'
& $csc @common ('/out:' + $exe) $src
if ($LASTEXITCODE -ne 0) { throw 'csc failed' }
Write-Output ('built ' + $exe)

if ($Model) {
  $sha = (Get-FileHash $Model -Algorithm SHA256).Hash.ToLower()
  if ($sha -ne '19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f') { throw ('not ggml-medium-q5_0.bin, sha256 ' + $sha) }
  $offline = Join-Path $Out 'LiveSubtitlesSetup-offline.exe'
  & $csc @common ('/resource:' + $Model + ',model.ggml-medium-q5_0.bin') ('/out:' + $offline) $src
  if ($LASTEXITCODE -ne 0) { throw 'csc failed (offline)' }
  Write-Output ('built ' + $offline)
}
Write-Output ('built ' + $zipPath)
