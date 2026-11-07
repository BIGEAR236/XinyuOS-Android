/// View-only formatting of a virtual red packet.
/// The wallet/ledger must never depend on these display strings.
class XyRedPacketPresenter {
  /// Only show the blessing typed by the sender, not the amount or cover label.
  /// Handles V4.2 messages that had the amount and cover in their text payload.
  static String blessing(String raw) {
    const prefix = '🧧 虚拟红包 ';
    final value = raw.startsWith(prefix) ? raw.substring(prefix.length) : raw;
    final match = RegExp(r'^\d+\s*星币\s*[:：]\s*').firstMatch(value);
    var note = match == null ? value : value.substring(match.end);
    for (final cover in const ['我的自定义封面', '樱花祝福', '星空心愿', '暖阳陪伴']) {
      if (note.startsWith('$cover · ')) {
        note = note.substring(cover.length + 3);
        break;
      }
    }
    return note.trim().isEmpty ? '恭喜发财，大吉大利' : note.trim();
  }
}
