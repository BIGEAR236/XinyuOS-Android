import 'dart:math';

/// Tier sizes: 15 white / 10 green / 4 gold / 1 red.
/// Tier odds per egg: 70% / 24% / 5% / 1%. Individual odds differ
/// because each species has a different weight and egg themes bias selection.
class PetSpecies {
  final String id, name, emoji, rarity, color, trait;
  final int weight;
  const PetSpecies(this.id, this.name, this.emoji, this.rarity, this.color, this.trait, this.weight);
}

const rarityNames = <String, String>{
  'white': '白色·常见', 'green': '绿色·珍稀',
  'gold': '金色·史诗', 'red': '红色·传说',
};
const rarityOdds = <String, int>{'white': 70, 'green': 24, 'gold': 5, 'red': 1};
const petSpecies = <PetSpecies>[
  PetSpecies('cat', '奶泡猫', '🐱', 'white', 'FFEDBDCE', '傲娇贪睡', 20),
  PetSpecies('dog', '棉花犬', '🐶', 'white', 'FFEAC598', '热情忠诚', 19),
  PetSpecies('rabbit', '糯米兔', '🐰', 'white', 'FFFFD2E4', '胆小可爱', 18),
  PetSpecies('hamster', '布丁仓鼠', '🐹', 'white', 'FFFFDA9C', '喜欢囤食', 17),
  PetSpecies('penguin', '泡泡企鹅', '🐧', 'white', 'FFB4CEE3', '爱滑行', 16),
  PetSpecies('hedgehog', '团子刺猬', '🦔', 'white', 'FFE5C7AA', '慢热胆小', 15),
  PetSpecies('squirrel', '栗子松鼠', '🐿️', 'white', 'FFF5C59E', '活力满满', 14),
  PetSpecies('duck', '黄油小鸭', '🦆', 'white', 'FFFFE7A3', '总爱排队', 13),
  PetSpecies('frog', '荷叶蛙蛙', '🐸', 'white', 'FFBFE3C1', '爱听下雨', 12),
  PetSpecies('chick', '麦芽小鸡', '🐥', 'white', 'FFFCE9A7', '软绵绵', 11),
  PetSpecies('turtle', '青豆海龟', '🐢', 'white', 'FFB7D5BE', '悠闲稳重', 10),
  PetSpecies('bee', '蜜糖小蜂', '🐝', 'white', 'FFFFDB83', '辛勤开朗', 9),
  PetSpecies('koala', '云眠考拉', '🐨', 'white', 'FFD0CED8', '喜欢拥抱', 8),
  PetSpecies('seal', '雪糕海豹', '🦭', 'white', 'FFDEE9EF', '黏人爱笑', 7),
  PetSpecies('snail', '露珠蜗牛', '🐌', 'white', 'FFDBBBCA', '有耐心', 6),
  PetSpecies('fox', '糖霜狐狸', '🦊', 'green', 'FFF7B68D', '聪明淘气', 12),
  PetSpecies('panda', '芝麻熊猫', '🐼', 'green', 'FFDFE1E9', '爱吃竹笋', 11),
  PetSpecies('otter', '奶糖水獭', '🦦', 'green', 'FFC6A58B', '亲水爱玩', 10),
  PetSpecies('deer', '星星小鹿', '🦌', 'green', 'FFF2C9B4', '温柔敏感', 9),
  PetSpecies('axolotl', '软糖六角龙', '🦎', 'green', 'FFFFB3D3', '好奇亲水', 8),
  PetSpecies('redpanda', '红豆小熊猫', '🐾', 'green', 'FFDEAE91', '会藏小礼物', 7),
  PetSpecies('owl', '星夜小鸮', '🦉', 'green', 'FFB9B3D9', '夜间守护', 6),
  PetSpecies('peacock', '琉璃孔雀', '🦚', 'green', 'FFA1D7D5', '优雅自信', 5),
  PetSpecies('dolphin', '蓝铃海豚', '🐬', 'green', 'FF9CCDE9', '活泼聪慧', 4),
  PetSpecies('alpaca', '奶绒羊驼', '🦙', 'green', 'FFF1D9C9', '慢热亲近', 3),
  PetSpecies('dragon', '云朵龙', '🐲', 'gold', 'FFB6D8E0', '会吐彩虹', 8),
  PetSpecies('unicorn', '月光独角兽', '🦄', 'gold', 'FFD9C6F7', '喜欢音乐', 5),
  PetSpecies('jellyfish', '果冻水母', '🪼', 'gold', 'FFBAC2FB', '随音乐发光', 3),
  PetSpecies('phoenix', '琥珀凤凰', '🔥', 'gold', 'FFFFB37F', '温暖守护', 2),
  PetSpecies('starlion', '赤曜星狮', '🦁', 'red', 'FFEFA0A4', '守护深夜星光', 1),
];

const _eggThemes = <String, List<String>>{
  '云朵蛋': ['cat', 'rabbit', 'panda', 'penguin', 'unicorn', 'seal', 'koala'],
  '森林蛋': ['fox', 'deer', 'hedgehog', 'squirrel', 'owl', 'redpanda', 'frog', 'snail'],
  '海洋蛋': ['otter', 'axolotl', 'jellyfish', 'penguin', 'dolphin', 'turtle', 'seal'],
  '星光蛋': ['dragon', 'unicorn', 'jellyfish', 'phoenix', 'starlion', 'owl'],
  '梦幻蛋': [],
};

class PetState {
  String? species;
  String name;
  String egg;
  int eggProgress, affection, hunger, joy, energy, level, xp;
  int lastCareAt, lastInteractionAt, interactionCount, hatchedAt;
  List<List<List<double>>> strokes;
  PetState({
    this.species, this.name = '', this.egg = '云朵蛋',
    this.eggProgress = 0, this.affection = 0,
    this.hunger = 65, this.joy = 65, this.energy = 70,
    this.level = 1, this.xp = 0,
    int? lastCareAt, this.lastInteractionAt = 0,
    this.interactionCount = 0, this.hatchedAt = 0,
    List<List<List<double>>>? strokes,
  }) : lastCareAt = lastCareAt ?? DateTime.now().millisecondsSinceEpoch,
       _createdAt = DateTime.now().millisecondsSinceEpoch,
       strokes = strokes ?? [];

  static const careCooldown = Duration(hours: 1);
  static const minimumHatchAge = Duration(hours: 24);
  static const requiredInteractions = 6;
  int _createdAt;
  int get createdAt => _createdAt;
  bool get isHatched => species != null;
  PetSpecies? get kind {
    for (final item in petSpecies) { if (item.id == species) return item; }
    return null;
  }
  int get mood => ((joy + energy + (100 - hunger)) / 3).round();
  String get expression => mood >= 70 ? '开心' : mood >= 40 ? '撒娇' : '疲惫';

  Duration remainingCooldown(DateTime now) {
    if (lastInteractionAt == 0) return Duration.zero;
    final ms = lastInteractionAt + careCooldown.inMilliseconds - now.millisecondsSinceEpoch;
    return Duration(milliseconds: max(0, ms));
  }
  bool canInteract(DateTime now) => remainingCooldown(now) == Duration.zero;

  void decay(DateTime now) {
    final hours = ((now.millisecondsSinceEpoch - lastCareAt) / 3600000).floor().clamp(0, 48).toInt();
    if (hours > 0) {
      hunger = (hunger + hours * 2).clamp(0, 100).toInt();
      joy = (joy - hours).clamp(0, 100).toInt();
      energy = (energy - hours).clamp(0, 100).toInt();
      lastCareAt = now.millisecondsSinceEpoch;
    }
  }

  /// Successful care changes stats at most once per REAL elapsed hour
  /// while still an egg (hatch pacing). A hatched pet may be cared for
  /// anytime; the local clock is best-effort without a server.
  String act(String action, DateTime now) {
    if (!isHatched) {
      if (!canInteract(now)) {
        final left = remainingCooldown(now);
        final minutes = (left.inMinutes + (left.inSeconds % 60 > 0 ? 1 : 0));
        return '孵化期每小时只能进行一次有效陪伴，再等约 $minutes 分钟。孵化后就能随时和它玩啦。可以自由聊天和画蛋壳。';
      }
    } else {
      lastInteractionAt = now.millisecondsSinceEpoch; // Recorded, never gates play.
    }
    decay(now);
    interactionCount++;
    if (!isHatched) {
      final delta = {'唱歌': 8, '抚摸': 6, '讲故事': 11, '摇篮曲': 9, '绘画': 5, '拥抱': 7}[action] ?? 5;
      eggProgress = (eggProgress + delta).clamp(0, 100).toInt();
      affection = (affection + 1).clamp(0, 100).toInt();
      return '蛋微微晃了晃 · 孵化进度 $eggProgress/100 · 有效陪伴 $interactionCount 次';
    }
    switch (action) {
      case '喂食': hunger = (hunger - 26).clamp(0, 100).toInt(); break;
      case '玩球': joy = (joy + 22).clamp(0, 100).toInt(); energy = (energy - 13).clamp(0, 100).toInt(); break;
      case '洗澡': joy = (joy + 12).clamp(0, 100).toInt(); break;
      case '睡觉': energy = (energy + 32).clamp(0, 100).toInt(); break;
      case '抚摸': joy = (joy + 12).clamp(0, 100).toInt(); break;
      case '挠痒痒': joy = (joy + 16).clamp(0, 100).toInt(); break;
      case '轻拍': joy = (joy + 8).clamp(0, 100).toInt(); break;
      case '训练': energy = (energy - 12).clamp(0, 100).toInt(); break;
      case '探险': energy = (energy - 19).clamp(0, 100).toInt(); joy = (joy + 19).clamp(0, 100).toInt(); break;
    }
    affection = (affection + 1).clamp(0, 100).toInt();
    xp += 12;
    while (xp >= level * 90) { xp -= level * 90; level++; }
    return '${name.isEmpty ? kind?.name ?? '宠物' : name}完成${action}，当前${expression}，Lv.$level（经验 $xp/${level * 90}）';
  }

  bool canHatchAt(DateTime now) => !isHatched && eggProgress >= 80 &&
    interactionCount >= requiredInteractions &&
    now.millisecondsSinceEpoch - createdAt >= minimumHatchAge.inMilliseconds;
  bool get canHatch => canHatchAt(DateTime.now());
  void setCreatedAt(DateTime date) => _createdAt = date.millisecondsSinceEpoch;

  PetSpecies hatch({Random? rng, bool debugSkipTime = false}) {
    if (isHatched || eggProgress < 80 ||
      (!debugSkipTime && !canHatch)) {
      throw StateError('孵化条件：真实时间满24小时、有效互动至少6次、孵化进度≥80。');
    }
    final random = rng ?? Random.secure();
    final roll = random.nextInt(10000);
    final tier = roll < 7000 ? 'white' : roll < 9400 ? 'green' : roll < 9900 ? 'gold' : 'red';
    final pool = petSpecies.where((s) => s.rarity == tier).toList();
    final themed = _eggThemes[egg] ?? const <String>[];
    int adjustedWeight(PetSpecies s) => s.weight * (themed.contains(s.id) ? 2 : 1);
    final totalWeight = pool.fold<int>(0, (n, s) => n + adjustedWeight(s));
    var choice = random.nextInt(totalWeight);
    var chosen = pool.last;
    for (final s in pool) {
      choice -= adjustedWeight(s);
      if (choice < 0) { chosen = s; break; }
    }
    species = chosen.id;
    name = chosen.name;
    hatchedAt = DateTime.now().millisecondsSinceEpoch;
    strokes = []; // Decorations belong to the egg, not the hatched pet.
    return chosen;
  }

  Map<String, dynamic> toJson() => {
    'species': species, 'name': name, 'egg': egg,
    'eggProgress': eggProgress, 'affection': affection, 'hunger': hunger,
    'joy': joy, 'energy': energy, 'level': level, 'xp': xp,
    'lastCareAt': lastCareAt, 'lastInteractionAt': lastInteractionAt,
    'interactionCount': interactionCount, 'hatchedAt': hatchedAt,
    'createdAt': createdAt, 'strokes': strokes,
  };

  factory PetState.fromJson(Map<String, dynamic> j) {
    final s = PetState(
      species: j['species'] as String?, name: '${j['name'] ?? ''}',
      egg: '${j['egg'] ?? '云朵蛋'}',
      eggProgress: (j['eggProgress'] as num?)?.toInt() ?? 0,
      affection: (j['affection'] as num?)?.toInt() ?? 0,
      hunger: (j['hunger'] as num?)?.toInt() ?? 65,
      joy: (j['joy'] as num?)?.toInt() ?? 65,
      energy: (j['energy'] as num?)?.toInt() ?? 70,
      level: (j['level'] as num?)?.toInt() ?? 1,
      xp: (j['xp'] as num?)?.toInt() ?? 0,
      lastCareAt: (j['lastCareAt'] as num?)?.toInt(),
      lastInteractionAt: (j['lastInteractionAt'] as num?)?.toInt() ?? 0,
      interactionCount: (j['interactionCount'] as num?)?.toInt() ?? 0,
      hatchedAt: (j['hatchedAt'] as num?)?.toInt() ?? 0,
      strokes: (j['strokes'] as List? ?? []).map((stroke) =>
        (stroke as List).map((point) => (point as List).map((e) => (e as num).toDouble()).toList()).toList(),
      ).toList(),
    );
    // Existing V3.8 saves remain readable. Their level and species are preserved.
    s._createdAt = (j['createdAt'] as num?)?.toInt() ?? s.lastCareAt;
    return s;
  }
}
