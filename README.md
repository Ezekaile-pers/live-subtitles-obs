# Live Subtitles for OBS

**English subtitles of your voice, live on stream.** You speak Russian (or Ukrainian, Polish, German…), and your viewers read English.

> **What this is.** A ready-made wrapper that makes live subtitles quick to set up for streamers. The recognition and translation are not mine. They are done by [LocalVocal](https://github.com/royshil/obs-localvocal) by Roy Shilkrot, which runs [OpenAI Whisper](https://github.com/openai/whisper) through [whisper.cpp](https://github.com/ggml-org/whisper.cpp) on your own PC. Live Subtitles adds:
> - an installer;
> - an OBS script that sets LocalVocal up in one click;
> - an overlay with styles;
> - slang packs and a profanity filter.
>
> Everything it builds on is listed in [CREDITS.md](CREDITS.md).

![Styles](docs/styles.png)

[Русская версия — README.ru.md](README.ru.md)

- **Basic style by default:** movie-like subtitles. Optional styles: a dark box, EVE Online (an interface window or a Local chat line) and World of Warcraft (a `/say` line with your name).
- **Your name on screen** in the EVE and WoW styles, in your own color. Font size, position, width, the number of lines and the fade time are adjustable.
- **Slang packs, optional.** Whisper translates game slang literally: «Пробки на скане» comes out as "traffic jams on the scan", «Фортик» as "Portico". The EVE and WoW packs turn these back into "probes on d-scan" and "Fortizar". You can write a pack for your own game in a few lines.
- **Profanity masked** with asterisks of the same length: English, Russian, transliterated Russian, slurs, and any words you add yourself.
- **Everything stays on your PC.** No cloud, no accounts, no API keys, no Node or Python.

## Install on Windows (2 minutes)

1. Download **`LiveSubtitlesSetup.exe`** from [Releases](../../releases/latest). If huggingface.co is blocked in your network, take **`LiveSubtitlesSetup-offline.exe`** instead: the Whisper model is inside (540 MB).
2. **Close OBS** and run it. Windows may say "Windows protected your PC" because the installer isn't code-signed: press **More info → Run anyway**. The installer's source code and build script are in [`installer/`](installer/).
3. Pick a **subtitle style**: *Basic* by default, *EVE Online* or *World of Warcraft*. Optionally type your **name**. Then press **Install**. The installer:
   - copies the module to the **install folder**. By default this is `%LOCALAPPDATA%\Programs\LiveSubtitles`; press **Browse…** to pick any folder on any drive;
   - puts the Whisper model into the `models` folder inside it, so nothing big goes to drive C:. The script hands this file to LocalVocal. The installer downloads the model from Hugging Face and checks its SHA-256, takes it from the offline build, or reuses the copy LocalVocal already downloaded;
   - if LocalVocal isn't installed, downloads its official installer from GitHub and starts it. Go through it to the end;
   - adds the script to your current OBS scene collection, keeping a copy of the collection next to it.
4. Open OBS → **Tools → Scripts** → `live-subtitles.lua`. Pick your **microphone** and press **Set up everything**. Then press **Show test**, and just talk: the English text appears about a second after each phrase.

The installer needs no admin rights; only the LocalVocal installer asks for them. You can run it again to update: it suggests the folder where Live Subtitles already is, and your own pack (`packs/custom.*`) is kept.

To show the subtitles in other scenes, add the existing source there: **+ → Browser → Add Existing → Live Subtitles**.

### Manual install (any OS)

1. Install LocalVocal from its [releases](https://github.com/royshil/obs-localvocal/releases/latest). On Windows, take `obs-localvocal-…-windows-x64-generic-Installer.exe`, which uses any GPU through Vulkan; NVIDIA owners can take `…-nvidia-Installer.exe` for CUDA. Close OBS while installing. If the plugin doesn't load, install the [Microsoft Visual C++ runtime](https://aka.ms/vs/17/release/vc_redist.x64.exe).
2. Unzip `live-subtitles-<version>.zip` from Releases somewhere it will stay. Any path works, including Cyrillic and spaces.
3. In OBS: **Tools → Scripts → +** → `live-subtitles.lua`. Pick the microphone, the style and, optionally, a pack, then press **Set up everything**. The first time, LocalVocal downloads the Whisper model (514 MB): wait for its download window to finish.

## What you need

- **OBS Studio 32 or newer.** Tested on Windows 10/11. macOS and Linux should work with the manual install but are untested.
- **A graphics card is strongly recommended.** Whisper Medium translates in about a second on a GPU (AMD, NVIDIA or Intel, through Vulkan). On a processor it lags behind your speech, so use the Small model there.
- About 600 MB of disk space for the model.

## Settings

| Setting | What it does |
|---|---|
| Microphone | Where LocalVocal listens. |
| Whisper model | Medium (default): best translation, needs a GPU. Small: for weak PCs. Large v3: best but heavy. If the model file is in the module's `models` folder (the installer puts it there), LocalVocal uses that file; otherwise it finds or downloads the model by itself. "Keep" leaves LocalVocal's model as it is. A model file you picked in LocalVocal yourself is never replaced. |
| Run on | The graphics card (default) or the processor. LocalVocal itself uses only the processor until this is changed. |
| Spoken language / Translate to English | What you speak. With translation off you get subtitles in your own language. |
| Style | `classic` (default), `box`, `eve-photon`, `eve-local`, `wow`. See below. |
| Speaker name, Name on screen, name color | The name shown by the EVE and WoW styles. "Show" adds it to the other styles too. |
| Font size | Pixels on a 1080p frame (default 40). The overlay is stretched to your canvas, so the size looks the same at any resolution. |
| Font | Empty means the style's own font: Bahnschrift and Segoe UI come with Windows; Arial Narrow comes with Microsoft Office, otherwise Arial is used. |
| Position, Alignment, Margin, Width | Where the subtitles sit: bottom, top or middle, with the margin and width in % of the screen. Move them away from your game's UI. |
| Lines on screen | 1–4. A new phrase starts a new line. |
| Fade after | Seconds of silence before the subtitles fade (0 means when LocalVocal clears the text). |
| Frame color | Accent color of the EVE styles. |
| Packs | Slang packs from the `packs` folder, one checkbox per file. None are ticked by default. |
| Mask profanity / Your own words | Asterisks for swearing. Your own list adds names, nicknames or anything else. |
| Text from LocalVocal, Overlay | Source names. Change them only if your LocalVocal already writes into another text source. The script never rewrites a browser source that isn't a Live Subtitles overlay. |

Changes apply to the overlay right away. Pack, language and model changes go into the LocalVocal filter, so press **Set up everything** again after changing them.

## Styles

| | |
|---|---|
| ![classic](docs/style-classic.png) `classic` (default): movie subtitles | ![box](docs/style-box.png) `box`: text on a dark plate |
| ![eve-photon](docs/style-eve-photon.png) `eve-photon`: EVE Online interface window | ![eve-local](docs/style-eve-local.png) `eve-local`: a line of EVE Local chat |
| ![wow](docs/style-wow.png) `wow`: World of Warcraft `[Name] says: …` | |

Open `preview.html` with a double click to see every style side by side with your name, size and your own phrase. The overlay itself also works in a browser: `overlay/overlay.html?demo=1&style=eve-photon&name=Ezekaile`.

## Slang packs

A pack is two files in `packs/`:

- `<id>.js`: fixes for Whisper's translation, as `[pattern, replacement]` pairs. Patterns are case-insensitive regular expressions, applied in order.
- `<id>.prompt.txt`: a hint for Whisper, a comma-separated list of names and terms. Put the most frequent words at the end: Whisper reads only the last ~224 tokens.

The built-in packs:

- **EVE Online** (`eve`) was built from 96 phrases of Russian fleet comms. They were voiced and run through LocalVocal, and every rule fixes something Whisper actually produced. For example, «Я в хулле» is heard as "I'm f…" and «Пробки на скане» is translated as "traffic jams".
- **World of Warcraft** (`wow`) covers zones, dungeons, classes and chat slang.

**Your own pack.** Write rules into `packs/custom.js` and words into `custom.prompt.txt`, or copy them under a new name. Your own packs always run after the built-in ones (`eve`, `wow`): their rules can fix what a game pack produced, and their words go at the end of the Whisper hint, the part Whisper actually reads. Then:
1. Tick the pack in the script settings.
2. Press **Set up everything** to update the hint.
3. Refresh the overlay: right click → Refresh.

To see what Whisper really outputs, open **Tools → Scripts → Script Log**: the script writes every finished phrase there.

## What to expect

- The subtitles appear about 1–1.5 s after a phrase. While you talk, the line grows as LocalVocal sends partial results.
- Whisper is good with sentences and weaker with one-word shouts. It sometimes drops a word, merges two phrases or answers a short phrase with a list of words. The packs fix the frequent mistakes, not all of them.
- **The microphone must be loud enough.** With quiet peaks around −40 dB, recognition falls apart; at −20 dB it works. If the subtitles stay silent, raise the microphone level in Windows or add a Gain filter before LocalVocal.

## Troubleshooting

- **"LocalVocal is not installed"**: run the installer again, or install it by hand (Manual install, step 1). Then restart OBS. Portable OBS needs the portable plugin version.
- **Nothing appears**: press **Show test**.
  - If the test shows up, the overlay works and the problem is recognition. Check the microphone level, the eye icon of the LocalVocal filter, and whether the model has finished downloading.
  - If the test doesn't show up, press **Set up everything** again. In the browser source properties, **"Local file" must stay unchecked**: the script uses a `file:///` URL.
- **The model doesn't download**: huggingface.co may be blocked in your network. Use `LiveSubtitlesSetup-offline.exe`, turn on a VPN for the download, or put `ggml-medium-q5_0.bin` next to `LiveSubtitlesSetup.exe` and run it.
- **The antivirus complains about the installer**: it is unsigned and downloads files, which some antiviruses dislike. The source code is in `installer/`, so you can build it yourself or use the manual install.
- **Lag in game**: Whisper Medium and the game share the GPU. Try Small.
- **Wrong font on macOS/Linux**: Bahnschrift and Segoe UI are Windows fonts. Set **Font** to any font you have.

## Uninstall

Remove the script in **Tools → Scripts**, then delete the *Live Subtitles* sources and the LocalVocal filter from your scenes. Delete the install folder: the module and the model in `models` go with it. If LocalVocal downloaded a model by itself, that one is in `%APPDATA%\obs-studio\plugin_config\obs-localvocal\models`. LocalVocal itself is removed like any other OBS plugin.

## Privacy

Your voice never leaves your PC: recognition, translation and filtering are all local. Network access happens only once, when the installer or LocalVocal downloads the model and the LocalVocal installer. Note that every finished phrase, uncensored, goes to the OBS script log, and so into OBS log files if you share them.

## For developers

- Tests: `node --test` (Node 24). The Lua tests run on the LuaJIT that ships with OBS, the installer tests on the .NET Framework C# compiler that ships with Windows.
- Build the installer: `powershell -NoProfile -ExecutionPolicy Bypass -File installer\build.ps1`. Add `-Model <ggml-medium-q5_0.bin>` to also build the offline installer.
- Pictures for this README: `node tests/render_docs.mjs` (Microsoft Edge).

## License and credits

MIT, see [LICENSE](LICENSE). © 2026 Ezekaile.

Built on [LocalVocal](https://github.com/royshil/obs-localvocal) (GPL-2.0, Roy Shilkrot), [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT), [OpenAI Whisper](https://github.com/openai/whisper) (MIT) and [OBS Studio](https://obsproject.com) (GPL-2.0). None of their code is included here; the installer downloads them from the official sites. Full list: [CREDITS.md](CREDITS.md).

A fan project, not affiliated with the OBS Project, LocalVocal, OpenAI, CCP Games or Blizzard Entertainment. EVE Online is a trademark of CCP; World of Warcraft is a trademark of Blizzard Entertainment.
