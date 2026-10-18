// Тесты установщика installer/LiveSubtitlesSetup.cs: tests/installer/run.ps1 собирает exe встроенным компилятором
// .NET Framework и проверяет его логику (вставку скрипта в коллекцию OBS, распаковку, закачку с проверкой хеша) и
// «--auto» на поддельном конфиге OBS. Не Windows или нет csc.exe — тест пропускается.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const csc = path.join(process.env.WINDIR || 'C:\\Windows', 'Microsoft.NET', 'Framework64', 'v4.0.30319', 'csc.exe');
const skip = process.platform !== 'win32' || !fs.existsSync(csc) ? 'нет компилятора C# из .NET Framework' : false;

test('установщик LiveSubtitlesSetup.exe', { skip, timeout: 300000 }, () => {
  const run = spawnSync('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(here, 'installer', 'run.ps1')], { encoding: 'utf8', timeout: 280000 });
  const out = `${run.stdout || ''}${run.stderr || ''}`.trim();
  assert.equal(run.status, 0, out);
  assert.match(out, /^ok \d+$/m, out);
});
