// Live Subtitles — страница-оверлей. Настройки — из параметров URL (их выставляет скрипт OBS), текст — событием
// окна «live-subtitles» ({ detail: { text } }), которое скрипт шлёт через javascript_event браузерного источника.
// Строки: частичные результаты LocalVocal растят текущую строку, новая фраза — новая строка (не больше lines),
// через fade секунд после последнего слова всё гаснет. Чистка — LiveSubtitles.clean (overlay/clean.js + packs/*.js).
(function (root) {
  'use strict';

  const LS = root.LiveSubtitles;
  const STYLES = ['classic', 'box', 'eve-photon', 'eve-local', 'wow'];
  const NAMED_STYLES = ['eve-photon', 'eve-local', 'wow'];
  const POSITIONS = ['bottom', 'top', 'middle'];
  const ALIGNS = ['left', 'center', 'right'];
  const HEX = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i;
  const FONT = /^[\p{L}\p{N} ,-]+$/u; // имя шрифта — в CSS-переменную, поэтому без кавычек, скобок и точек с запятой
  const SEPARATOR = { classic: ': ', box: ': ', 'eve-local': ' > ', wow: ' says: ' };

  const num = (value, def, min, max) => {
    const n = Number(value);
    if (value === null || value === '' || !Number.isFinite(n)) return def;
    return Math.min(max, Math.max(min, n));
  };
  const list = (value) => String(value || '').split(',').map((s) => s.trim()).filter(Boolean);
  const pick = (value, allowed, def) => (allowed.includes(value) ? value : def);

  function parseConfig(search) {
    const p = new URLSearchParams(search || '');
    const style = pick(p.get('style'), STYLES, 'classic');
    const show = p.get('showName');
    return {
      style,
      name: (p.get('name') || '').trim().slice(0, 40),
      nameColor: HEX.test(p.get('nameColor') || '') ? p.get('nameColor') : '',
      showName: show === '1' ? true : show === '0' ? false : NAMED_STYLES.includes(style),
      size: Math.round(num(p.get('size'), 40, 12, 160)),
      font: FONT.test(p.get('font') || '') ? p.get('font').trim() : '',
      position: pick(p.get('position'), POSITIONS, 'bottom'),
      align: pick(p.get('align'), ALIGNS, 'center'),
      offset: num(p.get('offset'), 8, 0, 45),
      width: num(p.get('width'), 70, 20, 100),
      lines: Math.round(num(p.get('lines'), 2, 1, 4)),
      fade: num(p.get('fade'), 6, 0, 60),
      packs: list(p.get('packs')).filter((id) => /^[a-z0-9_-]+$/i.test(id)),
      censor: p.get('censor') !== '0',
      hide: list(p.get('hide')),
      accent: HEX.test(p.get('accent') || '') ? p.get('accent') : '',
      demo: p.get('demo') === '1',
    };
  }

  // Длинная речь: хвост последних maxChars символов, обрезанный по началу слова.
  function trimTail(text, maxChars) {
    const value = String(text || '');
    if (value.length <= maxChars) return value;
    const cut = value.slice(-maxChars);
    const space = cut.indexOf(' ');
    return '…' + (space >= 0 && space < maxChars / 2 ? cut.slice(space + 1) : cut);
  }

  // Та же фраза, если первые два слова совпали: LocalVocal дописывает фразу частями.
  const words = (s) => String(s).toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, ' ').split(/\s+/).filter(Boolean);
  function sameSentence(prev, next) {
    const a = words(prev);
    const b = words(next);
    if (!a.length || !b.length) return false;
    const n = Math.min(2, a.length, b.length);
    for (let i = 0; i < n; i++) if (a[i] !== b[i]) return false;
    return true;
  }

  // У каждой фразы свой id: по нему render отличает новую строку (с анимацией) от выросшей или сдвинутой (без неё).
  let lineId = 0;
  function nextLines(lines, text, max, now) {
    const value = String(text || '').trim();
    if (!value) return lines;
    const last = lines[lines.length - 1];
    if (last && sameSentence(last.text, value)) return lines.slice(0, -1).concat({ ...last, text: value });
    return lines.concat({ text: value, at: now, id: ++lineId }).slice(-max);
  }

  // Сколько символов влезает в две строки оверлея при этом размере шрифта и ширине.
  const maxChars = (config) => Math.max(40, Math.floor(((config.width / 100) * 1920) / (config.size * 0.52)) * 2);
  const pad = (n) => String(n).padStart(2, '0');
  const clock = (d) => `[ ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())} ]`;

  function el(doc, tag, cls, text) {
    const node = doc.createElement(tag);
    node.className = cls;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function render(container, config, lines, opts = {}) {
    const doc = opts.doc || root.document;
    container.className = 'subs';
    container.dataset.style = config.style;
    container.dataset.position = config.position;
    container.dataset.align = config.align;
    container.style.setProperty('--size', `${config.size}px`);
    container.style.setProperty('--width', `${config.width}%`);
    container.style.setProperty('--offset', `${config.offset}%`);
    if (config.font) container.style.setProperty('--font', config.font);
    if (config.nameColor) container.style.setProperty('--name-color', config.nameColor);
    if (config.accent) container.style.setProperty('--accent', config.accent);
    container.textContent = '';
    // Строки, уже бывшие на экране, перерисовываются без анимации появления — иначе блок мигал бы на каждом
    // частичном результате LocalVocal (раз в ~1 с).
    const seen = container.lsSeen || new Set();
    container.lsSeen = new Set(lines.map((line) => line.id).filter(Boolean));
    if (!lines.length) return;

    let host = container;
    if (config.style === 'eve-photon') {
      host = container.appendChild(el(doc, 'div', 'panel'));
      if (config.showName && config.name) host.appendChild(el(doc, 'div', 'head', config.name));
    }
    const limit = maxChars(config);
    for (const line of lines) {
      const text = trimTail(LS.clean(line.text, { packs: config.packs, censor: config.censor, hide: config.hide }), limit);
      if (!text) continue;
      const row = host.appendChild(el(doc, 'div', line.id && seen.has(line.id) ? 'line' : 'line new'));
      if (config.style === 'eve-local') {
        row.appendChild(el(doc, 'span', 'time', clock(line.at || opts.now || new Date())));
        row.appendChild(el(doc, 'span', 'gap', ' '));
      }
      if (config.showName && config.name && config.style !== 'eve-photon') {
        row.appendChild(el(doc, 'span', 'who', config.style === 'wow' ? `[${config.name}]` : config.name));
        row.appendChild(el(doc, 'span', 'sep', SEPARATOR[config.style] || ': '));
      }
      row.appendChild(el(doc, 'span', 'text', text));
    }
  }

  // Примеры для ?demo=1 и кнопки «Показать тест»: под первый выбранный набор.
  const SAMPLES = {
    eve: ['Tackle him, I have point, warp to the gate', 'Cyno is up, jump jump jump', 'Logi, I need reps on me!', ''],
    wow: ['Okay guys, we are going to Westfall today', 'Hogger again. Every single time, Hogger', 'Mage, do you have water? The priest is AFK again', ''],
    default: ['Hello chat, the subtitles are working', 'This is how a second sentence looks', ''],
  };
  const samplesFor = (packs) => SAMPLES[packs.find((id) => SAMPLES[id])] || SAMPLES.default;

  // Наборы — классические скрипты из ../packs/<id>.js, по очереди; ненайденный набор просто пропускается.
  function loadPacks(doc, ids) {
    return ids.reduce((chain, id) => chain.then(() => new Promise((resolve) => {
      if (LS.packs[id]) return resolve();
      const script = doc.createElement('script');
      script.src = `../packs/${encodeURIComponent(id)}.js`;
      script.onload = resolve;
      script.onerror = resolve;
      doc.head.appendChild(script);
    })), Promise.resolve());
  }

  // Лента: каждый текст из LocalVocal (частичный, итоговый или пустой) → строки на экране.
  // Через fade секунд тишины всё гаснет (0,45 с — переход opacity в styles.css), при fade=0 — когда текст очистили.
  // view.draw(lines) рисует строки, view.gone(on) включает угасание. Возвращает onText(text).
  const FADE_MS = 450;
  function createFeed(config, view) {
    let lines = [];
    let fadeTimer = null;
    let clearTimer = null;
    const fadeOut = () => {
      view.gone(true);
      clearTimer = setTimeout(() => {
        clearTimer = null;
        lines = [];
        view.draw(lines);
        view.gone(false);
      }, FADE_MS);
    };
    return function onText(text) {
      const value = String(text ?? '').replace(/\s+/g, ' ').trim();
      clearTimeout(fadeTimer);
      if (value) {
        if (clearTimer) {
          // Новая фраза посреди угасания: старые строки уже ушли, начинаем с чистого экрана.
          clearTimeout(clearTimer);
          clearTimer = null;
          lines = [];
        }
        view.gone(false);
        lines = nextLines(lines, value, config.lines, new Date());
        view.draw(lines);
      } else if (config.fade === 0) {
        if (lines.length && !clearTimer) fadeOut();
        return;
      }
      if (config.fade > 0) fadeTimer = setTimeout(fadeOut, config.fade * 1000);
    };
  }

  // События от скрипта OBS: { text } — текст LocalVocal, { test: true } — примеры набора по очереди
  // (кнопка «Показать тест»); живая речь прерывает примеры.
  const TEST_STEP_MS = 2500;
  function createHandler(config, onText) {
    let testTimer = null;
    const stopTest = () => {
      clearTimeout(testTimer);
      testTimer = null;
    };
    return function handle(detail) {
      if (!detail) return;
      if (typeof detail.text === 'string') {
        stopTest();
        onText(detail.text);
      } else if (detail.test === true) {
        stopTest();
        const samples = samplesFor(config.packs);
        let i = 0;
        const step = () => {
          onText(samples[i++]);
          testTimer = i < samples.length ? setTimeout(step, TEST_STEP_MS) : null;
        };
        step();
      }
    };
  }

  function start() {
    const doc = root.document;
    const config = parseConfig(root.location.search);
    const stage = doc.getElementById('stage');
    const container = doc.getElementById('subs');
    const onText = createFeed(config, {
      draw: (lines) => render(container, config, lines),
      gone: (on) => stage.classList.toggle('gone', on),
    });
    const handle = createHandler(config, onText);
    root.addEventListener('live-subtitles', (event) => handle(event.detail));
    loadPacks(doc, config.packs).then(() => {
      render(container, config, []);
      if (!config.demo) return;
      const samples = samplesFor(config.packs);
      let i = 0;
      const next = () => { onText(samples[i++ % samples.length]); setTimeout(next, 3500); };
      next();
    });
  }

  Object.assign(LS, { parseConfig, trimTail, sameSentence, nextLines, render, samplesFor, createFeed, createHandler, startOverlay: start });
  if (root.document && root.document.getElementById && root.document.getElementById('subs')) start();
})(typeof window !== 'undefined' ? window : globalThis);
