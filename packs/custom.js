// Свой набор: исправления перевода под свою игру, имена друзей, мемы канала.
// Как пользоваться: впиши правила ниже, сохрани файл, в OBS в настройках скрипта Live Subtitles отметь набор
// «custom» и обнови оверлей (правый клик по источнику → «Обновить»).
// Правило — пара [что выдаёт Whisper (регулярка, без учёта регистра), как надо]. Применяются по порядку.
// Подсмотреть, что выдаёт Whisper: «Логи» скрипта (Инструменты → Скрипты → Логи скрипта) или сам оверлей.
//
// Your own pack: fixes for your game, friends' names, channel memes. Tick "custom" in the Live Subtitles script settings
// and refresh the overlay. A rule is a pair [what Whisper outputs (case-insensitive regex), what it should be].
(function (LS) {
  const W = (word) => `\\b(?:${word})\\b`; // целое слово или фраза / whole word or phrase

  LS.registerPack({ id: 'custom', name: 'Custom', rules: [
    // [W('vasyan'), 'Vasyan'],            // ник друга, который Whisper пишет с маленькой / a friend's nick
    // [W('the (big|great) boss'), 'Boss'], // дословный перевод → как говорят в игре / literal translation → game term
  ] });
})(LiveSubtitles);
