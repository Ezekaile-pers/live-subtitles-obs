import test from 'node:test';
import assert from 'node:assert/strict';
import { load } from './load.mjs';

const LS = load('profanity');

test('мат → звёздочки той же длины: английский перевод, транслит, русские слова', () => {
  assert.equal(LS.censor('Oh, fuck'), 'Oh, ****');
  assert.equal(LS.censor('Fuck! What the fucking hell'), '****! What the ******* hell');
  assert.equal(LS.censor('motherfucker, bullshit, shitty'), '************, ********, ******');
  assert.equal(LS.censor('son of a bitch, you asshole'), 'son of a *****, you *******');
  assert.equal(LS.censor('Blyat, suka, pizdec'), '*****, ****, ******');
  assert.equal(LS.censor('Нахуй этот данж, блять, пиздец, заебал'), '***** этот данж, *****, ******, ******');
  assert.equal(LS.censor('FUCK'), '****', 'регистр не важен');
  assert.equal(LS.censor('This is a faggot'), 'This is a ******', 'оскорбления тоже');
});

test('мат: русские формы и транслит — без перевода (субтитры по-русски) и когда Whisper оставил слово как есть', () => {
  for (const w of [
    'охуеть', 'охуенно', 'нихуя', 'схуяли', 'дохуя', 'заебись', 'ебу', 'ебёт', 'уёбок', 'долбоёб', 'разъебал', 'съебался',
    'пидор', 'пидорас', 'пидарас', 'сучка', 'сучара', 'шлюха', 'мудила', 'гандон', 'залупа',
    'pidor', 'pidoras', 'ohuet', 'nihuya', 'nahuy', 'zaebis', 'eblan', 'gandon', 'dolboeb', 'shluha', 'mudila', 'zalupa',
  ]) {
    assert.equal(LS.censor(w), '*'.repeat(w.length), w);
  }
});

test('мат: обычные слова не трогаем', () => {
  for (const text of [
    'Damn, it\'s cool', 'What the hell', 'Dickens and a cocktail', 'class assassin passage',
    'Scunthorpe', 'Hancock', 'pizza', 'хуже некуда, похудел', 'колебаться, хлебать, небо', 'бляха-муха', 'сукин сын',
    'сучок, мудрый, пиджак', 'убежать, объезд, съесть, подъезд, небоскрёб', 'Ohio, shoe, hue, such a day, Doha',
  ]) {
    assert.equal(LS.censor(text), text, text);
  }
});

test('свои слова под звёздочки: целые слова, без учёта регистра, кириллица тоже', () => {
  assert.equal(LS.censor('Tom is here, tom', ['Tom']), '*** is here, ***');
  assert.equal(LS.censor('Tomato Tom', ['Tom']), 'Tomato ***', 'кусок слова не трогаем');
  assert.equal(LS.censor('привет Вася', ['вася']), 'привет ****');
  assert.equal(LS.censor('a+b (c)', ['a+b', '(c)']), '*** ***', 'спецсимволы в словах не ломают поиск');
});

test('clean: пустое остаётся пустым, лишние пробелы убираются, первая буква заглавная', () => {
  assert.equal(LS.clean(''), '');
  assert.equal(LS.clean('   '), '');
  assert.equal(LS.clean(null), '');
  assert.equal(LS.clean(' go to DM ,  now'), 'Go to DM, now');
  assert.equal(LS.clean('fuck, wipe again'), '****, wipe again', 'звёздочки в начале — без заглавной');
});

test('clean: цензура выключается, свои слова работают и без неё', () => {
  assert.equal(LS.clean('oh fuck', { censor: false }), 'Oh fuck');
  assert.equal(LS.clean('Tom is here', { hide: ['Tom'] }), '*** is here');
  assert.equal(LS.clean('Tom fuck', { censor: false, hide: ['Tom'] }), '*** fuck');
});

test('наборы: правила по порядку, только выбранные, неизвестный набор не ломает', () => {
  LS.registerPack({ id: 't1', name: 'T1', rules: [['\\bfoo\\b', 'bar'], [/bar baz/giu, 'qux']] });
  LS.registerPack({ id: 't2', name: 'T2', rules: [['\\bqux\\b', 'QUUX']] });
  assert.equal(LS.clean('foo baz', { packs: ['t1'] }), 'Qux', 'правила набора применяются по порядку');
  assert.equal(LS.clean('foo baz', { packs: ['t1', 't2'] }), 'QUUX');
  assert.equal(LS.clean('foo baz', { packs: [] }), 'Foo baz');
  assert.equal(LS.clean('foo baz', { packs: ['nope', 't1'] }), 'Qux');
  assert.ok(LS.packs.t1 && LS.packs.t1.name === 'T1');
});

test('word(): границы слов и для латиницы, и для кириллицы', () => {
  assert.equal('Tom tomtom'.replace(LS.word('tom'), '*'), '* tomtom');
  assert.equal('Вася Васясь'.replace(LS.word('вася'), '*'), '* Васясь');
});
