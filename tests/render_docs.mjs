// Картинки стилей для README: preview.html через Edge headless → docs/style-<стиль>.png (кадр 1920×1080 в 960×540)
// и docs/styles.png (все стили сеткой). Только для разработки — нужны Node и Microsoft Edge: node tests/render_docs.mjs
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const docs = path.join(root, 'docs');
const page = pathToFileURL(path.join(root, 'preview.html')).href;
// Без pack preview.html берёт каждому стилю свои примеры: базовые — обычная речь, EVE и WoW — их сленг.
const STYLES = ['classic', 'box', 'eve-photon', 'eve-local', 'wow'];
const NAME = 'Ezekaile';

const edge = [process.env.EDGE, 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', 'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe']
  .filter(Boolean).find((bin) => fs.existsSync(bin));
if (!edge) {
  console.error('Не нашёл msedge.exe — задай путь в переменной EDGE.');
  process.exit(1);
}

function shot(query, out, width, height, scale) {
  const args = ['--headless=new', '--disable-gpu', '--hide-scrollbars', `--force-device-scale-factor=${scale}`, '--no-first-run',
    '--no-default-browser-check', '--virtual-time-budget=2000', `--window-size=${width},${height}`, `--screenshot=${out}`, `${page}?${query}`];
  const run = spawnSync(edge, args, { encoding: 'utf8', timeout: 60000 });
  const ok = run.status === 0 && fs.existsSync(out);
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${path.relative(root, out)}${ok ? '' : `: ${(run.stderr || '').trim().split('\n').pop()}`}`);
}

fs.mkdirSync(docs, { recursive: true });
for (const style of STYLES) {
  shot(`shot=${style}&name=${encodeURIComponent(NAME)}`, path.join(docs, `style-${style}.png`), 1920, 1080, 0.5);
}
shot(`gallery=1&name=${encodeURIComponent(NAME)}`, path.join(docs, 'styles.png'), 1920, 830, 0.75);
