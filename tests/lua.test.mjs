// Тесты скрипта OBS live-subtitles.lua: tests/lua/script.test.lua на настоящем LuaJIT из OBS (lua51.dll) через
// tests/lua/run.ps1. Нет Windows или OBS — тест пропускается. Свой путь к lua51.dll — переменная OBS_LUA.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const LUA = process.env.OBS_LUA || 'C:\\Program Files\\obs-studio\\bin\\64bit\\lua51.dll';
const skip = process.platform !== 'win32' || !fs.existsSync(LUA) ? 'нет lua51.dll из OBS' : false;

test('live-subtitles.lua на LuaJIT из OBS', { skip }, () => {
  const run = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(here, 'lua', 'run.ps1'), '-Lua', LUA], { encoding: 'utf8', timeout: 120000 });
  const out = `${run.stdout || ''}${run.stderr || ''}`.trim();
  assert.equal(run.status, 0, out);
  assert.match(out, /^ok \d+$/m, out);
});
