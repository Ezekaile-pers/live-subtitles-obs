// Набор «World of Warcraft» (русская речь → английский перевод Whisper → игровой английский).
// Что Whisper выдаёт, переводя русскую речь, → как это скажет англоязычный игрок WoW. Пары [регулярка, замена];
// регулярки без учёта регистра (флаги giu), применяются по порядку — длинные фразы раньше коротких; в замене можно
// $1, $2 (группы). Ошибки собраны прогонами 88 фраз со сленгом через LocalVocal (2026-10-17): «Мёртвые копи» →
// dead copy, «Орда» → Orda, «нид или грид» → Nate or Grid, «Огненные Недра» → Fiery Nests, «Хант,» → Cunt, и т.п.
// Правило берётся, только если не портит обычный английский: «horns» (рога) не трогаем — это и правда может быть рог.
(function (LS) {
  // Целое слово или фраза: альтернативы внутри не вылезают за границы слов.
  const W = (word) => `\\b(?:${word})\\b`;

  LS.registerPack({ id: 'wow', name: 'World of Warcraft', rules: [
    // ---------- города и зоны (русские названия клиента, переведённые дословно) ----------
    [W('(the )?west(ern)? (edge|end|region|land|lands|territory)'), 'Westfall'],
    [W('(the )?(twilight|dusk|dusky|sumer(ian|ech\\p{L}*)) (forest|woods?)'), 'Duskwood'],
    [W('(the )?elvin(sky|n)? forest'), 'Elwynn Forest'],
    [W('elvin'), 'Elwynn'],
    [W('(the )?(zlatozem\\p{L}*|golden ?(land|earth|lands))'), 'Goldshire'],
    [W('(krasnogor\\p{L}*|(the )?red mountains?)'), 'Redridge'],
    [W('(the )?(thorny|ternist\\p{L}*|thorn) valley'), 'Stranglethorn Vale'],
    [W('ternist\\p{L}*'), 'Stranglethorn'],
    [W('lok[- ]?modan'), 'Loch Modan'],
    [W('(the )?dark ?shores?'), 'Darkshore'],
    [W('(the )?ash(en)? forest'), 'Ashenvale'],
    [W('(the )?(barrens|steppes)(?<!burning steppes)'), 'the Barrens'],
    [W('(the )?inner lands'), 'the Hinterlands'],
    [W('(the )?dust(y)? (swamps?|marsh(es)?)'), 'Dustwallow Marsh'],
    [W('(the )?stone ?claw( mountains)?'), 'Stonetalon Mountains'],
    [W('(the )?(desecrated|defiled|tainted) forest'), 'Felwood'],
    [W('winter ?springs'), 'Winterspring'],
    [W('(the )?(smoldering|smouldering|glowing) gorge'), 'Searing Gorge'],
    [W('(the )?(scorched|burnt|burned) lands'), 'the Blasted Lands'],
    [W('(the )?dead ?wind pass'), 'Deadwind Pass'],
    [W('(storm|sturm|shtorm) ?(wind|grad|city)'), 'Stormwind'],
    [W('st[ae]l+[ -]?g?or\\p{L}*|steel ?(horn|mountain|city)'), 'Ironforge'],
    [W('under ?city|podgorod'), 'Undercity'],
    [W('thunder (cliff|rock)'), 'Thunder Bluff'],
    [W('orgrim+ar'), 'Orgrimmar'],

    // ---------- подземелья и рейды ----------
    [W('(the )?(fiery|fire|flaming) abyss'), 'Ragefire Chasm'],
    [W('(the )?caves? of (wailing|lament(ation)?|moaning|groans?)'), 'Wailing Caverns'],
    [W('(the )?dead ?(cop(y|ies)|kopi|mines?)'), 'Deadmines'],
    [W('(a|the) Deadmines'), 'Deadmines'],
    [W('go ?v,? ?dm'), 'go to DM'],
    [W('(the )?(dark|shadow) ?fang (fortress|keep|castle)'), 'Shadowfang Keep'],
    [W('(the )?(impenetrable|pitch[- ]black) (abyss|depths)'), 'Blackfathom Deeps'],
    [W('(the )?(monastery of the scarlet order|scarlet monastery|monastery)'), 'Scarlet Monastery'],
    [W('(the )?depths of (the )?black mountains?'), 'Blackrock Depths'],
    [W('(the )?(peak|spire|top) of (the )?black mountains?|black mountain (peak|spire)'), 'Blackrock Spire'],
    [W('(the )?black mountains?'), 'Blackrock Mountain'],
    [W('(the )?forgotten city'), 'Dire Maul'],
    [W('necrosit\\p{L}*|shola|skolo'), 'Scholo'],
    [W('straat'), 'Strat'],
    [W('(the )?(fiery|fire|flaming) (nests?|depths|bowels|core|guts|entrails|innards|nidra|nedra|nedr\\p{L}*)'), 'Molten Core'],
    [W('(the )?(lair of (the )?dark ?wing|dark ?wing lair)'), 'Blackwing Lair'],

    // ---------- персонажи ----------
    [W('hoe?g+h?e?r'), 'Hogger'],
    [W('van ?cl(ee?f+|iff?)'), 'VanCleef'],
    [W('(lyra|leroy|lira|lee?roy|lir[oa]y) (and )?jenkins'), 'Leeroy Jenkins'],
    [W('(no)?m[ae]n ?kri(e)?[gk]'), 'Mankrik'],

    // ---------- классы и роли ----------
    [W('retr[iy]c?k'), 'Ret paladin'],
    [W('palych'), 'paladin'],
    [W('k?holi[ck]'), 'holy'],
    [W('ma[cg]'), 'Mage'],
    [W('namaga'), 'on the mage'],
    [W('vars?'), 'warrior'],
    [W('war on (the )?tank'), 'warrior to tank'],
    [W('dd'), 'DPS'],
    [W('dru+l'), 'Druid'],
    [W('sham'), 'shaman'],
    [W('lok'), 'lock'],
    // В начале фразы и перед запятой — обращение: «Лок, …», «Хант, …» (Whisper слышит Log, Hunt и даже Cunt).
    ['^lo[gk](?=,)', 'Lock'],
    ['^(hunt|c[ua]nt)(?=,)', 'Hunter'],
    [W('peta'), 'pet'],
    [W('(a )?stone of (the )?souls?'), 'a soulstone'],
    [W('soul ?stone'), 'soulstone'],

    // ---------- бой и группа ----------
    [W('add(is|ies|y)( (is|are) (running|coming))?|adds run(ning)?'), 'adds incoming'],
    [W('broke (the )?aggro'), 'pulled aggro'],
    [W('(everyone|all) (was |were )?(lying|lay|laid)( down)?'), 'everyone died'],
    [W('(running|run|go|going|ran) (to|for|after) (the|my) body'), '$1 back to my corpse'],
    [W('cemetery'), 'graveyard'],
    [W('on the graveyard'), 'at the graveyard'],
    [W('resnus'), 'I\'ll res'],
    [W('you[\'’]?ll wake me up'), 'can you res me'],
    [W('buff,? not me'), 'buff me'],
    [W('king (a |the )?buff'), 'give me the buff'],
    [W('the dispel debuff|ze ?dispel,? (the )?debuff'), 'dispel the debuff'],
    [W('(knock down|shoot down|kill|beat|break) the (cast|cusp|caste|kast)'), 'interrupt the cast'],
    [W('proc(ane|anul\\p{L}*|ked)'), 'procced'],
    [W('nak+ad+a|on (the )?kd'), 'on CD'],
    [W('on (the )?(rollback|recharge|reload)'), 'on cooldown'],
    [W('bubble and (a |the )?stone'), 'bubble hearth'],
    [W('(the )?stone (is )?(from|on) (katya|katia|kate|(the )?(rollback|recharge|cooldown|retina))'), 'hearthstone on cooldown'],
    [W('(return|home) stone'), 'hearthstone'],
    [W('gr[iy]ff?[io]n(s?)'), 'gryphon$1'],
    [W('(lich|leech) on (the |a )?gryphon'), 'flying on a gryphon'],
    [W('(drank|drink|drinking) (a |the )?(jar|can|bank)'), '$1 a potion'],
    [W('resp'), 'respawn'],
    [W('inst'), 'instance'],
    [W('dan[jz]h?'), 'dungeon'],

    // ---------- лут ----------
    [W('(nate|need|neat|nid|kneed),? or (grid|greed|greet|green)'), 'need or greed'],
    [W('(falling|fell|dropped|upp?al( and| an?)?) (an? )?(peak|epic)'), 'an epic dropped'],
    [W('(sink|tink)\\p{L}*( from)? (the )?boss(es)?'), 'a blue from the boss'],
    [W('a beast for'), 'BiS for'],
    [W('(at|on|in) (the )?auction(?! house)'), 'on the auction house'],
    [W('(our |my |the )?clothes'), '$1gear'],
    [W('two handles?'), 'two-hander'],

    // ---------- прокачка ----------
    [W('(i[\'’]m|i am|we[\'’]re|we are) (swinging|rocking|pumping|swaying)'), '$1 leveling'],
    [W('apn[- ]?0*(\\d+)'), 'dinged $1'],
    [W('upp?ed (the )?(\\d+)(th|st|nd|rd)?'), 'dinged $2'],
    [W('expa'), 'XP'],
    [W('(the )?arrest (is over|ended|ran out)'), 'rested XP ran out'],

    // ---------- чат и мемы ----------
    [W('orda'), 'Horde'],
    [W('nierf\\p{L}*|nerfanul\\p{L}*'), 'nerfed'],
    [W('lagi'), 'lag'],
    [W('disco knocked me (down|out)'), 'I got disconnected'],
    [W('blizzards'), 'Blizzard'],
  ] });
})(LiveSubtitles);
