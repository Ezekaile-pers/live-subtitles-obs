import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import { load, root } from './load.mjs';

const require = createRequire(import.meta.url);
const LS = load('profanity', 'wow');
require(path.join(root, 'overlay', 'overlay.js'));

// Мини-DOM: ровно то, что трогает render — элементы, классы, текст, dataset, CSS-переменные.
class El {
  constructor(tag) { this.tagName = tag.toUpperCase(); this.className = ''; this.children = []; this.dataset = {}; this.ownText = ''; this.style = { props: {}, setProperty: (k, v) => { this.style.props[k] = v; } }; }
  appendChild(child) { this.children.push(child); return child; }
  get textContent() { return this.ownText + this.children.map((c) => c.textContent).join(''); }
  set textContent(value) { this.children = []; this.ownText = String(value); }
}
const doc = { createElement: (tag) => new El(tag) };
const find = (el, cls) => (el.className.split(' ').includes(cls) ? [el] : []).concat(...el.children.map((c) => find(c, cls)));
const renderInto = (config, lines, now) => { const box = new El('div'); LS.render(box, config, lines, { doc, now }); return box; };
const cfg = (search) => LS.parseConfig(search);
const at = new Date(2026, 9, 18, 3, 41, 12);

test('parseConfig: умолчания', () => {
  const c = cfg('');
  assert.deepEqual(
    { style: c.style, name: c.name, showName: c.showName, size: c.size, position: c.position, align: c.align, offset: c.offset, width: c.width, lines: c.lines, fade: c.fade, packs: c.packs, censor: c.censor, hide: c.hide, demo: c.demo },
    { style: 'classic', name: '', showName: false, size: 40, position: 'bottom', align: 'center', offset: 8, width: 70, lines: 2, fade: 6, packs: [], censor: true, hide: [], demo: false },
  );
});

test('parseConfig: значения из URL, границы, неизвестный стиль', () => {
  const c = cfg('?style=eve-local&name=Space%20Pilot&size=500&lines=9&offset=-3&width=5&fade=999&packs=eve,wow&censor=0&hide=Tom,%20Vasya,&position=top&align=left');
  assert.equal(c.style, 'eve-local');
  assert.equal(c.name, 'Space Pilot');
  assert.equal(c.size, 160);
  assert.equal(c.lines, 4);
  assert.equal(c.offset, 0);
  assert.equal(c.width, 20);
  assert.equal(c.fade, 60);
  assert.deepEqual(c.packs, ['eve', 'wow']);
  assert.equal(c.censor, false);
  assert.deepEqual(c.hide, ['Tom', 'Vasya']);
  assert.equal(c.position, 'top');
  assert.equal(c.align, 'left');
  assert.equal(cfg('?style=matrix').style, 'classic');
  assert.equal(cfg('?position=sideways&align=up').position, 'bottom');
  assert.equal(cfg('?size=abc').size, 40, 'мусор — по умолчанию');
});

test('parseConfig: ник показывается по стилю, параметр перекрывает', () => {
  for (const style of ['eve-photon', 'eve-local', 'wow']) assert.equal(cfg(`?style=${style}`).showName, true, style);
  for (const style of ['classic', 'box']) assert.equal(cfg(`?style=${style}`).showName, false, style);
  assert.equal(cfg('?style=wow&showName=0').showName, false);
  assert.equal(cfg('?style=classic&showName=1').showName, true);
});

test('parseConfig: цвета только #rgb/#rrggbb, шрифт без кавычек и скобок — в CSS ничего не протечёт', () => {
  assert.equal(cfg('?nameColor=%23f58cba').nameColor, '#f58cba');
  assert.equal(cfg('?accent=%2356d').accent, '#56d');
  assert.equal(cfg('?nameColor=red;background:url(x)').nameColor, '');
  assert.equal(cfg('?font=Bahnschrift%20SemiCondensed').font, 'Bahnschrift SemiCondensed');
  assert.equal(cfg('?font=x;}body{display:none').font, '');
});

test('trimTail: длинная фраза — хвост с «…» по границе слова', () => {
  assert.equal(LS.trimTail('short text', 50), 'short text');
  const long = 'Today we are going to Westfall and then to the Deadmines to kill VanCleef and his whole gang of thieves again';
  const tail = LS.trimTail(long, 40);
  assert.ok(tail.length <= 41, tail);
  assert.ok(tail.startsWith('…'), tail);
  assert.ok(long.endsWith(tail.slice(1)), 'это настоящий хвост фразы');
  assert.ok(long.split(' ').includes(tail.slice(1).split(' ')[0]), 'первое слово хвоста целое, не обрубок');
});

test('nextLines: частичные результаты обновляют строку, новая фраза — новая строка, лишние уходят', () => {
  let lines = [];
  lines = LS.nextLines(lines, 'Today we', 2, at);
  lines = LS.nextLines(lines, 'Today we go to Westfall', 2, at);
  assert.deepEqual(lines.map((l) => l.text), ['Today we go to Westfall'], 'та же фраза растёт');
  lines = LS.nextLines(lines, 'Hogger again', 2, at);
  assert.deepEqual(lines.map((l) => l.text), ['Today we go to Westfall', 'Hogger again']);
  lines = LS.nextLines(lines, 'Mage, water please', 2, at);
  assert.deepEqual(lines.map((l) => l.text), ['Hogger again', 'Mage, water please'], 'не больше lines строк');
  assert.deepEqual(LS.nextLines(lines, '', 2, at), lines, 'пустой текст строки не трогает — их гасит таймер');
  assert.deepEqual(LS.nextLines([], 'One', 1, at).map((l) => l.text), ['One']);
  assert.deepEqual(LS.nextLines([{ text: 'One', at }], 'Two', 1, at).map((l) => l.text), ['Two']);
});

test('render classic и box: только текст, ник по желанию', () => {
  const plain = renderInto(cfg('?style=classic'), [{ text: 'hello chat', at }], at);
  assert.equal(plain.dataset.style, 'classic');
  assert.deepEqual(find(plain, 'line').map((l) => l.textContent), ['Hello chat']);
  assert.equal(find(plain, 'who').length, 0);
  const named = renderInto(cfg('?style=box&showName=1&name=Ezekaile'), [{ text: 'hi', at }], at);
  assert.equal(find(named, 'line')[0].textContent, 'Ezekaile: Hi');
});

test('render wow: «[Ник] says: …», цвет ника — CSS-переменной', () => {
  const box = renderInto(cfg('?style=wow&name=Ezekaile&nameColor=%23f58cba&packs=wow'), [{ text: 'Orda is camping again', at }], at);
  assert.equal(find(box, 'line')[0].textContent, '[Ezekaile] says: Horde is camping again');
  assert.equal(find(box, 'who')[0].textContent, '[Ezekaile]');
  assert.equal(box.style.props['--name-color'], '#f58cba');
});

test('render eve-local: строка локального чата «[ 03:41:12 ] Ник > текст»', () => {
  const box = renderInto(cfg('?style=eve-local&name=Space%20Pilot'), [{ text: 'warp to zero', at }], at);
  assert.equal(find(box, 'line')[0].textContent, '[ 03:41:12 ] Space Pilot > Warp to zero');
  assert.equal(find(box, 'time')[0].textContent, '[ 03:41:12 ]');
});

test('render eve-photon: панель, ник капсом в шапке, строки под ней', () => {
  const box = renderInto(cfg('?style=eve-photon&name=Pilot&accent=%2356d4e0'), [{ text: 'first', at }, { text: 'second', at }], at);
  const panel = find(box, 'panel');
  assert.equal(panel.length, 1);
  assert.equal(find(panel[0], 'head')[0].textContent, 'Pilot');
  assert.deepEqual(find(panel[0], 'line').map((l) => l.textContent), ['First', 'Second']);
  assert.equal(box.style.props['--accent'], '#56d4e0');
});

test('render: чистка наборами и цензура, кавычки, обратный слэш и эмодзи доходят как есть', () => {
  const box = renderInto(cfg('?style=classic'), [{ text: 'He said "hi" \\ there 🙂, fuck', at }], at);
  assert.equal(find(box, 'line')[0].textContent, 'He said "hi" \\ there 🙂, ****');
  const off = renderInto(cfg('?style=classic&censor=0&hide=Tom'), [{ text: 'Tom fuck', at }], at);
  assert.equal(find(off, 'line')[0].textContent, '*** fuck');
});

// Лента текста: что видно на экране после каждого текста из LocalVocal и по таймерам затухания.
function feedWith(t, search) {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const seen = { lines: [], gone: false };
  const onText = LS.createFeed(cfg(search), { draw: (lines) => { seen.lines = lines.map((l) => l.text); }, gone: (on) => { seen.gone = on; } });
  return { seen, onText, tick: (ms) => t.mock.timers.tick(ms) };
}

test('лента: через fade секунд тишины строки гаснут и убираются', (t) => {
  const { seen, onText, tick } = feedWith(t, '?fade=2');
  onText('first');
  assert.deepEqual(seen.lines, ['first']);
  tick(1999);
  assert.equal(seen.gone, false);
  tick(1);
  assert.equal(seen.gone, true, 'гаснет');
  tick(450);
  assert.deepEqual(seen.lines, [], 'после угасания строк нет');
  assert.equal(seen.gone, false, 'сцена снова готова к тексту');
});

test('лента: фраза, пришедшая во время угасания, не стирается', (t) => {
  const { seen, onText, tick } = feedWith(t, '?fade=2');
  onText('first');
  tick(2000);
  tick(200);
  onText('second');
  tick(1000);
  assert.deepEqual(seen.lines, ['second'], 'старая строка ушла, новая осталась');
  assert.equal(seen.gone, false);
});

test('лента: fade=0 — строки висят, пока LocalVocal не очистит текст', (t) => {
  const { seen, onText, tick } = feedWith(t, '?fade=0');
  onText('first');
  tick(60000);
  assert.deepEqual(seen.lines, ['first']);
  onText('');
  tick(450);
  assert.deepEqual(seen.lines, []);
});

test('события: текст — в ленту, {test:true} — примеры набора по очереди, живая речь прерывает тест', (t) => {
  t.mock.timers.enable({ apis: ['setTimeout'] });
  const seen = [];
  const handle = LS.createHandler(cfg('?packs=eve'), (text) => seen.push(text));
  handle({ text: 'warp to zero' });
  assert.deepEqual(seen, ['warp to zero']);
  handle({ test: true });
  const samples = LS.samplesFor(['eve']);
  assert.equal(seen[1], samples[0], 'первый пример сразу');
  t.mock.timers.tick(2500);
  assert.equal(seen[2], samples[1], 'второй через 2,5 с');
  handle({ text: 'real speech' });
  t.mock.timers.tick(10000);
  assert.deepEqual(seen.slice(3), ['real speech'], 'после живой речи примеры не идут');
  handle({});
  handle({ text: 42 });
  assert.equal(seen.length, 4, 'мусор без текста игнорируется');
});

test('render: анимация появления — только у новой строки; частичные обновления и сдвиг строк не мигают', () => {
  const box = new El('div');
  const draw = (lines) => {
    LS.render(box, cfg('?style=classic'), lines, { doc, now: at });
    return find(box, 'line').map((l) => l.className);
  };
  let lines = LS.nextLines([], 'Warp to zero', 2, at);
  assert.deepEqual(draw(lines), ['line new'], 'первая строка появляется');
  lines = LS.nextLines(lines, 'Warp to zero and jump', 2, at);
  assert.deepEqual(draw(lines), ['line'], 'та же фраза выросла — без анимации');
  lines = LS.nextLines(lines, 'Cyno is up', 2, at);
  assert.deepEqual(draw(lines), ['line', 'line new'], 'новая фраза — новая строка с анимацией');
  lines = LS.nextLines(lines, 'Logi, reps on me', 2, at);
  assert.deepEqual(draw(lines), ['line', 'line new'], 'старая строка уехала вверх без мигания');
  // В CSS анимация висит только на .line.new: иначе любая перерисовка запускает её заново у всех строк.
  const css = fs.readFileSync(path.join(root, 'overlay', 'styles.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  for (const [, selector] of css.matchAll(/([^{}]+)\{[^}]*\banimation\s*:/g)) {
    assert.match(selector, /\.line\.new\b/, `анимация без .new: ${selector.trim()}`);
  }
});

test('render: размер, ширина, отступ, позиция — в CSS-переменных и data-атрибутах', () => {
  const box = renderInto(cfg('?size=56&width=50&offset=12&position=top&align=right&font=Bahnschrift'), [], at);
  assert.equal(box.style.props['--size'], '56px');
  assert.equal(box.style.props['--width'], '50%');
  assert.equal(box.style.props['--offset'], '12%');
  assert.equal(box.style.props['--font'], 'Bahnschrift');
  assert.equal(box.dataset.position, 'top');
  assert.equal(box.dataset.align, 'right');
  assert.equal(find(box, 'line').length, 0, 'без строк — пусто');
});
