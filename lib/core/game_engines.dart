import 'dart:math';

/// 15x15 Gomoku. AI never asks the LLM to choose a legal move.
class Gomoku {
  static const n = 15;
  final board = List<int>.filled(n * n, 0);
  int winner = 0;
  bool get over => winner != 0 || !board.contains(0);
  int at(int r, int c) => (r < 0 || r >= n || c < 0 || c >= n) ? -1 : board[r * n + c];
  bool put(int row, int col, int player) {
    if (over || row < 0 || row >= n || col < 0 || col >= n || board[row * n + col] != 0) return false;
    board[row * n + col] = player;
    for (final d in const [[0, 1], [1, 0], [1, 1], [1, -1]]) {
      var count = 1;
      for (final sign in [-1, 1]) {
        var r = row + d[0] * sign;
        var c = col + d[1] * sign;
        while (at(r, c) == player) { count++; r += d[0] * sign; c += d[1] * sign; }
      }
      if (count >= 5) winner = player;
    }
    return true;
  }

  int _streakScore(int row, int col, int owner) {
    var score = 0;
    for (final d in const [[1, 0], [0, 1], [1, 1], [1, -1]]) {
      var same = 1;
      var openEnds = 0;
      for (final dir in [-1, 1]) {
        var r = row + d[0] * dir;
        var c = col + d[1] * dir;
        while (at(r, c) == owner) { same++; r += d[0] * dir; c += d[1] * dir; }
        if (at(r, c) == 0) openEnds++;
      }
      score += same >= 5 ? 200000 : same == 4 ? (openEnds == 2 ? 17000 : 8000) :
          same == 3 ? (openEnds == 2 ? 1800 : 340) :
          same == 2 ? (openEnds == 2 ? 130 : 30) : 2;
    }
    return score;
  }

  (int, int)? bestAiMove() {
    if (over) return null;
    if (board.every((i) => i == 0)) return (7, 7);
    var bestScore = -1;
    var best = (7, 7);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (at(r, c) != 0) continue;
        var near = false;
        for (var dr = -2; dr <= 2 && !near; dr++) {
          for (var dc = -2; dc <= 2; dc++) { if (at(r + dr, c + dc) > 0) { near = true; break; } }
        }
        if (!near) continue;
        final own = _streakScore(r, c, 2);
        final block = _streakScore(r, c, 1);
        final score = own + (block * 1.1).round() + 14 - (r - 7).abs() - (c - 7).abs();
        if (score > bestScore) { bestScore = score; best = (r, c); }
      }
    }
    return best;
  }
}

/// Simplified two-player flight chess: two planes per side, 24-step loop.
/// 6 launches a plane, captures reset it, reaching >=24 finishes.
class FlightChess {
  final Random rng;
  final human = [-1, -1];
  final ai = [-1, -1];
  String news = '掷出6点才能让飞机起飞';
  int lastHumanDice = 0;
  int lastAiDice = 0;
  FlightChess({Random? random}) : rng = random ?? Random.secure();
  bool get over => human.every((p) => p >= 24) || ai.every((p) => p >= 24);
  String get winner => human.every((p) => p >= 24) ? '你获胜' : ai.every((p) => p >= 24) ? 'AI 获胜' : '';
  List<int> choices(List<int> fleet, int die) => [for (int i = 0; i < fleet.length; i++) if (fleet[i] < 24 && (fleet[i] >= 0 || die == 6)) i];
  String _move(List<int> ours, List<int> theirs, int idx, int die, String who) {
    final old = ours[idx];
    ours[idx] = old == -1 ? 0 : min(24, old + die);
    var caught = '';
    if (ours[idx] < 24) {
      for (var j = 0; j < theirs.length; j++) {
        if (theirs[j] == ours[idx]) { theirs[j] = -1; caught = '，撞回对手一架飞机'; }
      }
    }
    return '$who的${idx + 1}号飞机移动到第${ours[idx] + 1}格$caught';
  }
  int roll() => rng.nextInt(6) + 1;
  List<int> humanOptions(int die) => choices(human, die);
  String humanMove(int die, int idx) {
    lastHumanDice = die;
    if (!choices(human, die).contains(idx)) return '这一回合无法移动该飞机';
    news = _move(human, ai, idx, die, '你');
    return news;
  }
  String aiTurn() {
    if (over) return winner;
    final die = roll(); lastAiDice = die;
    final options = choices(ai, die);
    if (options.isEmpty) return news = 'AI 掷出 $die 点，没有可移动的飞机';
    options.sort((a,b) => ai[b].compareTo(ai[a]));
    return news = 'AI 掷出 $die 点，${_move(ai, human, options.first, die, 'AI')}';
  }
}

class PropertyTile {
  final String name;
  final int price;
  final int rent;
  int owner; // -1 none, 0 human, 1 AI
  PropertyTile(this.name, this.price, this.rent, {this.owner = -1});
}

/// 16-square local board game. Never handles real currency or purchases.
class TinyMonopoly {
  final Random rng;
  final tiles = <PropertyTile>[
    PropertyTile('起点', 0, 0), PropertyTile('云朵街', 120, 24), PropertyTile('甜品巷', 140, 28),
    PropertyTile('礼物事件', 0, 0), PropertyTile('星光广场', 180, 36), PropertyTile('樱花路', 160, 32),
    PropertyTile('糖果店', 150, 30), PropertyTile('幸运事件', 0, 0), PropertyTile('梦境大道', 240, 48),
    PropertyTile('公园街', 190, 38), PropertyTile('萌宠小屋', 230, 46), PropertyTile('休憩', 0, 0),
    PropertyTile('音乐厅', 260, 52), PropertyTile('月亮站', 210, 42), PropertyTile('游乐园', 280, 56),
    PropertyTile('惊喜事件', 0, 0),
  ];
  final positions = [0, 0];
  final balances = [1200, 1200];
  final log = <String>[];
  int lastDice = 0;
  bool finished = false;
  TinyMonopoly({Random? random}) : rng = random ?? Random.secure();

  String turn(int player, {bool buy = true}) {
    if (finished) return '游戏已结束';
    final die = rng.nextInt(6) + 1;
    lastDice = die;
    final from = positions[player];
    positions[player] = (from + die) % tiles.length;
    if (positions[player] <= from) balances[player] += 200;
    final tile = tiles[positions[player]];
    var message = '${player == 0 ? '你' : 'AI'}掷出 $die 点，来到${tile.name}';
    if (tile.price > 0) {
      if (tile.owner == -1 && buy && balances[player] >= tile.price) {
        balances[player] -= tile.price;
        tile.owner = player;
        message += '，花 ${tile.price} 星币买下了这里';
      } else if (tile.owner >= 0 && tile.owner != player) {
        balances[player] -= tile.rent;
        balances[1 - player] += tile.rent;
        message += '，支付租金 ${tile.rent} 星币';
      }
    } else if (positions[player] == 3 || positions[player] == 7 || positions[player] == 15) {
      balances[player] += 80;
      message += '，领取意外礼物 80 星币';
    }
    if (balances[player] <= 0) { finished = true; message += '，破产，游戏结束'; }
    log.insert(0, message);
    return message;
  }
}
