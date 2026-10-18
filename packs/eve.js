// Набор «EVE Online» (русская речь → английский перевод Whisper → английский пилотов EVE).
// Что Whisper выдаёт, переводя русские комсы, → как это скажет англоязычный пилот. Пары [регулярка, замена];
// регулярки без учёта регистра (флаги giu), применяются по порядку — длинные фразы раньше коротких; в замене можно
// $1, $2 (группы). Ошибки собраны прогонами 96 фраз со сленгом через LocalVocal (2026-10-18, Whisper medium q5,
// голос Windows «Irina», с подсказкой eve.prompt.txt и без): «Я в хулле» → I'm fucked, «Пробки на скане» → traffic
// jams, «Фортик» → Portico, «Делв» → business, «понерфили» → Neurophilia, «Слиперы» → Slippers, «Лешак» → fox и т.п.
// Сленг — из русских комсов EVE: такл, РЭБ, флот, корабли, структуры, рынок.
// Правило берётся, только если не портит обычный английский: «career», «crab», «float» и «traffic» сами по себе
// не трогаем — только в окружении, где это точно EVE («FAX holds the career», «traffic jams on scan»).
(function (LS) {
  // Целое слово или фраза латиницей: альтернативы внутри не вылезают за границы слов.
  const W = (word) => `\\b(?:${word})\\b`;
  // Целое слово кириллицей (\b в JS понимает только латиницу): Whisper иногда оставляет слово непереведённым.
  const R = (word) => LS.word(word);

  LS.registerPack({ id: 'eve', name: 'EVE Online', rules: [
    // ---------- такл и РЭБ ----------
    [W('under (the |a )?scram'), 'scrammed'],
    [W('ney,? you\'re drying'), 'neuts are draining'],
    [W('drying (my|the|his|her|their|your|our) cap'), 'draining $1 cap'],
    [W('dries (my|the|his|her|their|your|our) cap'), 'drains $1 cap'],
    [W('dried (my|the|his|her|their|your|our) cap'), 'drained $1 cap'],
    [W('dry (my|the|his|her|their|your|our) cap'), 'drain $1 cap'],
    [W('gr[ae]y modules'), 'heat the modules'],
    [W('everhit|overhit'), 'overheat'], // слитно: «ever hit a deer» — обычный английский
    [/\bunder (?:the |a )?(?:clock|klok|cloak)(?=$|[,.!?])/giu, 'cloaked'], // в конце фразы: «under the clock tower» не трогаем
    // ---------- флот и навигация ----------
    [W('all the little( ones)? to the station'), 'everyone align to the station'],
    [W('(sewa|seva|see you),? (in the )?(float|flot)'), 'everyone to the fleet'],
    [/^(?:float|plot)(?=[,!])/giu, 'Fleet'], // «Флот, …» в начале фразы; «Plot twist» не трогаем
    [W('(in|into|to|join) the (float|flot)'), '$1 the fleet'],
    [W('flot'), 'fleet'],
    [/,? floti\b/giu, ' in the fleet'],
    [W('warp,? negate to zero'), 'warp to the gate at zero'],
    [W('warp,? negate'), 'warp to the gate'],
    [W('negate to zero'), 'the gate at zero'],
    [W('smarts? (and |on )?na ?gate'), 'smartbombs on the gate'],
    [W('smarts(?= on| at)'), 'smartbombs'],
    [W('na ?gate'), 'on the gate'],
    [W('naverview'), 'on the overview'],
    [W('zirnitra ?na'), 'Zirnitra on'],
    [W('na ?grid[ae]?'), 'on grid'],
    [W('seeded off ?grid'), 'sitting off grid'],
    [W('dakaemsa|dokaemsya|dokaemsa'), 'dock up'],
    [W('andok[aeiu]?'), 'undock'],
    [W('go ?switch'), 'switch'],
    [W('fk'), 'FC'],
    [W('in (the )?locale'), 'in local'],
    [W('(throw|send|give) me (a |the )?convoy'), 'send me a convo'],
    [W('traffic jams? on (the )?(d-?)?scan'), 'probes on d-scan'],
    [W('d ?-?scan'), 'd-scan'],
    [W('parallel static'), 'rolling the static'],
    [W('hole in the crit'), 'the hole is crit'],
    [W('crit on the mass'), 'crit on mass'],
    // ---------- цина, капиталы, структуры ----------
    [W('i (bet|put) (on )?(a |the )?covert( price| cyno)?'), 'I\'m lighting a covert cyno'],
    [W('covert price'), 'covert cyno'],
    [W('cyna|tsina|tsyna'), 'cyno'],
    [W('(fax|faxes) (holds?|keeps?|reps?|maintains?) (the )?career'), '$1 $2 the carrier'],
    [W('fort(eek|ik|ic|ick|iq)|portico(?= is| was| got| out| in| reinforced| timer)'), 'Fortizar'],
    [W('kick holds not old'), 'HIC holds the Nestor'], // «Хик держит Нестора» — дважды одинаково
    // ---------- логи и танк ----------
    [W('(?:i\'m|i am) fucked(?=,? (pull|get|save|rep|help))'), 'I\'m in hull'],
    [W('rips on'), 'reps on'],
    [W('logists?'), 'logi'],
    [W('zar[ei]p\\p{L}*'), 'repped'],
    // ---------- PvE, вормхолы ----------
    [W('krabim ?[ao]nomalk\\p{L}*( v ?n\\p{L}*)?'), 'krabbing anomalies in nullsec'], // «Крабим аномальки в нулях» слитно
    [W('krabi'), 'krab'],
    [W('krab(im|it|bit)'), 'krabbing'],
    [W('v[ao]n[ao]malk\\p{L}*'), 'in an anomaly'],
    [W('[ao]nomalk\\p{L}*'), 'anomaly'],
    [W('(anomal\\p{L}*) (at|in) (0|zero|zeros|the zeros)'), '$1 in nullsec'],
    [W('n[ie]pis'), 'the rats'],
    [W('slippers (on|in|at) (the )?(site|grid|anomaly|anom|hole|wormhole)'), 'Sleepers $1 $2$3'],
    [W('spun (up )?the (pool|floor)'), 'spooled up'],
    // ---------- корабли ----------
    [W('machalk[aiy]'), 'Machariel'],
    [W('kiki(?= on| is on| sitting| tackl| point| warp| jump| land)'), 'Kikimora'],
    [W('mega ?tron(?= and| or|,| on grid| in local| fleet)'), 'Megathron'], // «Megatron is a Transformer» не трогаем
    [W('basilic'), 'Basilisk'],
    [W('basiliskii|basiliski'), 'Basilisks'],
    [W('golim[au]?|golema'), 'the Golem'],
    [W('sa[ck]ra'), 'Sacrilege'],
    [W('na ?sabru'), 'to the Sabre'],
    [W('sabru'), 'Sabre'],
    [W('cynotov|cinotaf|cynotaf|cenotaf|tsinotaf'), 'Cenotaph'],
    [W('s ?artai'), 'with arty'],
    // ---------- места ----------
    [W('po[t]?ch,? ?vin ?garit'), 'Pochven is burning'], // «Почвен горит» — дважды одинаково
    [W('zhit[auye]|jitu'), 'Jita'],
    [W('uedam[ae]'), 'Uedama'],
    [W('amar'), 'Amarr'],
    [W('(do)?dixie(?= or| and|,)'), 'Dodixie'],
    [W('lerens'), 'Rens'],
    [W('overtak(e|ing) the fleet'), 'moving the fleet'],
    [W('the fleet into business'), 'the fleet to Delve'],
    // ---------- союзы, CCP ----------
    [W('(enid|enita|inity) (and|&) (e?guns?|gunn?a|goons)'), 'Inits and Goons'],
    [W('fratov'), 'Frat'],
    [W('(against|vs\\.?) (the )?frats'), '$1 Frat'],
    [W('pandemics? (has |have )?(hot)?dropped'), 'Pandemic Horde hotdropped'],
    [W('pandemics? and hot ?drop'), 'Pandemic Horde hotdropped'],
    [W('(everything is )?according to neurophil\\p{L}*'), 'nerfed everything'],
    [W('neurophil\\p{L}*|p[ao]nerfil\\p{L}*'), 'nerfed'],
    [W('ccp'), 'CCP'],
    // ---------- деньги и чат ----------
    [W('(\\d+) (lyams?|lams?)'), '$1 mil'],
    [W('(loss|lost)( by| of| on)? (\\d+) l'), '$1$2 $3 mil'], // «лямов» → «L»; «2 L of water», «worth 5 L» не трогаем
    [W('gank (and |is )?(scav|kava|squad|scovat)'), 'gank squad'],
    [W('milliard ?isk\\p{L}*'), 'a billion ISK'],
    [W('ISK of the feed'), 'ISK for the fit'],
    [W('it\'s a bit(?=,? don\'t (come|go|engage|jump|warp))'), 'it\'s bait'],
    // ---------- слова, которые Whisper оставил по-русски ----------
    [R('миллиард ?иск\\p{L}*'), 'a billion ISK'],
    [R('офф[ -]?грид\\p{L}*'), 'off grid'],
    [R('сидит'), 'is sitting'],
    [R('грид\\p{L}*'), 'grid'],
    [R('гейт\\p{L}*'), 'gate'],
    [R('варп\\p{L}*'), 'warp'],
    [R('флот\\p{L}*'), 'fleet'],
    [R('локал\\p{L}*'), 'local'],
    [R('такл\\p{L}*'), 'tackle'],
    [R('поинт\\p{L}*'), 'point'],
    [R('иск(и|ов|а)?'), 'ISK'],
    [R('лям(а|ов)?'), 'mil'],
    [R('(миллиард|ярд|лярд)(а|ов)?'), 'bil'],
  ] });
})(LiveSubtitles);
