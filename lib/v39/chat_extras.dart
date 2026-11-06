/// Pure helpers for model reply display and local virtual gift markers.
/// No network, payment processing or external token transfer.
class ReplySegmenter {
  /// Split one MODEL response into up to 3 short chat bubbles (one API call).
  /// Structured story, JSON, Markdown/code and very short replies are untouched.
  static List<String> split(String answer, int requested) {
    final text = answer.trim();
    // Keep gift tokens intact and attached to the last bubble so the claim
    // button can be shown after a single model request.
    final gift = VirtualGiftOffer.parse(text);
    if (gift != null && requested > 1) {
      final match = RegExp(r'(?:^|\n)\s*\[虚拟(?:红包|礼物)[:：][^\]\n]+\]\s*$').firstMatch(text);
      if (match != null && match.start > 0) {
        final before = text.substring(0, match.start).trim();
        if (before.isNotEmpty) {
          final segments = split(before, requested);
          segments[segments.length - 1] += '\n${text.substring(match.start).trim()}';
          return segments;
        }
      }
    }
    if (requested <= 1 || text.length < 24 || text.contains('```') ||
      text.startsWith('{') || text.startsWith('[') ||
      RegExp(r'(?m)^\*\*\d{2}:\d{2}\*\*\s*\|').hasMatch(text) ||
      RegExp(r'(?m)^\s*[-*#>]\s').hasMatch(text)) return [text];
    final count = requested.clamp(1, 3).toInt();
    final parts = text.split(RegExp(r'\n\s*\n|(?<=。)|(?<=！)|(?<=？)|(?<=!)|(?<=\?)'))
        .map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
    // If prose has fewer sentences than requested bubbles, split the longest
    // sentence close to the middle, preferring natural commas/semicolons.
    while (parts.length < count) {
      var longest = 0;
      for (var i = 1; i < parts.length; i++) {
        if (parts[i].length > parts[longest].length) longest = i;
      }
      final phrase = parts[longest];
      if (phrase.length < 24) break;
      final target = phrase.length ~/ 2;
      var cut = target;
      for (var delta = 0; delta < 10; delta++) {
        for (final pos in [target - delta, target + delta]) {
          if (pos > 8 && pos < phrase.length - 8 &&
            '，,；;、 '.contains(phrase[pos])) {
            cut = pos + 1; break;
          }
        }
        if (cut != target) break;
      }
      parts
        ..removeAt(longest)
        ..insertAll(longest, [phrase.substring(0, cut).trim(), phrase.substring(cut).trim()]);
    }
    if (parts.length <= count) return parts;
    final result = <String>[];
    var index = 0;
    for (var slot = 0; slot < count; slot++) {
      final slotsLeft = count - slot;
      final targetLength = (parts.sublist(index).join().length / slotsLeft).ceil();
      var bubble = '';
      while (index < parts.length - slotsLeft + 1) {
        bubble += parts[index++];
        if (bubble.length >= targetLength) break;
      }
      result.add(bubble);
    }
    return result.where((s) => s.isNotEmpty).toList();
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
