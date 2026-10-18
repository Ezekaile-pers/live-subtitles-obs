// Фильтр мата для субтитров: слово целиком → звёздочки той же длины (включается настройкой «Фильтр мата»).
// Английский — как его выдаёт перевод Whisper; транслит и русские корни — если Whisper оставил слово без перевода;
// оскорбления — тоже: Whisper иногда слышит их вместо сленга («это имба» → «This is a f…»).
// Правила только для целых слов: «cocktail», «Scunthorpe», «хлебать» не задеваются (см. tests/clean.test.mjs).
(function (LS) {
  const word = LS.word;
  LS.registerProfanity([
    // английский
    word('\\p{L}*f+u+c+k+\\p{L}*'),
    word('\\p{L}*shit\\p{L}*'),
    word('bitch(?:es|y|ing)?|sonofabitch'),
    word('cunts?'),
    word('dick(?:s|head|heads)?'),
    word('cocks?(?:sucker\\p{L}*)?'),
    word('puss(?:y|ies)'),
    word('whores?|sluts?'),
    word('(?:ass|arse)holes?'),
    word('bastards?'),
    word('fag(?:got)?s?|retard(?:ed|s)?|nigg(?:a|er)s?'),
    // транслит русского мата
    word('bl[iy]a(?:t|d)\\p{L}*|blya|cyka|suk[ai]'),
    word('(?:na ?)?h[uo][iy]|pizd\\p{L}*|y?ob(?:any|anniy)|y?ebat\\p{L}*|mudak\\p{L}*'),
    word('(?:o|ni|na|po|do)h[uo](?:e|ye|ya|y|i)\\p{L}*|zaeb\\p{L}*|y?eblan\\p{L}*|dolbo(?:y?e)?ob\\p{L}*|dolboeb\\p{L}*'),
    word('pid[ao]r\\p{L}*|pidr\\p{L}*|gandon\\p{L}*|shl[iy]?uh\\p{L}*|mudil\\p{L}*|zalup\\p{L}*|such(?:ka|ki|ku|ara)\\p{L}*'),
    // русский мат — без перевода (субтитры по-русски) или когда Whisper оставил слово как есть.
    // Корень ху- — с приставками (охуеть, нихуя, схуяли); ёб/еб в начале слова — всегда мат («небо», «хлебать»,
    // «съесть», «подъезд» не задеваются: там до «е/ё» нет приставки из списка или после неё не «б»).
    word('бля[дт]?ь?|сук[аи]|(?:с|рас|вы|за|у|на|от|под)?пизд\\p{L}*|(?:на|по|от|за|о|ни|с|до|пере|под|рас)?ху[йеёяи]\\p{L}*'),
    word('(?:за|вы|до|у|при|по|на|от|раз|разъ|съ|подъ|объ|долбо)?[её]б\\p{L}*|муда[кч]\\p{L}*|мудил\\p{L}*|мудо\\p{L}*'),
    word('пид[оа]р\\p{L}*|пидр\\p{L}*|суч(?:к|ар)\\p{L}*|шлюх\\p{L}*|гандон\\p{L}*|залуп\\p{L}*'),
  ]);
})(LiveSubtitles);
