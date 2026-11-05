/// Monotonic request tickets prevent cancelled/stale completions from altering
/// a new generation. This contains no network calls or Flutter dependencies.
class RequestGate {
  final Map<String,int> _tickets = {};
  int start(String thread) {
    final id=(_tickets[thread] ?? 0)+1;
    _tickets[thread]=id;
    return id;
  }
  int cancel(String thread) => start(thread);
  bool isCurrent(String thread, int ticket) => _tickets[thread] == ticket;
}
