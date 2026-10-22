// Live Subtitles for OBS — установщик для стримера. Ставит модуль, модель Whisper для LocalVocal и сам LocalVocal
// (его официальный установщик с GitHub) и добавляет скрипт в текущую коллекцию сцен OBS. Распознавание и перевод
// делает LocalVocal (Roy Shilkrot, GPL-2.0) на whisper.cpp и модели OpenAI Whisper — установщик их не содержит,
// а скачивает с официальных адресов (сборка -offline несёт модель внутри). MIT License, (c) 2026 Ezekaile.
// Сборка встроенным в Windows компилятором .NET Framework 4.x: powershell -File installer\build.ps1
// Без окна: LiveSubtitlesSetup.exe --auto [--dir папка] [--preset basic|eve|wow] [--name Ник] [--model medium|small|large]
//           [--device gpu|cpu] [--gpu generic|nvidia] [--no-model] [--no-localvocal] [--no-script] [--no-module];
//           --no-model (или --model none) — модель не качать; журнал — %TEMP%\LiveSubtitlesSetup.log
// Обновление (скрипт уже в коллекции): --device и --model уходят в его настройки и в фильтр LocalVocal, стиль и ник не трогаются.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

namespace LiveSubtitles
{
    public sealed class ModelInfo
    {
        public readonly string Id, Name, Folder, File, Url, Sha256;

        public ModelInfo(string id, string name, string folder, string file, string sha256)
        {
            Id = id; Name = name; Folder = folder; File = file; Sha256 = sha256;
            Url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/" + file;
        }
    }

    public sealed class Options
    {
        public bool Module = true, Model = true, LocalVocal = true, Script = true;
        public string ModelId = "medium", Gpu = "generic", Preset = "basic", Name = "";
        public string Device = "gpu"; // где считать перевод: gpu — видеокарта (быстро), cpu — процессор (видеокарта свободна игре)
        public bool DeviceChosen, ModelChosen; // обновление: стример сейчас сменил устройство / модель — применить к уже добавленному скрипту
        public string Dir; // папка установки модуля и модели; пусто — Setup.DefaultDir()
    }

    public delegate void Progress(long done, long total);

    public static class Setup
    {
        public const string Version = "1.2.1";
        public const string ScriptFile = "live-subtitles.lua";
        const string LocalVocalReleases = "https://api.github.com/repos/royshil/obs-localvocal/releases/latest";

        // Как в каталоге LocalVocal (data/models/models_directory.json): имя, папка, файл и SHA-256. Medium — по умолчанию,
        // как в скрипте; LocalVocal находит модель в plugin_config/obs-localvocal/models/<папка> и сам её не качает.
        public static readonly ModelInfo[] Models = new ModelInfo[]
        {
            new ModelInfo("medium", "Whisper Medium q5 (514Mb)", "ggml-medium-q5_0", "ggml-medium-q5_0.bin", "19fea4b380c3a618ec4723c3eef2eb785ffba0d0538cf43f8f235e7b3b34220f"),
            new ModelInfo("small", "Whisper Small q5 (181Mb)", "ggml-small-q5_1", "ggml-small-q5_1.bin", "ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb"),
            new ModelInfo("large", "Whisper Large v3 q5 (1Gb)", "ggml-large-v3-q5_0", "ggml-large-v3-q5_0.bin", "d75795ecff3f83b5faa89d1900604ad8c780abd5739fae406de19f23ecd98ad1"),
        };

        public static ModelInfo FindModel(string id)
        {
            foreach (ModelInfo m in Models) if (m.Id == id) return m;
            return null;
        }

        // ---------- пути (переменные окружения важнее системных папок: так установщик проверяется на поддельном OBS) ----------

        static string Folder(string variable, Environment.SpecialFolder fallback)
        {
            string value = Environment.GetEnvironmentVariable(variable);
            return string.IsNullOrEmpty(value) ? Environment.GetFolderPath(fallback) : value;
        }

        public static string AppData() { return Folder("APPDATA", Environment.SpecialFolder.ApplicationData); }
        public static string LocalAppData() { return Folder("LOCALAPPDATA", Environment.SpecialFolder.LocalApplicationData); }
        public static string ProgramData() { return Folder("PROGRAMDATA", Environment.SpecialFolder.CommonApplicationData); }
        public static string InstallDir() { return Path.Combine(LocalAppData(), "Programs", "LiveSubtitles"); }
        public static string ObsConfigDir() { return Path.Combine(AppData(), "obs-studio"); }
        public static string LogFile() { return Path.Combine(Path.GetTempPath(), "LiveSubtitlesSetup.log"); }

        // Где модель держит сам LocalVocal (скачанная им по имени) и где её держит модуль (папка models в папке установки,
        // хоть на другом диске: скрипт отдаёт её LocalVocal внешним файлом).
        public static string LocalVocalModelPath(ModelInfo m)
        {
            return Path.Combine(ObsConfigDir(), "plugin_config", "obs-localvocal", "models", m.Folder, m.File);
        }

        public static string ModuleModelPath(string dir, ModelInfo m) { return Path.Combine(dir, "models", m.File); }

        // Папка, куда модуль уже поставлен (скрипт в текущей коллекции OBS): обновление идёт туда же.
        public static string ExistingInstallDir()
        {
            try
            {
                string collection = CurrentCollectionPath();
                if (collection == null) return null;
                Dictionary<string, object> root = Json().DeserializeObject(System.IO.File.ReadAllText(collection, Encoding.UTF8)) as Dictionary<string, object>;
                object modules, scripts;
                if (root == null || !root.TryGetValue("modules", out modules) || !(modules is Dictionary<string, object>)
                    || !((Dictionary<string, object>)modules).TryGetValue("scripts-tool", out scripts) || !(scripts is object[]))
                    return null;
                foreach (object item in (object[])scripts)
                {
                    Dictionary<string, object> entry = item as Dictionary<string, object>;
                    object path;
                    if (entry == null || !entry.TryGetValue("path", out path) || !(path is string)) continue;
                    string file = ((string)path).Replace('/', Path.DirectorySeparatorChar);
                    if (!file.EndsWith(Path.DirectorySeparatorChar + ScriptFile, StringComparison.OrdinalIgnoreCase) || !System.IO.File.Exists(file)) continue;
                    return Path.GetDirectoryName(Path.GetFullPath(file));
                }
            }
            catch (Exception) { }
            return null;
        }

        public static string DefaultDir() { return ExistingInstallDir() ?? InstallDir(); }

        // Папка годится, если в ней можно создать файл; иначе — понятная ошибка до того, как что-то качать.
        public static void EnsureWritable(string dir)
        {
            try
            {
                Directory.CreateDirectory(dir);
                string probe = Path.Combine(dir, ".write-test");
                System.IO.File.WriteAllText(probe, "ok");
                System.IO.File.Delete(probe);
            }
            catch (Exception e)
            {
                throw new IOException(T.F("dir_not_writable", dir, e.Message), e);
            }
        }

        public static string ObsInstallDir()
        {
            try
            {
                RegistryView view = Environment.Is64BitOperatingSystem ? RegistryView.Registry64 : RegistryView.Default;
                using (RegistryKey hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view))
                using (RegistryKey key = hklm.OpenSubKey(@"SOFTWARE\OBS Studio"))
                {
                    string value = key == null ? null : key.GetValue("") as string;
                    if (!string.IsNullOrEmpty(value) && Directory.Exists(value)) return value;
                }
            }
            catch (Exception) { }
            string guess = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "obs-studio");
            return Directory.Exists(guess) ? guess : null;
        }

        public static string ObsExe()
        {
            string dir = ObsInstallDir();
            string exe = dir == null ? null : Path.Combine(dir, "bin", "64bit", "obs64.exe");
            return exe != null && System.IO.File.Exists(exe) ? exe : null;
        }

        public static bool ObsRunning() { return Process.GetProcessesByName("obs64").Length > 0; }

        // LocalVocal в одной из папок плагинов OBS: общая (ProgramData), своя у пользователя или рядом с самим OBS.
        public static bool LocalVocalInstalled()
        {
            List<string> places = new List<string>
            {
                Path.Combine(ProgramData(), "obs-studio", "plugins", "obs-localvocal", "bin", "64bit", "obs-localvocal.dll"),
                Path.Combine(AppData(), "obs-studio", "plugins", "obs-localvocal", "bin", "64bit", "obs-localvocal.dll"),
            };
            string obs = ObsInstallDir();
            if (obs != null) places.Add(Path.Combine(obs, "obs-plugins", "64bit", "obs-localvocal.dll"));
            foreach (string place in places) if (System.IO.File.Exists(place)) return true;
            return false;
        }

        // ---------- коллекция сцен OBS ----------

        public static string ReadIniValue(string path, string section, string key)
        {
            if (!System.IO.File.Exists(path)) return null;
            string current = null;
            foreach (string raw in System.IO.File.ReadAllLines(path, Encoding.UTF8))
            {
                string line = raw.Trim();
                if (line.StartsWith("[") && line.EndsWith("]")) { current = line.Substring(1, line.Length - 2); continue; }
                int eq = line.IndexOf('=');
                if (current == section && eq > 0 && line.Substring(0, eq).Trim() == key) return line.Substring(eq + 1).Trim();
            }
            return null;
        }

        // Текущая коллекция: [Basic] SceneCollectionFile в user.ini (OBS 31+) или global.ini (старые версии).
        public static string CurrentCollectionPath()
        {
            string dir = ObsConfigDir();
            foreach (string ini in new[] { "user.ini", "global.ini" })
            {
                string file = ReadIniValue(Path.Combine(dir, ini), "Basic", "SceneCollectionFile");
                if (string.IsNullOrEmpty(file)) continue;
                if (!file.EndsWith(".json", StringComparison.OrdinalIgnoreCase)) file += ".json";
                string path = Path.Combine(dir, "basic", "scenes", file);
                if (System.IO.File.Exists(path)) return path;
            }
            return null;
        }

        // Имя текущей коллекции, как его показывает OBS ([Basic] SceneCollection), иначе — имя файла.
        public static string CurrentCollectionName()
        {
            string path = CurrentCollectionPath();
            if (path == null) return null;
            foreach (string ini in new[] { "user.ini", "global.ini" })
            {
                string name = ReadIniValue(Path.Combine(ObsConfigDir(), ini), "Basic", "SceneCollection");
                if (!string.IsNullOrEmpty(name)) return name;
            }
            return Path.GetFileNameWithoutExtension(path);
        }

        public static string JsonString(string s)
        {
            StringBuilder sb = new StringBuilder("\"");
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) sb.AppendFormat("\\u{0:x4}", (int)c); else sb.Append(c);
                        break;
                }
            }
            return sb.Append('"').ToString();
        }

        // Стартовые настройки скрипта: базовый стиль по умолчанию, EVE Online и WoW — по выбору; device — где считать
        // перевод, modelId — какую модель скрипт отдаёт LocalVocal (умолчания скрипта — видеокарта и Medium — не пишем).
        public static string PresetSettings(string preset, string name)
        {
            return PresetSettings(preset, name, "gpu", "medium");
        }

        public static string PresetSettings(string preset, string name, string device, string modelId)
        {
            List<string> parts = new List<string>();
            if (preset == "eve") { parts.Add("\"style\": \"eve-photon\""); parts.Add("\"pack_eve\": true"); }
            else if (preset == "wow") { parts.Add("\"style\": \"wow\""); parts.Add("\"pack_wow\": true"); }
            else parts.Add("\"style\": \"classic\"");
            string trimmed = (name ?? "").Trim();
            if (trimmed.Length > 0) parts.Add("\"name\": " + JsonString(trimmed));
            if (device == "cpu") parts.Add("\"device\": \"cpu\"");
            ModelInfo model = FindModel(modelId);
            if (model != null && model != Models[0]) parts.Add("\"model\": " + JsonString(model.Name));
            return "{" + string.Join(", ", parts.ToArray()) + "}";
        }

        static JavaScriptSerializer Json()
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = int.MaxValue;
            serializer.RecursionLimit = 1000;
            return serializer;
        }

        // Скрипт в коллекцию сцен (modules → scripts-tool), как его записал бы сам OBS. Вставка текстом: остальной файл
        // не переписывается. Live Subtitles там уже есть (из любой папки) — коллекция не меняется. Битый JSON — ошибка.
        public static string AddScript(string json, string scriptPath, string settingsJson)
        {
            string path = scriptPath.Replace('\\', '/');
            Dictionary<string, object> root = Json().DeserializeObject(json) as Dictionary<string, object>;
            if (root == null) throw new InvalidDataException("not an OBS scene collection");
            object modules, scripts;
            if (root.TryGetValue("modules", out modules) && modules is Dictionary<string, object>
                && ((Dictionary<string, object>)modules).TryGetValue("scripts-tool", out scripts) && scripts is object[])
            {
                foreach (object item in (object[])scripts)
                {
                    Dictionary<string, object> entry = item as Dictionary<string, object>;
                    object existing;
                    if (entry != null && entry.TryGetValue("path", out existing) && existing is string
                        && ((string)existing).Replace('\\', '/').EndsWith("/" + ScriptFile, StringComparison.OrdinalIgnoreCase))
                        return json;
                }
            }

            string added = "{\"path\": " + JsonString(path) + ", \"settings\": " + (string.IsNullOrEmpty(settingsJson) ? "{}" : settingsJson) + "}";
            string result;
            Match m = Regex.Match(json, "\"scripts-tool\"\\s*:\\s*\\[");
            if (m.Success)
            {
                int at = m.Index + m.Length;
                result = json.Insert(at, added + (Regex.IsMatch(json.Substring(at), "^\\s*\\]") ? "" : ","));
            }
            else if ((m = Regex.Match(json, "\"modules\"\\s*:\\s*\\{")).Success)
            {
                int at = m.Index + m.Length;
                result = json.Insert(at, "\"scripts-tool\": [" + added + "]" + (Regex.IsMatch(json.Substring(at), "^\\s*\\}") ? "" : ","));
            }
            else
            {
                int end = json.LastIndexOf('}');
                result = json.Insert(end, (root.Count > 0 ? ", " : "") + "\"modules\": {\"scripts-tool\": [" + added + "]}");
            }
            Json().DeserializeObject(result);
            return result;
        }

        // ---------- обновление: настройки уже добавленного скрипта и его фильтр LocalVocal ----------
        // Тоже правка текстом: меняются только нужные значения, остальной файл остаётся байт в байт.

        const string LocalVocalId = "transcription_filter_audio_filter";

        // Значение в тексте JSON: s[Start..End); Key — имя члена объекта (у элемента массива — null).
        sealed class Span
        {
            public string Key;
            public int Start, End;
        }

        static int SkipWs(string s, int i)
        {
            while (i < s.Length && (char.IsWhiteSpace(s[i]) || s[i] == '﻿')) i++;
            return i;
        }

        // Строка JSON с кавычки s[i]; возвращает позицию за закрывающей кавычкой.
        static int ReadString(string s, int i, out string value)
        {
            StringBuilder sb = new StringBuilder();
            for (i++; s[i] != '"'; i++)
            {
                if (s[i] != '\\') { sb.Append(s[i]); continue; }
                char e = s[++i];
                if (e == 'u') { sb.Append((char)Convert.ToInt32(s.Substring(i + 1, 4), 16)); i += 4; }
                else sb.Append(e == 'n' ? '\n' : e == 'r' ? '\r' : e == 't' ? '\t' : e == 'b' ? '\b' : e == 'f' ? '\f' : e);
            }
            value = sb.ToString();
            return i + 1;
        }

        // Члены объекта (s[start] == '{') или элементы массива (s[start] == '['); end — позиция за скобкой.
        static List<Span> Items(string s, int start, out int end)
        {
            List<Span> items = new List<Span>();
            bool isObject = s[start] == '{';
            int i = SkipWs(s, start + 1);
            if (s[i] == (isObject ? '}' : ']')) { end = i + 1; return items; }
            while (true)
            {
                string key = null;
                if (isObject) i = SkipWs(s, SkipWs(s, ReadString(s, i, out key)) + 1);
                int valueEnd = SkipValue(s, i);
                items.Add(new Span { Key = key, Start = i, End = valueEnd });
                i = SkipWs(s, valueEnd);
                if (s[i] != ',') { end = i + 1; return items; }
                i = SkipWs(s, i + 1);
            }
        }

        static int SkipValue(string s, int i)
        {
            string ignored;
            int end;
            if (s[i] == '"') return ReadString(s, i, out ignored);
            if (s[i] == '{' || s[i] == '[') { Items(s, i, out end); return end; }
            while (i < s.Length && ",}] \t\r\n".IndexOf(s[i]) < 0) i++;
            return i;
        }

        // Член key объекта, который начинается в s[obj]; не объект или члена нет — null.
        static Span Member(string s, int obj, string key)
        {
            if (s[obj] != '{') return null;
            int end;
            foreach (Span m in Items(s, obj, out end)) if (m.Key == key) return m;
            return null;
        }

        // Элементы массива array; не массив или null — пустой список.
        static List<Span> Elements(string s, Span array)
        {
            int end;
            return array != null && s[array.Start] == '[' ? Items(s, array.Start, out end) : new List<Span>();
        }

        // Значение члена как текст: строка — без кавычек, остальное — как записано; объекта или члена нет — fallback.
        static string Value(string s, Span obj, string key, string fallback)
        {
            Span value = obj == null ? null : Member(s, obj.Start, key);
            if (value == null) return fallback;
            if (s[value.Start] != '"') return s.Substring(value.Start, value.End - value.Start);
            string text;
            ReadString(s, value.Start, out text);
            return text;
        }

        // Члены объекта obj: есть — новое значение, нет — добавляются в начало. Значения — готовый текст JSON.
        static string SetMembers(string s, int obj, List<KeyValuePair<string, string>> values)
        {
            foreach (KeyValuePair<string, string> pair in values)
            {
                Span old = Member(s, obj, pair.Key);
                if (old == null)
                {
                    bool empty = s[SkipWs(s, obj + 1)] == '}';
                    s = s.Insert(obj + 1, JsonString(pair.Key) + ": " + pair.Value + (empty ? "" : ", "));
                }
                else if (s.Substring(old.Start, old.End - old.Start) != pair.Value)
                    s = s.Substring(0, old.Start) + pair.Value + s.Substring(old.End);
            }
            return s;
        }

        static KeyValuePair<string, string> Pair(string key, string json) { return new KeyValuePair<string, string>(key, json); }

        // Коллекция сцен — объект JSON; пустая строка, битый файл или не объект — нет.
        static bool ValidJson(string s)
        {
            try { return !string.IsNullOrEmpty(s) && Json().DeserializeObject(s) is Dictionary<string, object>; }
            catch (Exception) { return false; }
        }

        static void RequireCollection(string s)
        {
            if (!(Json().DeserializeObject(s ?? "") is Dictionary<string, object>)) throw new InvalidDataException("not an OBS scene collection");
        }

        // Запись Live Subtitles в modules → scripts-tool (из любой папки, как в AddScript) или null.
        static Span ScriptEntry(string s)
        {
            Span modules = Member(s, SkipWs(s, 0), "modules");
            foreach (Span item in Elements(s, modules == null ? null : Member(s, modules.Start, "scripts-tool")))
            {
                string path = Value(s, item, "path", null);
                if (path != null && path.Replace('\\', '/').EndsWith("/" + ScriptFile, StringComparison.OrdinalIgnoreCase)) return item;
            }
            return null;
        }

        // Объект настроек уже добавленного скрипта или null.
        static Span ScriptSettings(string s)
        {
            Span entry = ScriptEntry(s);
            Span settings = entry == null ? null : Member(s, entry.Start, "settings");
            return settings != null && s[settings.Start] == '{' ? settings : null;
        }

        // Настройки первого фильтра LocalVocal на источнике mic — там же, где его ищет скрипт: среди источников и
        // глобальных аудиоустройств OBS («Мик/Доп.», «Звук рабочего стола» лежат в корне коллекции, не в sources).
        static Span LocalVocalSettings(string s, string mic)
        {
            if (string.IsNullOrEmpty(mic)) return null;
            int root = SkipWs(s, 0), end;
            List<Span> candidates = Elements(s, Member(s, root, "sources"));
            foreach (Span m in Items(s, root, out end))
                if (Regex.IsMatch(m.Key, "^(DesktopAudioDevice|AuxAudioDevice)\\d+$")) candidates.Add(m);
            foreach (Span source in candidates)
            {
                if (s[source.Start] != '{' || Value(s, source, "name", null) != mic) continue;
                foreach (Span f in Elements(s, Member(s, source.Start, "filters")))
                {
                    string id = Value(s, f, "id", null);
                    if (id == null || Regex.Replace(id, "_v\\d+$", "") != LocalVocalId) continue;
                    Span settings = Member(s, f.Start, "settings");
                    return settings != null && s[settings.Start] == '{' ? settings : null;
                }
            }
            return null;
        }

        public static string CurrentCollectionJson()
        {
            try
            {
                string path = CurrentCollectionPath();
                return path == null ? null : System.IO.File.ReadAllText(path, Encoding.UTF8);
            }
            catch (Exception) { return null; }
        }

        // Live Subtitles уже добавлен в эту коллекцию — установщик его обновляет.
        public static bool ScriptAdded(string json)
        {
            return ValidJson(json) && ScriptEntry(json) != null;
        }

        // Настройка уже добавленного скрипта (строка — без кавычек); нет значения — fallback; скрипта нет — null.
        public static string ScriptSetting(string json, string key, string fallback)
        {
            if (!ValidJson(json)) return null;
            Span settings = ScriptSettings(json);
            return settings == null ? null : Value(json, settings, key, fallback);
        }

        // Где уже добавленный скрипт считает перевод: gpu, cpu или keep (нет значения — умолчание скрипта, gpu).
        public static string ScriptDevice(string json) { return ScriptSetting(json, "device", "gpu"); }

        // Пресет установщика, ближайший к стилю уже добавленного скрипта (окно показывает его при обновлении).
        public static string ScriptPreset(string json)
        {
            string style = ScriptSetting(json, "style", "classic");
            if (style == null) return null;
            return style.StartsWith("eve-") ? "eve" : style == "wow" ? "wow" : "basic";
        }

        // Какую модель берёт уже добавленный скрипт: medium, small, large; «не менять» — ""; нет значения — умолчание (medium).
        public static string ScriptModelId(string json)
        {
            if (!ValidJson(json)) return null;
            Span settings = ScriptSettings(json);
            if (settings == null) return null;
            ModelInfo model = FindModelByName(Value(json, settings, "model", Models[0].Name));
            return model == null ? "" : model.Id;
        }

        static ModelInfo FindModelByName(string name)
        {
            foreach (ModelInfo m in Models) if (m.Name == name) return m;
            return null;
        }

        // Обновление: члены patchJson (объект) — в настройки уже добавленного скрипта; скрипта нет — коллекция без изменений.
        public static string SetScriptSettings(string json, string patchJson)
        {
            RequireCollection(json);
            Span settings = ScriptSettings(json);
            int end;
            List<KeyValuePair<string, string>> values = new List<KeyValuePair<string, string>>();
            foreach (Span m in Items(patchJson, SkipWs(patchJson, 0), out end))
                values.Add(Pair(m.Key, patchJson.Substring(m.Start, m.End - m.Start)));
            if (settings == null || values.Count == 0) return json;
            string result = SetMembers(json, settings.Start, values);
            Json().DeserializeObject(result);
            return result;
        }

        // На процессоре — потоков по числу логических ядер минус два (игре и OBS), от 4 до 8; так же считает скрипт.
        public static int CpuThreads(int processors) { return Math.Max(4, Math.Min(8, processors - 2)); }

        // Обновление: фильтр LocalVocal на микрофоне скрипта получает устройство, модель и скорость — то же, что поставила бы
        // кнопка «Настроить всё» (localvocal_settings и keep_own_settings в live-subtitles.lua). Устройство LocalVocal
        // меняет только при загрузке модели, а правка идёт, пока OBS закрыт: при запуске модель сразу грузится куда надо.
        // Фильтра ещё нет (не нажимали «Настроить всё») — коллекция без изменений.
        public static string UpdateLocalVocal(string json)
        {
            RequireCollection(json);
            Span settings = ScriptSettings(json);
            Span filter = settings == null ? null : LocalVocalSettings(json, Value(json, settings, "mic", ""));
            if (filter == null) return json;
            List<KeyValuePair<string, string>> values = new List<KeyValuePair<string, string>>();
            values.Add(Pair("partial_group", Value(json, settings, "live_text", "false") == "true" ? "true" : "false"));
            values.Add(Pair("partial_latency", "1100"));
            values.Add(Pair("audio_ctx", "576"));
            values.Add(Pair("beam_search.beam_size", "2"));
            string device = Value(json, settings, "device", "gpu");
            if (device == "cpu")
            {
                values.Add(Pair("backend_device", "-1"));
                values.Add(Pair("n_threads", CpuThreads(Environment.ProcessorCount).ToString(CultureInfo.InvariantCulture)));
            }
            else if (device != "keep")
            {
                values.Add(Pair("backend_device", "0"));
                values.Add(Pair("n_threads", "4"));
            }
            string model = Value(json, settings, "model", Models[0].Name);
            string path = Value(json, ScriptEntry(json), "path", "").Replace('\\', '/');
            string models = path.Substring(0, path.LastIndexOf('/') + 1) + "models/";
            bool own = Value(json, filter, "whisper_model_path", "") == "!!!external!!!"
                && !Value(json, filter, "whisper_model_path_external", "").Replace('\\', '/').StartsWith(models, StringComparison.OrdinalIgnoreCase);
            if (model != "" && !own)
            {
                ModelInfo info = FindModelByName(model);
                if (info != null && System.IO.File.Exists(models + info.File))
                {
                    values.Add(Pair("whisper_model_path", JsonString("!!!external!!!")));
                    values.Add(Pair("whisper_model_path_external", JsonString(models + info.File)));
                }
                else values.Add(Pair("whisper_model_path", JsonString(model)));
            }
            string result = SetMembers(json, filter.Start, values);
            Json().DeserializeObject(result);
            return result;
        }

        static bool HasLocalVocal(string json)
        {
            Span settings = ScriptSettings(json);
            return settings != null && LocalVocalSettings(json, Value(json, settings, "mic", "")) != null;
        }

        // Что стример выбрал сейчас для уже добавленного скрипта: только то, что он менял (в окне — список, без окна — ключ).
        static string ScriptPatch(Options o)
        {
            List<string> parts = new List<string>();
            if (o.DeviceChosen) parts.Add("\"device\": " + JsonString(o.Device));
            ModelInfo model = FindModel(o.ModelId);
            if (o.ModelChosen && model != null) parts.Add("\"model\": " + JsonString(model.Name));
            return "{" + string.Join(", ", parts.ToArray()) + "}";
        }

        // ---------- файлы ----------

        static readonly string[] StreamerFiles = { "packs/custom.js", "packs/custom.prompt.txt" };

        // Модуль из архива в папку. Свой набор стримера (custom) при обновлении не затирается; путь вне папки — ошибка.
        public static int ExtractModule(Stream zip, string dir)
        {
            string root = Path.GetFullPath(dir).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            int written = 0;
            using (ZipArchive archive = new ZipArchive(zip, ZipArchiveMode.Read, true))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string name = entry.FullName.Replace('\\', '/');
                    string target = Path.GetFullPath(Path.Combine(root, name));
                    if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("bad path in archive: " + name);
                    if (name.EndsWith("/")) continue;
                    if (Array.IndexOf(StreamerFiles, name) >= 0 && System.IO.File.Exists(target)) continue;
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    entry.ExtractToFile(target, true);
                    written++;
                }
            }
            return written;
        }

        public static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = System.IO.File.OpenRead(path))
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
        }

        // Поток → файл через .part, с проверкой SHA-256 (если задан); не совпал — ничего не остаётся.
        public static void Save(Stream input, long total, string target, string sha256, Progress progress, Func<bool> cancelled)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(target));
            string part = target + ".part";
            try
            {
                using (FileStream output = System.IO.File.Create(part))
                {
                    byte[] buffer = new byte[1 << 16];
                    long done = 0;
                    int n;
                    while ((n = input.Read(buffer, 0, buffer.Length)) > 0)
                    {
                        if (cancelled != null && cancelled()) throw new OperationCanceledException();
                        output.Write(buffer, 0, n);
                        done += n;
                        if (progress != null) progress(done, total);
                    }
                }
                if (!string.IsNullOrEmpty(sha256) && !string.Equals(Sha256File(part), sha256, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException(T.S("bad_hash"));
                if (System.IO.File.Exists(target)) System.IO.File.Delete(target);
                System.IO.File.Move(part, target);
            }
            finally
            {
                if (System.IO.File.Exists(part)) System.IO.File.Delete(part);
            }
        }

        static WebRequest Request(string url)
        {
            ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; // TLS 1.2 для .NET Framework 4.x
            WebRequest request = WebRequest.Create(url);
            HttpWebRequest http = request as HttpWebRequest;
            if (http != null) http.UserAgent = "LiveSubtitlesSetup/" + Version;
            return request;
        }

        public static void Download(string url, string target, string sha256, Progress progress, Func<bool> cancelled)
        {
            using (WebResponse response = Request(url).GetResponse())
            using (Stream input = response.GetResponseStream())
                Save(input, response.ContentLength, target, sha256, progress, cancelled);
        }

        // Модель — в папку models выбранной папки установки. Уже есть там или у самого LocalVocal (скачал её раньше) с верным
        // хешем — ничего не делаем; есть внутри установщика (сборка -offline) или рядом с ним — копия; иначе — с Hugging Face.
        // Возвращает, откуда взялась: present, localvocal, embedded, beside, downloaded.
        public static string PlaceModel(ModelInfo m, string dir, Action<string> log, Progress progress, Func<bool> cancelled)
        {
            string target = ModuleModelPath(dir, m);
            if (System.IO.File.Exists(target) && Sha256File(target) == m.Sha256) return "present";
            string theirs = LocalVocalModelPath(m);
            if (System.IO.File.Exists(theirs) && Sha256File(theirs) == m.Sha256) return "localvocal";
            Assembly self = Assembly.GetExecutingAssembly();
            using (Stream embedded = self.GetManifestResourceStream("model." + m.File))
            {
                if (embedded != null) { Save(embedded, embedded.Length, target, m.Sha256, progress, cancelled); return "embedded"; }
            }
            string beside = Path.Combine(Path.GetDirectoryName(self.Location), m.File);
            if (System.IO.File.Exists(beside))
            {
                using (FileStream input = System.IO.File.OpenRead(beside)) Save(input, input.Length, target, m.Sha256, progress, cancelled);
                return "beside";
            }
            if (log != null) log(T.F("model_start", m.Name, m.Url));
            Download(m.Url, target, m.Sha256, progress, cancelled);
            return "downloaded";
        }

        // Официальный установщик LocalVocal для Windows из последнего релиза: generic (видеокарта через Vulkan) или nvidia (CUDA).
        public static string PickLocalVocalAsset(string releaseJson, string gpu)
        {
            Match m = Regex.Match(releaseJson, "\"browser_download_url\"\\s*:\\s*\"(https://[^\"]+-windows-x64-" + Regex.Escape(gpu) + "-Installer\\.exe)\"", RegexOptions.IgnoreCase);
            return m.Success ? m.Groups[1].Value : null;
        }

        static string LocalVocalInstallerUrl(string gpu)
        {
            WebRequest request = Request(LocalVocalReleases);
            ((HttpWebRequest)request).Accept = "application/vnd.github+json";
            using (WebResponse response = request.GetResponse())
            using (StreamReader reader = new StreamReader(response.GetResponseStream(), Encoding.UTF8))
                return PickLocalVocalAsset(reader.ReadToEnd(), gpu);
        }

        // ---------- установка ----------

        public static void Run(Options o, Action<string> log, Progress progress, Func<bool> cancelled)
        {
            string dir = string.IsNullOrEmpty(o.Dir) ? DefaultDir() : Path.GetFullPath(o.Dir);
            if (o.Module || o.Model) EnsureWritable(dir);
            if (o.Module)
            {
                using (Stream zip = Assembly.GetExecutingAssembly().GetManifestResourceStream("module.zip"))
                {
                    if (zip == null) throw new InvalidOperationException("module.zip is missing in the installer");
                    ExtractModule(zip, dir);
                }
                log(T.F("module_done", dir));
            }

            if (o.LocalVocal)
            {
                if (LocalVocalInstalled()) log(T.S("localvocal_present"));
                else if (ObsRunning()) log(T.S("localvocal_obs_running"));
                else
                {
                    log(T.S("localvocal_find"));
                    string url = LocalVocalInstallerUrl(o.Gpu);
                    if (url == null) throw new InvalidOperationException(T.S("localvocal_no_asset"));
                    string file = Path.Combine(Path.GetTempPath(), Path.GetFileName(new Uri(url).LocalPath));
                    log(T.F("downloading", url));
                    Download(url, file, null, progress, cancelled);
                    log(T.S("localvocal_run"));
                    using (Process p = Process.Start(new ProcessStartInfo(file) { UseShellExecute = true })) p.WaitForExit();
                    log(LocalVocalInstalled() ? T.S("localvocal_done") : T.S("localvocal_missing"));
                }
            }

            if (o.Model)
            {
                ModelInfo m = FindModel(o.ModelId) ?? Models[0];
                string how = PlaceModel(m, dir, log, progress, cancelled);
                log(T.F("model_" + how, m.Name, how == "localvocal" ? LocalVocalModelPath(m) : ModuleModelPath(dir, m)));
            }

            bool ready = false; // обновление, и фильтр LocalVocal уже настроен: «Настроить всё» нажимать не нужно
            if (o.Script)
            {
                string collection = CurrentCollectionPath();
                string script = Path.Combine(dir, ScriptFile);
                if (collection == null) log(T.F("script_manual", script));
                else if (ObsRunning()) log(T.F("script_obs_running", script));
                else
                {
                    string json = System.IO.File.ReadAllText(collection, Encoding.UTF8);
                    string next = AddScript(json, script, PresetSettings(o.Preset, o.Name, o.Device, o.ModelId));
                    if (next != json)
                    {
                        System.IO.File.Copy(collection, collection + ".before-live-subtitles", true);
                        System.IO.File.WriteAllText(collection, next, new UTF8Encoding(false));
                        log(T.F("script_done", Path.GetFileNameWithoutExtension(collection)));
                    }
                    else
                    {
                        // Обновление: выбранные сейчас устройство и модель — в настройки скрипта, а в фильтр LocalVocal — то,
                        // что поставила бы кнопка «Настроить всё»: OBS при запуске сразу работает с новыми настройками.
                        next = UpdateLocalVocal(SetScriptSettings(json, ScriptPatch(o)));
                        string copy = ".before-live-subtitles-" + Version;
                        if (next != json)
                        {
                            System.IO.File.Copy(collection, collection + copy, true);
                            System.IO.File.WriteAllText(collection, next, new UTF8Encoding(false));
                        }
                        string device = ScriptDevice(next), model = ScriptModelId(next);
                        log(T.F(next != json ? "script_updated" : "script_present",
                            T.S(device == "cpu" ? "on_cpu" : device == "keep" ? "on_keep" : "on_gpu"),
                            model == "" ? T.S("model_as_set") : FindModel(model).Name, copy));
                        ready = HasLocalVocal(next);
                        if (!ready) log(T.S("setup_needed"));
                    }
                }
            }
            log(T.S(ready ? "finish_update" : "finish"));
        }

        // ---------- запуск ----------

        [STAThread]
        public static int Main(string[] args)
        {
            List<string> list = new List<string>(args);
            if (!list.Contains("--auto"))
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new SetupForm());
                return 0;
            }
            Options o = new Options();
            for (int i = 0; i < list.Count; i++)
            {
                string next = i + 1 < list.Count ? list[i + 1] : "";
                switch (list[i])
                {
                    case "--dir": o.Dir = next; i++; break;
                    case "--preset": o.Preset = next; i++; break;
                    case "--name": o.Name = next; i++; break;
                    case "--gpu": o.Gpu = next; i++; break;
                    case "--device": o.Device = next == "cpu" ? "cpu" : "gpu"; o.DeviceChosen = true; i++; break;
                    case "--model": if (next == "none") o.Model = false; else { o.ModelId = next; o.ModelChosen = true; } i++; break;
                    case "--no-model": o.Model = false; break;
                    case "--no-localvocal": o.LocalVocal = false; break;
                    case "--no-script": o.Script = false; break;
                    case "--no-module": o.Module = false; break;
                }
            }
            using (StreamWriter journal = new StreamWriter(LogFile(), false, new UTF8Encoding(false)))
            {
                try
                {
                    Run(o, delegate(string line) { journal.WriteLine(line); journal.Flush(); }, null, null);
                    return 0;
                }
                catch (Exception e)
                {
                    journal.WriteLine("ERROR: " + e.Message);
                    return 1;
                }
            }
        }
    }

    // ---------- подписи: по-русски, если Windows на русском (или украинском, белорусском, казахском), иначе по-английски ----------

    public static class T
    {
        static readonly string Lang = Array.IndexOf(new[] { "ru", "uk", "be", "kk" }, CultureInfo.CurrentUICulture.TwoLetterISOLanguageName) >= 0 ? "ru" : "en";

        static readonly Dictionary<string, string[]> Text = new Dictionary<string, string[]>
        {
            // ключ → { русский, английский }
            { "title", new[] { "Live Subtitles для OBS — установка", "Live Subtitles for OBS — setup" } },
            { "intro", new[] { "Английские субтитры вашей речи на стриме. Это обёртка для быстрой установки: распознаёт и переводит LocalVocal (Roy Shilkrot) на whisper.cpp и модели OpenAI Whisper — установщик скачивает их с официальных сайтов.",
                               "English subtitles of your speech on stream. This is a quick-install wrapper: recognition and translation are done by LocalVocal (Roy Shilkrot) on whisper.cpp and the OpenAI Whisper model, downloaded from their official sites." } },
            { "folder", new[] { "Папка установки", "Install folder" } },
            { "browse", new[] { "Обзор…", "Browse…" } },
            { "browse_title", new[] { "Куда поставить Live Subtitles: модуль и модель Whisper. Можно любой диск — внутри создастся папка LiveSubtitles.", "Where to install Live Subtitles: the module and the Whisper model. Any drive works — a LiveSubtitles folder is created inside." } },
            { "folder_hint", new[] { "Сюда лягут модуль и модель Whisper (до 1 ГБ). Свободно на диске {0} — {1} ГБ", "The module and the Whisper model (up to 1 GB) go here. Free on {0} — {1} GB" } },
            { "folder_bad", new[] { "Такой папки не может быть — проверьте путь.", "This can't be a folder — check the path." } },
            { "dir_not_writable", new[] { "В папку «{0}» нельзя записать ({1}). Выберите другую, например на другом диске.", "Can't write to “{0}” ({1}). Pick another folder, e.g. on another drive." } },
            { "module", new[] { "Модуль Live Subtitles", "Live Subtitles module" } },
            { "module_hint", new[] { "скрипт, оверлей и наборы сленга (2 МБ)", "script, overlay and slang packs (2 MB)" } },
            { "model", new[] { "Модель Whisper", "Whisper model" } },
            { "model_medium", new[] { "Medium — лучший перевод, нужна видеокарта (514 МБ)", "Medium — best translation, needs a GPU (514 MB)" } },
            { "model_small", new[] { "Small — для слабых ПК (181 МБ)", "Small — for weak PCs (181 MB)" } },
            { "model_large", new[] { "Large v3 — лучше всех, тяжёлая (1 ГБ)", "Large v3 — the best, heavy (1 GB)" } },
            { "device", new[] { "Перевод считать на", "Run translation on" } },
            { "device_gpu", new[] { "видеокарте — быстро (рекомендуем)", "graphics card — fast (recommended)" } },
            { "device_cpu", new[] { "процессоре — не трогает видеокарту, медленнее", "processor — leaves the graphics card alone, slower" } },
            { "device_hint", new[] { "Если игра подлагивает, пока вы говорите, — процессор: субтитры придут на пару секунд позже, модель лучше Small. Поменять можно и потом: запустите установщик ещё раз или смените в окне скрипта.", "If your game stutters while you talk, pick the processor: subtitles come a couple of seconds later, Small works best. You can change it later: run the installer again or change it in the script window." } },
            { "on_gpu", new[] { "видеокарте", "graphics card" } },
            { "on_cpu", new[] { "процессоре", "processor" } },
            { "on_keep", new[] { "устройстве из настроек LocalVocal", "device set in LocalVocal" } },
            { "model_as_set", new[] { "как в LocalVocal", "as set in LocalVocal" } },
            { "localvocal", new[] { "Плагин LocalVocal для OBS", "LocalVocal plugin for OBS" } },
            { "gpu_generic", new[] { "любая видеокарта (Vulkan) — если не знаете, эта", "any GPU (Vulkan) — if unsure, this one" } },
            { "gpu_nvidia", new[] { "NVIDIA (CUDA, нужны свежие драйверы)", "NVIDIA (CUDA, needs fresh drivers)" } },
            { "installed", new[] { "уже установлен", "already installed" } },
            { "script", new[] { "Добавить скрипт в OBS", "Add the script to OBS" } },
            { "script_update", new[] { "Обновить настройки в OBS", "Update the settings in OBS" } },
            { "collection", new[] { "коллекция сцен «{0}»", "scene collection “{0}”" } },
            { "no_collection", new[] { "коллекция сцен не найдена — добавите скрипт сами", "no scene collection found — you will add the script yourself" } },
            { "preset", new[] { "Стиль субтитров", "Subtitle style" } },
            { "preset_basic", new[] { "Базовый — киношные субтитры", "Basic — movie subtitles" } },
            { "preset_eve", new[] { "EVE Online — окно интерфейса + сленг EVE", "EVE Online — interface window + EVE slang" } },
            { "preset_wow", new[] { "World of Warcraft — /say + сленг WoW", "World of Warcraft — /say + WoW slang" } },
            { "name", new[] { "Ник на экране (для EVE и WoW)", "Name on screen (for EVE and WoW)" } },
            { "close_obs", new[] { "Закройте OBS: пока он открыт, LocalVocal не установить и скрипт не добавить.", "Close OBS: while it is open, LocalVocal can't be installed and the script can't be added." } },
            { "install", new[] { "Установить", "Install" } },
            { "close", new[] { "Закрыть", "Close" } },
            { "open_obs", new[] { "Открыть OBS", "Open OBS" } },
            { "module_done", new[] { "Модуль установлен: {0}", "Module installed: {0}" } },
            { "localvocal_present", new[] { "LocalVocal уже установлен.", "LocalVocal is already installed." } },
            { "localvocal_obs_running", new[] { "LocalVocal: закройте OBS и запустите установщик ещё раз.", "LocalVocal: close OBS and run the installer again." } },
            { "localvocal_find", new[] { "Ищу последний релиз LocalVocal на GitHub…", "Looking up the latest LocalVocal release on GitHub…" } },
            { "localvocal_no_asset", new[] { "В последнем релизе LocalVocal не нашёлся установщик для Windows — поставьте его вручную: github.com/royshil/obs-localvocal/releases", "No Windows installer in the latest LocalVocal release — install it by hand: github.com/royshil/obs-localvocal/releases" } },
            { "downloading", new[] { "Скачиваю {0}", "Downloading {0}" } },
            { "localvocal_run", new[] { "Запускаю установщик LocalVocal — пройдите его до конца.", "Starting the LocalVocal installer — go through it to the end." } },
            { "localvocal_done", new[] { "LocalVocal установлен.", "LocalVocal installed." } },
            { "localvocal_missing", new[] { "LocalVocal не нашёлся после установки — проверьте в OBS, есть ли фильтр «LocalVocal Transcription».", "LocalVocal not found after its installer — check in OBS for the “LocalVocal Transcription” filter." } },
            { "model_start", new[] { "Скачиваю модель {0} с {1} (если не идёт — включите VPN или возьмите сборку -offline)", "Downloading {0} from {1} (if it stalls, use a VPN or the -offline build)" } },
            { "model_present", new[] { "Модель {0} уже на месте: {1}", "Model {0} is already in place: {1}" } },
            { "model_localvocal", new[] { "Модель {0} уже скачана LocalVocal, вторая копия не нужна: {1}", "Model {0} was already downloaded by LocalVocal, no second copy needed: {1}" } },
            { "model_embedded", new[] { "Модель {0} из установщика: {1}", "Model {0} from the installer: {1}" } },
            { "model_beside", new[] { "Модель {0} скопирована из папки установщика: {1}", "Model {0} copied from the installer folder: {1}" } },
            { "model_downloaded", new[] { "Модель {0} скачана и проверена: {1}", "Model {0} downloaded and verified: {1}" } },
            { "bad_hash", new[] { "Файл модели повреждён (не совпал SHA-256) — запустите установку ещё раз.", "The model file is corrupt (SHA-256 mismatch) — run the setup again." } },
            { "script_present", new[] { "Live Subtitles уже есть в OBS, менять нечего: перевод на {0}, модель — {1}.", "Live Subtitles is already in OBS, nothing to change: translation on the {0}, model: {1}." } },
            { "script_updated", new[] { "Live Subtitles уже был в OBS — обновил его настройки и фильтр LocalVocal: перевод на {0}, модель — {1} (копия коллекции до правки — рядом, {2}).", "Live Subtitles was already in OBS; its settings and LocalVocal filter are updated: translation on the {0}, model: {1} (a copy of the collection from before is next to it, {2})." } },
            { "setup_needed", new[] { "Фильтра LocalVocal на микрофоне скрипта ещё нет — его создаст кнопка «Настроить всё» в окне скрипта.", "There is no LocalVocal filter on the script microphone yet: “Set up everything” in the script window creates it." } },
            { "finish_update", new[] { "Готово. Запустите OBS — субтитры заработают с этими настройками, «Настроить всё» нажимать не нужно. Стиль и ник меняются в окне скрипта.", "Done. Start OBS: the subtitles run with these settings, no need to press “Set up everything”. Style and name are changed in the script window." } },
            { "script_done", new[] { "Скрипт добавлен в OBS, коллекция «{0}» (копия до правки — рядом, .before-live-subtitles).", "Script added to OBS, collection “{0}” (a copy from before is next to it, .before-live-subtitles)." } },
            { "script_obs_running", new[] { "OBS открыт — скрипт добавьте сами: Сервис → Скрипты → + → {0}", "OBS is open — add the script yourself: Tools → Scripts → + → {0}" } },
            { "script_manual", new[] { "Добавьте скрипт сами: OBS → Сервис → Скрипты → + → {0}", "Add the script yourself: OBS → Tools → Scripts → + → {0}" } },
            { "finish", new[] { "Готово. Откройте OBS → Сервис → Скрипты → live-subtitles.lua → «Настроить всё», потом «Показать тест».", "Done. Open OBS → Tools → Scripts → live-subtitles.lua → “Set up everything”, then “Show test”." } },
            { "error", new[] { "Ошибка: {0}", "Error: {0}" } },
        };

        public static string S(string key)
        {
            string[] pair;
            return Text.TryGetValue(key, out pair) ? pair[Lang == "ru" ? 0 : 1] : key;
        }

        public static string F(string key, params object[] args) { return string.Format(S(key), args); }
    }

    // ---------- окно ----------

    public sealed class SetupForm : Form
    {
        readonly CheckBox module = new CheckBox(), model = new CheckBox(), localVocal = new CheckBox(), script = new CheckBox();
        readonly ComboBox modelList = new ComboBox(), deviceList = new ComboBox(), gpuList = new ComboBox(), presetList = new ComboBox();
        readonly TextBox folderBox = new TextBox(), nameBox = new TextBox(), logBox = new TextBox();
        readonly Label folderHint = new Label(), scriptNote = new Label(), obsNote = new Label();
        readonly ProgressBar bar = new ProgressBar();
        readonly Button browse = new Button(), install = new Button(), close = new Button(), openObs = new Button();
        volatile bool closing;
        // Обновление: списки показывают, что уже стоит у скрипта; к нему применяется только то, что стример сменил.
        readonly string current = Setup.CurrentCollectionJson();
        int initialModel, initialDevice;

        static readonly string[] ModelIds = { "medium", "small", "large" };
        static readonly string[] Gpus = { "generic", "nvidia" };
        static readonly string[] Devices = { "gpu", "cpu" };
        static readonly string[] Presets = { "basic", "eve", "wow" };
        const string FolderName = "LiveSubtitles";

        public SetupForm()
        {
            Text = T.S("title") + " " + Setup.Version;
            Font = SystemFonts.MessageBoxFont;
            AutoScaleMode = AutoScaleMode.Font;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(660, 710);

            TableLayoutPanel table = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, Padding = new Padding(14), AutoScroll = true };
            table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 40));
            table.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 60));
            Controls.Add(table);
            int row = 0;

            Label intro = new Label { Text = T.S("intro"), AutoSize = true, MaximumSize = new Size(620, 0), Margin = new Padding(0, 0, 0, 10) };
            table.Controls.Add(intro, 0, row);
            table.SetColumnSpan(intro, 2);
            row++;

            // Папка установки: модуль и модель Whisper; «Обзор…» — любая папка на любом диске.
            folderBox.Text = Setup.DefaultDir();
            folderBox.Dock = DockStyle.Fill;
            folderBox.TextChanged += delegate { UpdateFolderHint(); };
            browse.Text = T.S("browse"); browse.AutoSize = true; browse.Click += delegate { Browse(); };
            TableLayoutPanel folderRow = new TableLayoutPanel { ColumnCount = 2, Dock = DockStyle.Fill, AutoSize = true, Margin = new Padding(0) };
            folderRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            folderRow.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            folderRow.Controls.Add(folderBox, 0, 0);
            folderRow.Controls.Add(browse, 1, 0);
            table.Controls.Add(new Label { Text = T.S("folder"), AutoSize = true, Anchor = AnchorStyles.Left }, 0, row);
            table.Controls.Add(folderRow, 1, row);
            row++;
            folderHint.AutoSize = true; folderHint.MaximumSize = new Size(390, 0); folderHint.ForeColor = SystemColors.GrayText;
            folderHint.Margin = new Padding(3, 0, 3, 8);
            table.Controls.Add(folderHint, 1, row);
            row++;

            module.Text = T.S("module"); module.Checked = true; module.AutoSize = true;
            table.Controls.Add(module, 0, row);
            table.Controls.Add(new Label { Text = T.S("module_hint"), AutoSize = true, Anchor = AnchorStyles.Left, ForeColor = SystemColors.GrayText }, 1, row);
            row++;

            model.Text = T.S("model"); model.Checked = true; model.AutoSize = true;
            modelList.DropDownStyle = ComboBoxStyle.DropDownList; modelList.Dock = DockStyle.Fill;
            foreach (string id in ModelIds) modelList.Items.Add(T.S("model_" + id));
            modelList.SelectedIndex = Math.Max(0, Array.IndexOf(ModelIds, Setup.ScriptModelId(current)));
            table.Controls.Add(model, 0, row);
            table.Controls.Add(modelList, 1, row);
            row++;

            // Где считать перевод. Процессор медленнее — с ним сразу предлагаем Small вместо Medium.
            deviceList.DropDownStyle = ComboBoxStyle.DropDownList; deviceList.Dock = DockStyle.Fill;
            foreach (string device in Devices) deviceList.Items.Add(T.S("device_" + device));
            deviceList.SelectedIndex = Setup.ScriptDevice(current) == "cpu" ? 1 : 0;
            initialModel = modelList.SelectedIndex;
            initialDevice = deviceList.SelectedIndex;
            deviceList.SelectedIndexChanged += delegate
            {
                if (Devices[Math.Max(0, deviceList.SelectedIndex)] == "cpu" && ModelIds[Math.Max(0, modelList.SelectedIndex)] == "medium")
                    modelList.SelectedIndex = Array.IndexOf(ModelIds, "small");
            };
            table.Controls.Add(new Label { Text = T.S("device"), AutoSize = true, Anchor = AnchorStyles.Left }, 0, row);
            table.Controls.Add(deviceList, 1, row);
            row++;
            Label deviceHint = new Label { Text = T.S("device_hint"), AutoSize = true, MaximumSize = new Size(390, 0), ForeColor = SystemColors.GrayText, Margin = new Padding(3, 0, 3, 8) };
            table.Controls.Add(deviceHint, 1, row);
            row++;

            localVocal.Text = T.S("localvocal"); localVocal.AutoSize = true;
            bool hasLocalVocal = Setup.LocalVocalInstalled();
            localVocal.Checked = !hasLocalVocal;
            localVocal.Enabled = !hasLocalVocal;
            table.Controls.Add(localVocal, 0, row);
            if (hasLocalVocal)
            {
                table.Controls.Add(new Label { Text = "✓ " + T.S("installed"), AutoSize = true, Anchor = AnchorStyles.Left, ForeColor = Color.SeaGreen }, 1, row);
            }
            else
            {
                gpuList.DropDownStyle = ComboBoxStyle.DropDownList; gpuList.Dock = DockStyle.Fill;
                foreach (string gpu in Gpus) gpuList.Items.Add(T.S("gpu_" + gpu));
                gpuList.SelectedIndex = 0;
                table.Controls.Add(gpuList, 1, row);
            }
            row++;

            string collection = Setup.CurrentCollectionName();
            bool added = Setup.ScriptAdded(current);
            script.Text = T.S(added ? "script_update" : "script"); script.AutoSize = true; script.Checked = collection != null; script.Enabled = collection != null;
            scriptNote.Text = collection != null ? T.F("collection", collection) : T.S("no_collection");
            scriptNote.AutoSize = true; scriptNote.MaximumSize = new Size(390, 0); scriptNote.ForeColor = SystemColors.GrayText;
            table.Controls.Add(script, 0, row);
            table.Controls.Add(scriptNote, 1, row);
            row++;

            presetList.DropDownStyle = ComboBoxStyle.DropDownList; presetList.Dock = DockStyle.Fill;
            foreach (string preset in Presets) presetList.Items.Add(T.S("preset_" + preset));
            // Обновление: стиль и ник уже добавленного скрипта меняются в окне скрипта, здесь они только видны.
            presetList.SelectedIndex = Math.Max(0, Array.IndexOf(Presets, Setup.ScriptPreset(current)));
            presetList.Enabled = !added;
            table.Controls.Add(new Label { Text = T.S("preset"), AutoSize = true, Anchor = AnchorStyles.Left }, 0, row);
            table.Controls.Add(presetList, 1, row);
            row++;

            nameBox.Dock = DockStyle.Fill;
            nameBox.Text = Setup.ScriptSetting(current, "name", "") ?? "";
            nameBox.Enabled = !added;
            table.Controls.Add(new Label { Text = T.S("name"), AutoSize = true, Anchor = AnchorStyles.Left }, 0, row);
            table.Controls.Add(nameBox, 1, row);
            row++;

            obsNote.Text = T.S("close_obs"); obsNote.AutoSize = true; obsNote.MaximumSize = new Size(620, 0); obsNote.ForeColor = Color.Firebrick;
            obsNote.Visible = Setup.ObsRunning();
            table.Controls.Add(obsNote, 0, row);
            table.SetColumnSpan(obsNote, 2);
            row++;

            bar.Dock = DockStyle.Fill; bar.Minimum = 0; bar.Maximum = 1000;
            table.Controls.Add(bar, 0, row);
            table.SetColumnSpan(bar, 2);
            row++;

            logBox.Multiline = true; logBox.ReadOnly = true; logBox.ScrollBars = ScrollBars.Vertical; logBox.Dock = DockStyle.Fill; logBox.Height = 160;
            table.Controls.Add(logBox, 0, row);
            table.SetColumnSpan(logBox, 2);
            row++;

            FlowLayoutPanel buttons = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, Dock = DockStyle.Fill, AutoSize = true };
            close.Text = T.S("close"); close.AutoSize = true; close.Click += delegate { Close(); };
            install.Text = T.S("install"); install.AutoSize = true; install.Click += delegate { Start(); };
            openObs.Text = T.S("open_obs"); openObs.AutoSize = true; openObs.Enabled = Setup.ObsExe() != null; openObs.Click += delegate { OpenObs(); };
            buttons.Controls.Add(close);
            buttons.Controls.Add(install);
            buttons.Controls.Add(openObs);
            table.Controls.Add(buttons, 0, row);
            table.SetColumnSpan(buttons, 2);

            AcceptButton = install;
            ActiveControl = install;
            FormClosing += delegate { closing = true; };
            UpdateFolderHint();
        }

        // Выбранная в «Обзоре» папка — родитель: в ней создаётся LiveSubtitles (если это не она сама).
        void Browse()
        {
            using (FolderBrowserDialog dialog = new FolderBrowserDialog())
            {
                dialog.Description = T.S("browse_title");
                dialog.ShowNewFolderButton = true;
                string current = folderBox.Text.Trim();
                try
                {
                    string parent = Directory.Exists(current) ? current : Path.GetDirectoryName(current);
                    if (!string.IsNullOrEmpty(parent) && Directory.Exists(parent)) dialog.SelectedPath = parent;
                }
                catch (Exception) { }
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                string chosen = dialog.SelectedPath;
                if (!string.Equals(Path.GetFileName(chosen.TrimEnd(Path.DirectorySeparatorChar)), FolderName, StringComparison.OrdinalIgnoreCase))
                    chosen = Path.Combine(chosen, FolderName);
                folderBox.Text = chosen;
            }
        }

        // Под полем — что туда ляжет и сколько места на этом диске; меньше 1,2 ГБ — красным.
        void UpdateFolderHint()
        {
            try
            {
                string root = Path.GetPathRoot(Path.GetFullPath(folderBox.Text.Trim()));
                DriveInfo drive = new DriveInfo(root);
                double gb = drive.AvailableFreeSpace / 1073741824.0;
                folderHint.Text = T.F("folder_hint", root.TrimEnd(Path.DirectorySeparatorChar), gb.ToString("0.#", CultureInfo.CurrentCulture));
                folderHint.ForeColor = gb < 1.2 ? Color.Firebrick : SystemColors.GrayText;
            }
            catch (Exception)
            {
                folderHint.Text = T.S("folder_bad");
                folderHint.ForeColor = Color.Firebrick;
            }
        }

        void Log(string line)
        {
            if (InvokeRequired) { BeginInvoke(new Action<string>(Log), line); return; }
            logBox.AppendText(line + Environment.NewLine);
        }

        void Report(long done, long total)
        {
            if (total <= 0) return;
            int value = (int)Math.Min(1000, done * 1000 / total);
            if (InvokeRequired) { BeginInvoke(new Action(delegate { bar.Value = value; })); return; }
            bar.Value = value;
        }

        void Start()
        {
            Options o = new Options
            {
                Module = module.Checked,
                Model = model.Checked,
                LocalVocal = localVocal.Checked,
                Script = script.Checked,
                ModelId = ModelIds[Math.Max(0, modelList.SelectedIndex)],
                Device = Devices[Math.Max(0, deviceList.SelectedIndex)],
                DeviceChosen = deviceList.SelectedIndex != initialDevice,
                ModelChosen = modelList.SelectedIndex != initialModel,
                Gpu = Gpus[Math.Max(0, gpuList.SelectedIndex)],
                Preset = Presets[Math.Max(0, presetList.SelectedIndex)],
                Name = nameBox.Text,
                Dir = folderBox.Text.Trim(),
            };
            install.Enabled = false;
            browse.Enabled = false;
            folderBox.ReadOnly = true;
            obsNote.Visible = Setup.ObsRunning();
            Thread worker = new Thread(delegate()
            {
                try { Setup.Run(o, Log, Report, delegate { return closing; }); }
                catch (OperationCanceledException) { }
                catch (Exception e) { Log(T.F("error", e.Message)); }
                finally
                {
                    if (!closing) BeginInvoke(new Action(delegate { install.Enabled = true; browse.Enabled = true; folderBox.ReadOnly = false; bar.Value = 0; }));
                }
            });
            worker.IsBackground = true;
            worker.Start();
        }

        void OpenObs()
        {
            string exe = Setup.ObsExe();
            if (exe == null) return;
            Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = Path.GetDirectoryName(exe), UseShellExecute = true });
        }
    }
}
