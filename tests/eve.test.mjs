import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { load, root } from './load.mjs';

const LS = load('profanity', 'eve');

// Сырые переводы Whisper из прогонов 96 фраз со сленгом EVE через LocalVocal (голос Windows «Irina», Whisper medium q5,
// 2026-10-18; с подсказкой eve.prompt.txt и без) → что видит зритель. Слева — то, что Whisper реально выдал.
const WHISPER = [
  // такл и РЭБ
  ['He is under the scram, beat him', 'He is scrammed, beat him'],
  ['He is under scram, beat him', 'He is scrammed, beat him'],
  ['Ney, you\'re drying my cap', 'Neuts are draining my cap'],
  ['Gray Modules, key and overheat', 'Heat the modules, key and overheat'],
  ['Warm up the modules, turn on the EVERHIT', 'Warm up the modules, turn on the overheat'],
  ['Tengu under the clock', 'Tengu cloaked'],
  ['Basilisk, Zaripa, Tengu under clock', 'Basilisk, repped, Tengu cloaked'],
  // флот и навигация
  ['All the little ones to the station', 'Everyone align to the station'],
  ['All the little to the station', 'Everyone align to the station'],
  ['Float, warp, negate to zero', 'Fleet, warp to the gate at zero'],
  ['plot, warp, negate to zero', 'Fleet, warp to the gate at zero'],
  ['Float! Warp to gate zero!', 'Fleet! Warp to gate zero!'],
  ['See you in the flot', 'Everyone to the fleet'],
  ['undock, sewa, float', 'Undock, everyone to the fleet'],
  ['Cenotaph, Floti', 'Cenotaph in the fleet'],
  ['Cynotov, Floti', 'Cenotaph in the fleet'],
  ['Smart and Nagate', 'Smartbombs on the gate'],
  ['Naverview, nothing', 'On the overview, nothing'],
  ['Zirnitrana grid', 'Zirnitra on grid'],
  ['Booster seeded off grid', 'Booster sitting off grid'],
  ['Booster сидит офф грид', 'Booster is sitting off grid'],
  ['Dakaemsa, on the Andoki camp', 'Dock up, on the undock camp'],
  ['dock, on the Andoki camp', 'Dock, on the undock camp'],
  ['Goswitch, broadcast and sacra', 'Switch, broadcast and Sacrilege'],
  ['FK, who are you shooting at?', 'FC, who are you shooting at?'],
  ['In locale 40 neutrals', 'In local 40 neutrals'],
  ['In the locale 40 neutrals', 'In local 40 neutrals'],
  ['Throw me a convoy', 'Send me a convo'],
  ['Give me the convoy', 'Send me a convo'],
  ['The traffic jams on the scan will scan us', 'The probes on d-scan will scan us'],
  ['Parallel static', 'Rolling the static'],
  ['hole in the crit on the mass', 'The hole is crit on mass'],
  // цина, капиталы, структуры
  ['CYNA is lit. Let\'s jump', 'Cyno is lit. Let\'s jump'],
  ['CYNA is lit, let\'s jump', 'Cyno is lit, let\'s jump'],
  ['I put the covert price', 'I\'m lighting a covert cyno'],
  ['I bet on a covert', 'I\'m lighting a covert cyno'],
  ['FAX holds the career', 'FAX holds the carrier'],
  ['Fax holds the career', 'Fax holds the carrier'],
  ['Forteek is out of the timer', 'Fortizar is out of the timer'],
  ['Portico is out of the timer', 'Fortizar is out of the timer'],
  // логи и танк: «Я в хулле» Whisper слышит как мат — без правила зритель увидел бы звёздочки
  ['I\'m fucked, pull me out', 'I\'m in hull, pull me out'],
  ['I\'m fucked, get me out', 'I\'m in hull, get me out'],
  ['Shield falls, rips on Drake', 'Shield falls, reps on Drake'],
  ['I need rips on me', 'I need reps on me'],
  ['Shield falls, reps on Drake Logists, hold the armor', 'Shield falls, reps on Drake logi, hold the armor'],
  ['Logists, hold the armor!', 'Logi, hold the armor!'],
  // PvE и вормхолы
  ['Local is clear, you can krabi', 'Local is clear, you can krab'],
  ['Krabim anomalies at 0', 'Krabbing anomalies in nullsec'],
  ['rattlesnake, krabit, anomaly', 'Rattlesnake, krabbing, anomaly'],
  ['Nipis beats the drone', 'The rats beats the drone'],
  ['Slippers on the site', 'Sleepers on the site'],
  ['Leshak has spun the pool', 'Leshak has spooled up'],
  ['The fox has spun the floor, go away!', 'The fox has spooled up, go away!'],
  // корабли
  ['Machalka with officer fit', 'Machariel with officer fit'],
  ['Machalka with officer fit Vargur and 2.5', 'Machariel with officer fit Vargur and 2.5'],
  ['Kiki on top, she is very fast', 'Kikimora on top, she is very fast'],
  ['MegaTron and Hyperion', 'Megathron and Hyperion'],
  ['Basilic, they were raking golem', 'Basilisk, they were raking golem'],
  ['primary, logi, switch, nasabru', 'Primary, logi, switch, to the Sabre'],
  ['Hurricane Sartai', 'Hurricane with arty'],
  // места
  ['Amar, Dixie and Lerens', 'Amarr, Dodixie and Rens'],
  ['We are overtaking the fleet into business', 'We are moving the fleet to Delve'],
  // союзы и CCP
  ['Enid and Egun are against frats', 'Inits and Goons are against Frat'],
  ['Enita and Gunna vs. Fratov', 'Inits and Goons vs. Frat'],
  ['Pandemic has dropped them', 'Pandemic Horde hotdropped them'],
  ['CCP again, everything is according to Neurophilia', 'CCP again, nerfed everything'],
  // деньги и чат
  ['Loss by 200 L', 'Loss by 200 mil'],
  ['gank is kava at the gate', 'Gank squad at the gate'],
  ['gank and scav at the gate', 'Gank squad at the gate'],
  ['It\'s a bit, don\'t come in', 'It\'s bait, don\'t come in'],
  ['FIT is shit, redo it', 'FIT is ****, redo it'],
  // прогон с итоговой подсказкой (eve.prompt.txt)
  ['Fortiq got out of the timer', 'Fortizar got out of the timer'],
  ['FAX maintains career', 'FAX maintains the carrier'],
  ['Kick holds not old', 'HIC holds the Nestor'],
  ['krabimonomalki vn', 'Krabbing anomalies in nullsec'],
  ['krabimonomalkevna', 'Krabbing anomalies in nullsec'],
  ['Basiliskii zarepali Golima', 'Basilisks repped the Golem'],
  ['Rattlesnake, Krabbit, Vanamalki', 'Rattlesnake, krabbing, in an anomaly'],
  ['Poch, vingarit', 'Pochven is burning'],
  ['POTCH, vingarit', 'Pochven is burning'],
  ['Milliardisk of the feed', 'A billion ISK for the fit'],
  ['gank and scovat on the gate', 'Gank squad on the gate'],
  ['ccp again, all panerfili', 'CCP again, all nerfed'],
  ['Pandemic and hotdrop', 'Pandemic Horde hotdropped'],
  ['Smart and Nagate, don\'t lie to me', 'Smartbombs on the gate, don\'t lie to me'],
  // слова, оставленные по-русски
  ['миллиардиска вза', 'A billion ISK вза'],
  ['Warp на гейт, флот', 'Warp на gate, fleet'],
];

test('набор eve и цензура на настоящих переводах Whisper', () => {
  for (const [raw, expected] of WHISPER) assert.equal(LS.clean(raw, { packs: ['eve'] }), expected, raw);
});

test('набор eve не портит обычный английский', () => {
  for (const text of [
    'Warp to zero',
    'The gate is clear',
    'Point',
    'Hold the line',
    'Good fight everyone, o7',
    'Thank you for the follow',
    'We need more DPS',
    'My career in EVE started in 2010',
    'The traffic was terrible today',
    'I bought new slippers',
    'The boat will float',
    'This will negate the bonus',
    'Business is going well',
    'Kiki is my cat',
    'I had crab for dinner',
    'My locale is Russian',
    'The convoy left at noon',
    'It\'s a bit cold today',
    'Plot twist!',
    'The pandemic changed everything',
    'Frats are loud',
    'Dixie is a nice name',
    'A fox in the forest',
    'Under the bridge',
    'I put the cup on the table',
    'I bet you can do it',
    'I need 2 L of water',
    'Megatron is a Transformer',
    'He is a good pilot',
    'Have you ever hit a deer?',
    'Did you ever hit level 50?',
    'Under the clock tower',
    'It is worth 5 L',
  ]) {
    assert.equal(LS.clean(text, { packs: ['eve'] }), text, text);
  }
});

test('набор eve: подсказка Whisper — список слов, сленг в конце, в пределах того, что Whisper видит', () => {
  const prompt = fs.readFileSync(path.join(root, 'packs', 'eve.prompt.txt'), 'utf8').trim();
  assert.match(prompt, /^CCP, CONCORD/);
  assert.match(prompt, /dictor, HIC, bubble, web, scram, point, tackle, gf, o7, fly safe\.$/);
  assert.ok(prompt.length < 950, `Whisper берёт последние ~224 токена: ${prompt.length} знаков`);
});
