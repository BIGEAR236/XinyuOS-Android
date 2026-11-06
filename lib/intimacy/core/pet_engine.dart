import 'dart:math';

class PetSpecies {
  final String id, name, emoji, rarity, color, trait;
  const PetSpecies(this.id, this.name, this.emoji, this.rarity, this.color, this.trait);
}

const petSpecies = <PetSpecies>[
  PetSpecies('cat', '奶泡猫', '🐱', 'common', 'FFEDBDCE', '傲娇贪睡'),
  PetSpecies('dog', '棉花犬', '🐶', 'common', 'FFEAC598', '热情忠诚'),
  PetSpecies('rabbit', '糯米兔', '🐰', 'common', 'FFFFD2E4', '胆小可爱'),
  PetSpecies('hamster', '布丁仓鼠', '🐹', 'common', 'FFFFDA9C', '喜欢囤食'),
  PetSpecies('penguin', '泡泡企鹅', '🐧', 'common', 'FFB4CEE3', '爱滑行'),
  PetSpecies('hedgehog', '团子刺猬', '🦔', 'common', 'FFE5C7AA', '慢热胆小'),
  PetSpecies('fox', '糖霜狐狸', '🦊', 'rare', 'FFF7B68D', '聪明淘气'),
  PetSpecies('panda', '芝麻熊猫', '🐼', 'rare', 'FFDFE1E9', '爱吃竹笋'),
  PetSpecies('otter', '奶糖水獭', '🦦', 'rare', 'FFC6A58B', '亲水爱玩'),
  PetSpecies('squirrel', '栗子松鼠', '🐿️', 'rare', 'FFF5C59E', '活力满满'),
  PetSpecies('deer', '星星小鹿', '🦌', 'rare', 'FFF2C9B4', '温柔敏感'),
  PetSpecies('axolotl', '软糖六角龙', '🦎', 'rare', 'FFFFB3D3', '好奇亲水'),
  PetSpecies('dragon', '云朵龙', '🐲', 'legendary', 'FFB6D8E0', '会吐彩虹'),
  PetSpecies('unicorn', '月光独角兽', '🦄', 'legendary', 'FFD9C6F7', '喜欢音乐'),
  PetSpecies('jellyfish', '果冻水母', '🪼', 'legendary', 'FFBAC2FB', '随音乐发光'),
];

class PetState {
  String? species;
  String name;
  String egg;
  int eggProgress;
  int affection;
  int hunger;
  int joy;
  int energy;
  int level;
  int xp;
  int lastCareAt;
  int hatchedAt;
  List<List<List<double>>> strokes;
  PetState({
    this.species,
    this.name = '',
    this.egg = '云朵蛋',
    this.eggProgress = 0,
    this.affection = 0,
    this.hunger = 65,
    this.joy = 65,
    this.energy = 70,
    this.level = 1,
    this.xp = 0,
    int? lastCareAt,
    this.hatchedAt = 0,
    List<List<List<double>>>? strokes,
  }) : lastCareAt = lastCareAt ?? DateTime.now().millisecondsSinceEpoch,
       _createdAt = lastCareAt ?? DateTime.now().millisecondsSinceEpoch,
       strokes = strokes ?? [];

  bool get isHatched => species != null;
  PetSpecies? get kind { for (final item in petSpecies) { if (item.id == species) return item; } return null; }
  int get mood => ((joy + energy + (100 - hunger)) / 3).round();
  String get expression => mood >= 70 ? '开心' : mood >= 40 ? '撒娇' : '疲惫';

  void decay(DateTime now) {
    final hours = ((now.millisecondsSinceEpoch - lastCareAt) / 3600000).floor().clamp(0, 48).toInt();
    if (hours > 0) {
      hunger = (hunger + hours * 2).clamp(0, 100).toInt();
      joy = (joy - hours).clamp(0, 100).toInt();
      energy = (energy - hours).clamp(0, 100).toInt();
      lastCareAt = now.millisecondsSinceEpoch;
    }
  }

  String act(String action, DateTime now) {
    decay(now);
    if (!isHatched) {
      final delta = {'唱歌': 8, '抚摸': 6, '讲故事': 10, '摇篮曲': 8, '绘画': 5, '拥抱': 7}[action] ?? 3;
      eggProgress = (eggProgress + delta).clamp(0, 100).toInt();
      affection = (affection + 3).clamp(0, 100).toInt();
      return '你和角色一起${action}，蛋轻轻晃了晃。孵化亲密值 $eggProgress/100';
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
    affection = (affection + 2).clamp(0, 100).toInt();
    xp += 9;
    while (xp >= level * 90) { xp -= level * 90; level++; }
    lastCareAt = now.millisecondsSinceEpoch;
    return '${name.isEmpty ? kind!.name : name}刚刚完成${action}，现在${expression}，成长等级 Lv.$level';
  }

  /// Requires time AND joint interaction. Calling it before the conditions holds has no effect.
  bool get canHatch => !isHatched && eggProgress >= 80 &&
       DateTime.now().millisecondsSinceEpoch - lastCareAt >= 0 &&
       (DateTime.now().millisecondsSinceEpoch - createdAt) >= 3600000;
  int get createdAt => _createdAt ?? lastCareAt;
  int? _createdAt;
  void setCreatedAt(DateTime date) => _createdAt = date.millisecondsSinceEpoch;

  PetSpecies hatch({Random? rng, bool debugSkipTime = false}) {
    if (isHatched || eggProgress < 80 || (!debugSkipTime && !canHatch)) {
      throw StateError('需孵化亲密值达到80，并经过至少1小时');
    }
    final random = rng ?? Random.secure();
    final r = random.nextInt(100);
    final rarity = r < 65 ? 'common' : r < 93 ? 'rare' : 'legendary';
    final pool = petSpecies.where((p) => p.rarity == rarity).toList();
    final themes=<String,List<String>>{
      '云朵蛋':['cat','rabbit','panda','penguin','unicorn'],
      '森林蛋':['fox','deer','hedgehog','squirrel','dragon'],
      '海洋蛋':['otter','axolotl','jellyfish','penguin'],
      '星光蛋':['dragon','unicorn','jellyfish','fox'],
      '梦幻蛋':[for(final p in petSpecies)p.id],
    };
    final eligible=pool.where((p)=>(themes[egg]??const <String>[]).contains(p.id)).toList();
    final drawPool=eligible.isNotEmpty && random.nextInt(100)<65?eligible:pool;
    final chosen = drawPool[random.nextInt(drawPool.length)];
    species = chosen.id;
    name = chosen.name;
    hatchedAt = DateTime.now().millisecondsSinceEpoch;
    strokes = []; // Egg drawing does not remain on the hatched pet.
    return chosen;
  }

  Map<String, dynamic> toJson() => {
    'species': species, 'name': name, 'egg': egg, 'eggProgress': eggProgress,
    'affection': affection, 'hunger': hunger, 'joy': joy, 'energy': energy,
    'level': level, 'xp': xp, 'lastCareAt': lastCareAt, 'hatchedAt': hatchedAt,
    'createdAt': createdAt, 'strokes': strokes,
  };

  factory PetState.fromJson(Map<String, dynamic> j) {
    final s = PetState(
      species: j['species'] as String?, name: '${j['name'] ?? ''}', egg: '${j['egg'] ?? '云朵蛋'}',
      eggProgress: (j['eggProgress'] as num?)?.toInt() ?? 0,
      affection: (j['affection'] as num?)?.toInt() ?? 0,
      hunger: (j['hunger'] as num?)?.toInt() ?? 65,
      joy: (j['joy'] as num?)?.toInt() ?? 65,
      energy: (j['energy'] as num?)?.toInt() ?? 70,
      level: (j['level'] as num?)?.toInt() ?? 1,
      xp: (j['xp'] as num?)?.toInt() ?? 0,
      lastCareAt: (j['lastCareAt'] as num?)?.toInt(),
      hatchedAt: (j['hatchedAt'] as num?)?.toInt() ?? 0,
      strokes: (j['strokes'] as List? ?? []).map((stroke) =>
        (stroke as List).map((point) => (point as List).map((e) => (e as num).toDouble()).toList()).toList(),
      ).toList(),
    );
    s._createdAt = (j['createdAt'] as num?)?.toInt() ?? s.lastCareAt;
    return s;
  }
}
