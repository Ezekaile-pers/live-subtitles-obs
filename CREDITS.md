# Credits

Live Subtitles for OBS is a thin, ready-to-use **wrapper** that makes these subtitles easy to set up for streamers. It consists of an OBS script, an overlay page, slang packs and an installer. Speech recognition and translation are done entirely by the projects below. Please star and support them.

## The projects that do the real work

| Project | What it does here | License |
|---|---|---|
| [LocalVocal](https://github.com/royshil/obs-localvocal) by Roy Shilkrot | The OBS plugin that listens to the microphone, runs Whisper on your PC and writes the text into OBS. Live Subtitles only configures it. The installer downloads LocalVocal's official release; nothing of LocalVocal is included here. | GPL-2.0 |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) by Georgi Gerganov and the ggml-org contributors | The fast Whisper engine inside LocalVocal (GPU via Vulkan or CUDA). | MIT |
| [Whisper](https://github.com/openai/whisper) by OpenAI | The speech recognition and translation model. | MIT (code and weights) |
| [ggml Whisper models](https://huggingface.co/ggerganov/whisper.cpp) on Hugging Face | The model files the installer and LocalVocal download, checked against their SHA-256. | MIT |
| [Silero VAD](https://github.com/snakers4/silero-vad) | Voice activity detection that ships with LocalVocal. | MIT |
| [OBS Studio](https://github.com/obsproject/obs-studio) | The streaming app. Its Lua scripting (LuaJIT) runs the script; its [browser source](https://github.com/obsproject/obs-browser) shows the overlay and delivers the text through `javascript_event`. | GPL-2.0 |

Live Subtitles adds the overlay styles, slang packs, profanity filter, the OBS script and the installer. All of these are original work under the [MIT License](LICENSE).

## Looks and words borrowed from games

- **EVE Online** © CCP Games. The `eve-photon` and `eve-local` styles imitate the look of the Photon interface and the Local chat line. They use only their own CSS and system fonts, no game assets.
- **World of Warcraft** © Blizzard Entertainment. The `wow` style imitates a `/say` chat line, also with only its own CSS.
- **EVE slang** comes from Russian EVE fleet comms. Every rule was checked on what Whisper actually produced.
- **WoW slang** comes from the author's own World of Warcraft stream.

## Fonts

Only system fonts are used, nothing is bundled: Bahnschrift and Segoe UI (Microsoft, part of Windows), and Arial Narrow (Monotype, comes with Microsoft Office; without it the `wow` style falls back to Arial).

## Tools used to make it

- [Node.js](https://nodejs.org) runs the tests.
- Microsoft Edge (headless) renders the README pictures.
- The C# compiler of the .NET Framework builds the installer.
- The Windows "Microsoft Irina" voice synthesized the test phrases; the voice files are not included.
- Developed with the help of [Claude Code](https://claude.com/claude-code) (Anthropic).

## Not affiliated

This is a fan-made tool. It is not affiliated with or endorsed by the OBS Project, the LocalVocal authors, OpenAI, Hugging Face, CCP Games or Blizzard Entertainment. All trademarks belong to their owners.
