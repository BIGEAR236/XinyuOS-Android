/// Pure helpers for model reply display and local virtual gift markers.
/// No network, payment processing or external token transfer.
class ReplySegmenter {
  /// Formats ONE already-received model answer as 1-3 display bubbles.
  /// No network requests are made here. Never split structured roleplay output.
  static List<String> split(String answer, int requested) {
    final text = answer.trim();
    final count = requested.clamp(1, 3).toInt();
    if (count <= 1 || text.length < 24 || _isStructured(text)) {
      return [text];
    }

    // A claimable virtual gift/red packet must stay at the *end* of the last
    // bubble. Do not create a separate gift-only message with another ID.
    var prose = text;
    var giftSuffix = '';
    if (VirtualGiftOffer.parse(text) != null) {
      final match = RegExp(
        r'(?:^|\n)\s*\[虚拟(?:红包|礼物)[:：][^\]\n]+\]\s*$',
      ).firstMatch(text);
      if (match != null && match.start > 0) {
        prose = text.substring(0, match.start).trimRight();
        giftSuffix = text.substring(match.start).trim();
      }
    }

    if (prose.length < 24 || _isStructured(prose)) return [text];

    // Split after sentence punctuation without zero-width regex/lookbehinds.
    // Every source character remains in exactly one chunk, so join() is
    // lossless for normal prose (including spaces and newlines).
    final parts = <String>[];
    var start = 0;
    for (var i = 0; i < prose.length; i++) {
      final char = prose[i];
      if ('。！？!?'.contains(char) && i + 1 < prose.length) {
        parts.add(prose.substring(start, i + 1));
        start = i + 1;
      } else if (char == '\n' && i > 0 && prose[i - 1] == '\n' &&
          i + 1 < prose.length) {
        parts.add(prose.substring(start, i + 1));
        start = i + 1;
      }
    }
    if (start < prose.length) parts.add(prose.substring(start));

    // For a single long sentence, prefer a natural comma or semicolon.
    // If none exists, split near the midpoint to honor 2/3 short bubbles.
    while (parts.length < count) {
      var longestIndex = 0;
      for (var i = 1; i < parts.length; i++) {
        if (parts[i].length > parts[longestIndex].length) longestIndex = i;
      }
      final phrase = parts[longestIndex];
      if (phrase.length < 12) break;
      final cut = _naturalCut(phrase);
      if (cut <= 0 || cut >= phrase.length) break;
      parts
        ..removeAt(longestIndex)
        ..insertAll(longestIndex, [phrase.substring(0, cut), phrase.substring(cut)]);
    }

    if (parts.length < 2) return [text];
    final bubbleCount = count < parts.length ? count : parts.length;
    final result = <String>[];
    var index = 0;

    // Choose sentence boundaries nearest equal text lengths, always leaving
    // at least one intact chunk for each remaining bubble.
    for (var slot = 0; slot < bubbleCount - 1; slot++) {
      final slotsLeft = bubbleCount - slot;
      final target = parts.sublist(index).join().length / slotsLeft;
      var end = index + 1;
      var length = parts[index].length;
      final maxEnd = parts.length - (slotsLeft - 1);
      while (end < maxEnd) {
        final nextLength = length + parts[end].length;
        if ((nextLength - target).abs() >= (length - target).abs()) break;
        length = nextLength;
        end++;
      }
      result.add(parts.sublist(index, end).join());
      index = end;
    }
    result.add(parts.sublist(index).join());

    if (giftSuffix.isNotEmpty) {
      result[result.length - 1] += '\n$giftSuffix';
    }
    return result;
  }

  static bool _isStructured(String text) =>
      text.contains('```') ||
      text.startsWith('{') || text.startsWith('[') ||
      RegExp(r'(?m)^\*\*\d{2}:\d{2}\*\*\s*\|').hasMatch(text) ||
      RegExp(r'(?m)^\s*[-*#>]\s').hasMatch(text);

  static int _naturalCut(String text) {
    final midpoint = text.length ~/ 2;
    var best = -1;
    var distance = text.length;
    for (var i = 5; i < text.length - 5; i++) {
      if ('，,；;、'.contains(text[i])) {
        final candidate = i + 1;
        final delta = (candidate - midpoint).abs();
        if (delta < distance) {
          best = candidate;
          distance = delta;
        }
      }
    }
    if (best >= 0) return best;

    // Dart String offsets are UTF-16: avoid cutting an emoji surrogate pair.
    var cut = midpoint;
    if (cut > 0 && cut < text.length) {
      final left = text.codeUnitAt(cut - 1);
      final right = text.codeUnitAt(cut);
      if (left >= 0xD800 && left <= 0xDBFF &&
          right >= 0xDC00 && right <= 0xDFFF) {
        cut++;
      }
    }
    return cut;
  }
}

class VirtualGiftOffer {
  final String kind; // red or gift
  final String name;
  final int coins;
  const VirtualGiftOffer(this.kind, this.name, this.coins);
  bool get isRedPacket => kind == 'red';

  static VirtualGiftOffer? parse(String text) {
    final trimmed = text.trim();
    // Only a final standalone token is actionable, never quote fragments.
    final match = RegExp(r'(?:^|\n)\s*\[虚拟(红包|礼物)[:：]([^\]\n]{1,24})\]\s*$').firstMatch(trimmed);
    if (match == null) return null;
    final raw = match.group(2)!.trim();
    if (match.group(1) == '红包') {
      final count = int.tryParse(raw.replaceAll('星币', '').trim());
      if (count == null || count < 1 || count > 30) return null;
      return VirtualGiftOffer('red', '星币红包', count);
    }
    if (raw.isEmpty || raw.contains('[') || raw.contains(']')) return null;
    return VirtualGiftOffer('gift', raw, 0);
  }
}
