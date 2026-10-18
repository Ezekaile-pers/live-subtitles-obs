import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { load, root } from './load.mjs';

const LS = load('profanity', 'wow');

// Сырые переводы Whisper из прогона 88 фраз со сленгом через LocalVocal (голос Windows «Irina», 2026-10-17) →
// что видит зритель. Слева — то, что Whisper реально выдал, справа — после глоссария и цензуры.
const WHISPER = [
  // места
  ['Looking for a healer in a dead copy', 'Looking for a healer in Deadmines'],
  ['Looking for healers in dead copies', 'Looking for healers in Deadmines'],
  ['Gov, DM', 'Go to DM'],
  ['GovDM', 'Go to DM'],
  ['Swim in the western edge', 'Swim in Westfall'],
  ['Two-taker in the golden land', 'Two-taker in Goldshire'],
  ['Go to Krasnogor', 'Go to Redridge'],
  ['We go to Krasnogorje', 'We go to Redridge'],
  ['Let\'s fly to Stalgorod', 'Let\'s fly to Ironforge'],
  ['Let\'s fly to Stalgorna', 'Let\'s fly to Ironforge'],
  ['In the Sumerian forest it\'s scary', 'In Duskwood it\'s scary'],
  ['Fiery Nests on Saturday', 'Molten Core on Saturday'],
  ['Fiery nidra on Saturday', 'Molten Core on Saturday'],
  ['The depths of the Black Mountain', 'Blackrock Depths'],
  ['Shola and strat', 'Scholo and strat'],
  ['Gank the Ternist', 'Gank the Stranglethorn'],
  ['Orda is camping again', 'Horde is camping again'],
  // персонажи
  ['Hoegger killed again', 'Hogger killed again'],
  ['Lyra and Jenkins', 'Leeroy Jenkins'],
  ['Leroy Jenkins', 'Leeroy Jenkins'],
  ['Where is Nomenkrieg?', 'Where is Mankrik?'],
  // классы
  ['Retrik hits like a truck', 'Ret paladin hits like a truck'],
  ['Holic doesn\'t have time', 'Holy doesn\'t have time'],
  ['Mag, give me some water', 'Mage, give me some water'],
  ['Druul, we do not meet in Stormwind', 'Druid, we do not meet in Stormwind'],
  ['Log, give me a stone of soul', 'Lock, give me a soulstone'],
  ['Cunt, take the pet away', 'Hunter, take the pet away'],
  ['Get Peta out', 'Get pet out'],
  ['Holic does not have time, need war on tank', 'Holy does not have time, need warrior to tank'],
  // бой
  ['The mage broke the aggro', 'The mage pulled aggro'],
  ['Addis is running', 'Adds incoming'],
  ['Adds run', 'Adds incoming'],
  ['Everyone was lying', 'Everyone died'],
  ['All laid', 'Everyone died'],
  ['Resnus on the cemetery', 'I\'ll res at the graveyard'],
  ['I\'ll take a nap in the cemetery', 'I\'ll take a nap in the graveyard'],
  ['Running after the body', 'Running back to my corpse'],
  ['You\'ll wake me up', 'Can you res me'],
  ['Buff not me', 'Buff me'],
  ['Buff, not me', 'Buff me'],
  ['The Dispel debuff', 'Dispel the debuff'],
  ['Kill the cusp', 'Interrupt the cast'],
  ['Procane sword', 'Procced sword'],
  ['Bubble Nakkada', 'Bubble on CD'],
  ['Bubble and Stone', 'Bubble hearth'],
  ['Stone from Katya', 'Hearthstone on cooldown'],
  ['Stone on the retina', 'Hearthstone on cooldown'],
  ['Lich on the griffon', 'Flying on a gryphon'],
  ['Leech on the gryphon', 'Flying on a gryphon'],
  // лут
  ['Nate or Grid', 'Need or greed'],
  ['Need, or greed', 'Need or greed'],
  ['Falling peak', 'An epic dropped'],
  ['Uppal and peak', 'An epic dropped'],
  ['Sinkas Bosses', 'A blue from the boss'],
  ['It\'s a beast for Paladin', 'It\'s BiS for Paladin'],
  ['I\'ll sell it at the auction', 'I\'ll sell it on the auction house'],
  ['Sell at auction', 'Sell on the auction house'],
  ['We need to repair our clothes', 'We need to repair our gear'],
  ['Two handles from VanCleef', 'Two-hander from VanCleef'],
  // прокачка и чат
  ['APN-020', 'Dinged 20'],
  ['Arrest is over', 'Rested XP ran out'],
  ['Nierf again', 'Nerfed again'],
  ['Lagi, ping 200', 'Lag, ping 200'],
  ['Disco knocked me down', 'I got disconnected'],
  // мат и то, что Whisper слышит вместо сленга
  ['Blyat, wipe again', '*****, wipe again'],
  ['Bitch, Hogger again', '*****, Hogger again'],
  ['What the fuck is this dungeon?', 'What the **** is this dungeon?'],
  ['This is a faggot', 'This is a ******'],
  // третий прогон (подсказка фразами)
  ['See you in Sturmgrad!', 'See you in Stormwind!'],
  ['Let\'s fly to Stalgoron', 'Let\'s fly to Ironforge'],
  ['Going to Krasnogorje', 'Going to Redridge'],
  ['The depths of the Black Mountains', 'Blackrock Depths'],
  ['Forming Monastery. Scholo and Straat', 'Forming Scarlet Monastery. Scholo and Strat'],
  ['Kholik does not have time', 'Holy does not have time'],
  ['Need a war on tank', 'Need a warrior to tank'],
  ['Zedispel, debuff', 'Dispel the debuff'],
  ['Stone on Katia', 'Hearthstone on cooldown'],
  ['Uppal epic', 'An epic dropped'],
  ['Two handles from VanCliff', 'Two-hander from VanCleef'],
  ['Cunt, get Peta away', 'Hunter, get pet away'],
  ['Log, give me the soulstone', 'Lock, give me the soulstone'],
  ['Quest-giver to the Golden Land', 'Quest-giver to Goldshire'],
  ['Gank on the Ternist', 'Gank on the Stranglethorn'],
  ['Cyka, again Hogger', '****, again Hogger'],
  // уже правильно — не трогаем
  ['I heal, you damage', 'I heal, you damage'],
  ['Kite him', 'Kite him'],
  ['Rogue, stealth', 'Rogue, stealth'],
  ['This is BiS for Paladin', 'This is BiS for Paladin'],
  ['GG, thank you all!', 'GG, thank you all!'],
  ['This is imba', 'This is imba'],
  ['Scholo and Strat', 'Scholo and Strat'],
];

test('набор wow и цензура на настоящих переводах Whisper', () => {
  for (const [raw, expected] of WHISPER) assert.equal(LS.clean(raw, { packs: ['wow'] }), expected, raw);
});

test('набор wow не портит обычный английский', () => {
  for (const text of [
    'Today we go to Westfall, we will kill Hogger again',
    'The Burning Steppes are far away',
    'We are going to the Deadmines',
    'I need a tank and a healer',
    'Magic and a magazine',
    'Dota is a different game',
    'A dark forest and red roses',
    'Tom, are you here?',
    'The hunter is hunting, he hunts',
    'He is a varsity player in a dead end job',
    'Thank you for the follow',
  ]) {
    const out = LS.clean(text, { packs: ['wow'] });
    assert.equal(out, text.replace('the Deadmines', 'Deadmines'), text);
  }
});

test('набор wow: подсказка Whisper — список слов, самое частое в конце', () => {
  const prompt = fs.readFileSync(path.join(root, 'packs', 'wow.prompt.txt'), 'utf8').trim();
  assert.match(prompt, /^Mankrik, VanCleef, Leeroy Jenkins/);
  assert.match(prompt, /Tank, tanking, healer, healing, DPS, damage, pull, aggro, adds, patrol, wipe\.$/);
  assert.ok(prompt.length < 800, 'Whisper берёт последние ~224 токена');
});
