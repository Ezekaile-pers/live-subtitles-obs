// Тесты грузят файлы модуля так же, как оверлей в OBS: классические скрипты, общий глобальный объект LiveSubtitles.
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Свежий LiveSubtitles с ядром и нужными наборами: load('profanity', 'wow').
export function load(...packs) {
  const files = [path.join(root, 'overlay', 'clean.js'), ...packs.map((id) => path.join(root, 'packs', `${id}.js`))];
  for (const file of files) delete require.cache[require.resolve(file)];
  delete globalThis.LiveSubtitles;
  for (const file of files) require(file);
  return globalThis.LiveSubtitles;
}
