import 'dart:convert';

/// Separates scene, narration, spoken dialogue, thoughts, and status.
/// The model can return a JSON envelope; legacy Markdown is accepted as a fallback.
enum StoryKind { action, speech, thought }

class StoryBeat {
  final StoryKind kind;
  final String text;
  final String speaker;
  const StoryBeat(this.kind, this.text, [this.speaker = '']);
}

class StoryScene {
  final String time;
  final String place;
  final List<StoryBeat> beats;
  final Map<String, String> status;
  const StoryScene(this.time, this.place, this.beats, this.status);
}

class StoryParser {
  static const outputContract = '''你是沉浸剧情对话生成器。角色设定用于确定人格，不是供你逐字复述的文本。
用户的即时指令必须遵守，不要将内心独白写成角色对白。
请只输出一个 JSON 对象，不要输出 Markdown 代码围栏、前后解释：
{"time":"HH:MM","place":"虚拟场景","beats":[
  {"type":"action","speaker":"","text":"25字以内的动作"},
  {"type":"speech","speaker":"角色名","text":"角色直接说出口的话"},
  {"type":"thought","speaker":"角色名","text":"只有读者能看到的内心想法"}
],"status":{"剧情地点":"地点","好感度":"38%","爱意":"12%","醋意":"0%","内心":"20字以内的心理总结"}}
动作、对白、心声必须为不同条目，不能混在同一字段，每句对白与每段动作各自一个条目。动作不超过25字。状态包含剧情地点、好感度、爱意、醋意、内心。时间精确到分钟，按 HH:MM 输出，优先使用应用传入的当前时间；未知地点不要编造现实位置。
''';

  static List<String> validate(StoryScene scene) {
    final failures=<String>[];
    if(!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(scene.time)) {
      failures.add('场景时间必须是 HH:MM');
    }
    if(scene.place.isEmpty) failures.add('缺少场景地点');
    if(scene.beats.isEmpty) failures.add('没有任何有效的剧情内容');
    for(final beat in scene.beats) {
      if(beat.kind==StoryKind.action && beat.text.runes.length>25) failures.add('动作描写超过25字');
      if(beat.kind==StoryKind.speech && beat.speaker.trim().isEmpty) failures.add('对白缺少角色姓名');
    }
    for(final key in ['剧情地点','好感度','爱意','醋意','内心']) {
      if(!scene.status.containsKey(key)) failures.add('状态缺少$key');
    }
    return failures;
  }

  static String toMarkdown(StoryScene scene) {
    final out=<String>['**${scene.time}** | ${scene.place}',''];
    for(final beat in scene.beats){
      switch(beat.kind){
        case StoryKind.action: out.add('`${beat.text}`'); break;
        case StoryKind.speech: out.add('${beat.speaker} | ${beat.text}'); break;
        case StoryKind.thought: out.add('> `${beat.text}`'); break;
      }
      out.add('');
    }
    out.add('```');
    for(final key in ['剧情地点','好感度','爱意','醋意','内心']) {
      out.add('$key：${scene.status[key]??''}');
    }
    out.add('```');
    return out.join('\n');
  }

  static StoryScene parse(String raw, {String fallbackName = '角色'}) {
    final trimmed = raw.trim();
    String input = trimmed;
    if (input.startsWith('```')) {
      input = input.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      input = input.replaceFirst(RegExp(r'\s*```$'), '');
    }
    try {
      final obj = jsonDecode(input);
      if (obj is Map<String, dynamic> && obj['beats'] is List) {
        final beats = <StoryBeat>[];
        for (final item in (obj['beats'] as List)) {
          if (item is! Map) continue;
          final type = '${item['type'] ?? ''}';
          final kind = type == 'thought' ? StoryKind.thought : type == 'action' ? StoryKind.action : StoryKind.speech;
          var t = '${item['text'] ?? ''}'.trim();
          if (kind == StoryKind.action && t.runes.length > 25) {
            t = String.fromCharCodes(t.runes.take(25));
          }
          if (t.isNotEmpty) beats.add(StoryBeat(kind, t, '${item['speaker'] ?? fallbackName}'));
        }
        final status = <String, String>{};
        if (obj['status'] is Map) {
          (obj['status'] as Map).forEach((k, v) => status['$k'] = '$v');
        }
        return StoryScene('${obj['time'] ?? ''}', '${obj['place'] ?? ''}', beats, status);
      }
    } catch (_) { /* fallback to Markdown */ }
    return parseMarkdown(trimmed, fallbackName: fallbackName);
  }

  static StoryScene parseMarkdown(String input, {String fallbackName = '角色'}) {
    final lines = const LineSplitter().convert(input);
    final beats = <StoryBeat>[];
    final status = <String, String>{};
    var inCode = false;
    var currentTime = '';
    var place = '';
    final timeRE = RegExp(r'^\*\*(\d{2}:\d{2})\*\*\s*\|\s*(.+)$');
    final speechRE = RegExp(r'^([^>|`]{1,25})\s*\|\s*(.+)$');
    for (final source in lines) {
      final line = source.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('```')) { inCode = !inCode; continue; }
      if (inCode) {
        final pivot = line.indexOf('：');
        if (pivot >= 0) status[line.substring(0, pivot).trim()] = line.substring(pivot + 1).trim();
        continue;
      }
      final timeMatch = timeRE.firstMatch(line);
      if (timeMatch != null) {
        currentTime = timeMatch.group(1)!;
        place = timeMatch.group(2)!;
        continue;
      }
      if (line.startsWith('>')) {
        final text = line.substring(1).trim().replaceAll(RegExp(r'^`|`$'), '');
        if (text.isNotEmpty) beats.add(StoryBeat(StoryKind.thought, text, fallbackName));
        continue;
      }
      if (line.startsWith('`') && line.endsWith('`')) {
        beats.add(StoryBeat(StoryKind.action, line.substring(1, line.length - 1), fallbackName));
        continue;
      }
      final speech = speechRE.firstMatch(line);
      if (speech != null) {
        beats.add(StoryBeat(StoryKind.speech, speech.group(2)!.trim(), speech.group(1)!.trim()));
        continue;
      }
      if (line.startsWith('内心：') || line.startsWith('心声：')) {
        beats.add(StoryBeat(StoryKind.thought, line.substring(3).trim(), fallbackName));
      } else {
        // Unknown text is displayed as unclassified speech rather than silently dropped.
        beats.add(StoryBeat(StoryKind.speech, line, fallbackName));
      }
    }
    return StoryScene(currentTime, place, beats, status);
  }
}
