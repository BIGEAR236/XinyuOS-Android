/// Strips roleplay/formatting that should never be SPOKEN aloud before the
/// text goes to TTS. Story-mode replies keep ONLY quoted dialogue (the
/// character's spoken words); narration and actions stay silent. When no
/// quotes are present the plain cleanup applies.
library;

/// Paired quotes: “” ‘’ «» "" '' plus CJK 「」『』. Group 1 holds the content.
final _dialogueQuote = RegExp(
    '[“"\']([^“”"\'』」]{1,150})[”"\']|「([^」]{1,150})」|『([^』]{1,150})』');

final _noiseTokens = RegExp(r'\[虚拟(?:红包|礼物)[^\]]*\]');
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
  // Story mode: extract only the quoted dialogue — what the character
  // actually SAYS to the player. Everything else is narration/action.
  final quotes = <String>[];
  for (final match in _dialogueQuote.allMatches(raw)) {
    final segment =
        match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
    if (segment.trim().isNotEmpty) quotes.add(segment.trim());
  }
  final source = quotes.isNotEmpty ? quotes.join('，') : raw;
  var text = source
      .replaceAll(_noiseTokens, '，')
      .replaceAll(_starActions, '，')
      .replaceAll(_underscoreActions, '，')
      .replaceAll(_parenActions, '，')
      .replaceAll(_markdownSymbols, '')
      .replaceAll(_clockTimes, '，')
      .replaceAll(_emoji, '')
      .replaceAll(_repeatPause, '，');
  return text
      .replaceAll(RegExp(r'^[，,。.\s]+'), '')
      .replaceAll(RegExp(r'[，,。\s]+$'), '')
      .trim();
}
