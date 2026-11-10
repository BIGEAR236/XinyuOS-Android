/// Strips roleplay/formatting that should never be SPOKEN aloud before the
/// text goes to TTS. Story-mode replies keep ONLY quoted dialogue (the
/// character's spoken words); narration and actions stay silent. When no
/// quotes are present the plain cleanup applies.
library;

/// Paired quotes: “” ‘’ «» "" '' plus CJK 「」『』. Group 1 holds the content.
final _dialogueQuote = RegExp(
    '[“"\']([^“”"\'』」]{1,150})[”"\']|「([^」]{1,150})」|『([^』]{1,150})』');

final _noiseTokens = RegExp(r'\[虚拟(?:红包|礼物)[^\]]*\]');
/// Story contracts often label lines: drop the label; keep only SPOKEN lines
/// (对白/台词/说). Non-spoken labels (动作/旁白/内心/场景/时间/思考) kill
/// the whole line so the narration never reaches TTS.
final _spokenLineLabel = RegExp(r'(?m)^[ \t]*对白[ \t]*[:：][ \t]*(.+)$');
final _speechLineLabel = RegExp(r'(?m)^[ \t]*台词[ \t]*[:：][ \t]*(.+)$');
final _silentLineLabels = RegExp(
    r'(?m)^[ \t]*(动作|旁白|内心|心理|场景|环境|时间|思考|神态|表情|描写|叙述|系统)[ \t]*[:：][^\n]*$');
/// Inline "标签：内容" prefixes on a single mixed line.
final _inlineSilentLabel = RegExp(
    r'(动作|旁白|内心|心理|场景|神态|表情)[ \t]*[:：]');
final _jsonFragments = RegExp(r'[{}\[\]]|"[\w\u4e00-\u9fff]+"\s*:');
final _starActions = RegExp(r'\*[^*\n]{1,60}\*');
final _underscoreActions = RegExp(r'(?<!\w)_[^_\n]{1,60}_(?!\w)');
final _parenActions =
    RegExp(r'[（(【\[][^）)】\n]{1,80}[）)】\]]');
final _markdownSymbols = RegExp(r'[*#>`~|]{1,3}');
final _clockTimes = RegExp(r'\d{1,2}:\d{2}');
final _emoji = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]',
    unicode: true);
final _repeatPause = RegExp(r'[，,、\s]{2,}');

/// Returns the speakable text, or '' when nothing meaningful is left.
String spokenText(String raw) {
  // Labeled-structure replies (story contracts): keep only spoken lines.
  final spoken = <String>[];
  for (final line in raw.split('\n')) {
    var m = _spokenLineLabel.firstMatch(line);
    m ??= _speechLineLabel.firstMatch(line);
    if (m != null && m.group(1)!.trim().isNotEmpty) {
      spoken.add(m.group(1)!.trim());
    }
  }
  var source = spoken.isNotEmpty ? spoken.join('，') : raw;
  // Story mode: extract only the quoted dialogue — what the character
  // actually SAYS to the player. Everything else is narration/action.
  final quotes = <String>[];
  for (final match in _dialogueQuote.allMatches(source)) {
    final segment =
        match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
    if (segment.trim().isNotEmpty) quotes.add(segment.trim());
  }
  if (quotes.isNotEmpty) source = quotes.join('，');
  var text = source
      .replaceAll(_silentLineLabels, '')
      .replaceAll(_inlineSilentLabel, '，')
      .replaceAll(_noiseTokens, '，')
      .replaceAll(_starActions, '，')
      .replaceAll(_underscoreActions, '，')
      .replaceAll(_parenActions, '，')
      .replaceAll(_jsonFragments, '')
      .replaceAll(_markdownSymbols, '')
      .replaceAll(_clockTimes, '，')
      .replaceAll(_emoji, '')
      .replaceAll(_repeatPause, '，');
  return text
      .replaceAll(RegExp(r'^[，,。.\s]+'), '')
      .replaceAll(RegExp(r'[，,。\s]+$'), '')
      .trim();
}
