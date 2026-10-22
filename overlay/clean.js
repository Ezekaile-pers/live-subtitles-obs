// Live Subtitles — чистка перевода: наборы сленга (глоссарии исправлений) и фильтр мата.
// Классический скрипт (страница оверлея открывается по file://, ES-модули там не грузятся): в браузере кладёт
// глобальный объект LiveSubtitles, в Node отдаёт его же через module.exports — для тестов.
// Наборы (packs/*.js) и фильтр (packs/profanity.js) регистрируются в нём после загрузки.
(function (root) {
  'use strict';

  const api = root.LiveSubtitles || {};
  const packs = api.packs || {};
  const profanity = api.profanityRules || [];

  // Буква или цифра рядом: границы слов и для кириллицы (\b в JS знает только латиницу).
  const L = '[\\p{L}\\p{N}]';
  const word = (body) => new RegExp(`(?<!${L})(?:${body})(?!${L})`, 'giu');
  const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const stars = (match) => '*'.repeat(match.length);

  // Набор: { id, name, rules: [[регулярка-строка (флаги giu) или RegExp, замена]] }, правила — по порядку.
  function registerPack(pack) {
    const rules = (pack.rules || []).map(([pattern, value]) => [pattern instanceof RegExp ? pattern : new RegExp(pattern, 'giu'), value]);
    packs[pack.id] = { id: pack.id, name: pack.name || pack.id, rules };
  }

  function registerProfanity(rules) {
    profanity.push(...rules);
  }

  function maskWords(text, words) {
    const list = (words || []).map((w) => String(w).trim()).filter(Boolean);
    return list.length ? text.replace(word(list.map(escapeRe).join('|')), stars) : text;
  }

  // Мат и свои слова → звёздочки той же длины.
  function censor(text, extraWords) {
    return maskWords(profanity.reduce((out, rule) => out.replace(rule, stars), String(text ?? '')), extraWords);
  }

  // Всё вместе: наборы по порядку, потом мат (замена из набора мат не вернёт), свои слова, пробелы, заглавная буква.
  function clean(text, opts = {}) {
    const value = String(text ?? '');
    if (!value.trim()) return '';
    let out = value;
    for (const id of opts.packs || []) {
      const pack = packs[id];
      if (pack) out = pack.rules.reduce((s, [re, replacement]) => s.replace(re, replacement), out);
    }
    if (opts.censor !== false) out = profanity.reduce((s, rule) => s.replace(rule, stars), out);
    out = maskWords(out, opts.hide)
      .replace(/\s+([,.!?])/g, '$1')
      .replace(/\s{2,}/g, ' ')
      .trim();
    return out.charAt(0).toUpperCase() + out.slice(1);
  }

  Object.assign(api, { version: '1.2.1', packs, profanityRules: profanity, word, registerPack, registerProfanity, censor, clean });
  root.LiveSubtitles = api;
  if (typeof module === 'object' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
