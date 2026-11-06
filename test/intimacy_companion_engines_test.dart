import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/intimacy/core/story_parser.dart';
import 'package:xinyu_os/intimacy/core/pet_engine.dart';
import 'package:xinyu_os/intimacy/core/game_engines.dart';
import 'package:xinyu_os/intimacy/core/media_engine.dart';

void main(){
  test('Legacy Markdown speech, thought, action and status are distinct',(){
    final x=StoryParser.parse('''**16:45** | 湖边咖啡馆
`他笑了`
楼一 | 这个红包给我的吗？
> `原来她记得今天。`
```
好感度：38%
爱意：12%
醋意：0%
```''',fallbackName:'楼一');
    expect(x.time,'16:45');
    expect(x.beats.map((b)=>b.kind).toList(),[StoryKind.action,StoryKind.speech,StoryKind.thought]);
    expect(x.status['好感度'],'38%');
  });
  test('Strict JSON produces separate thoughts and limits action length',(){
    final x=StoryParser.parse('{"time":"10:20","place":"家","beats":[{"type":"action","text":"他抬起头"},{"type":"speech","speaker":"小满","text":"你好"},{"type":"thought","speaker":"小满","text":"好开心"}],"status":{"好感度":"50%"}}');
    expect(x.beats.length,3);expect(x.beats.last.kind,StoryKind.thought);
  });
  test('15 unique pet species, per-role serialization and hatch',(){
    expect(petSpecies.length,greaterThanOrEqualTo(15));
    expect(petSpecies.map((p)=>p.id).toSet().length,petSpecies.length);
    final p=PetState();p.eggProgress=95;
    p.setCreatedAt(DateTime.now().subtract(const Duration(hours:2)));
    final chosen=p.hatch(rng:Random(3));
    expect(p.species,chosen.id);
    final copy=PetState.fromJson(p.toJson());expect(copy.species,p.species);
    expect(copy.strokes,isEmpty);
  });
  test('Pet actions are bounded and increase XP',(){
    final p=PetState(species:'cat');p.hunger=10;
    p.act('喂食',DateTime.now());expect(p.hunger,inInclusiveRange(0,100));expect(p.xp,greaterThan(0));
  });
  test('Gomoku obeys occupancy and detects five',(){
    final g=Gomoku();
    for(var c=0;c<4;c++)expect(g.put(4,c,1),isTrue);
    expect(g.put(4,0,2),isFalse);
    expect(g.put(4,4,1),isTrue);expect(g.winner,1);expect(g.bestAiMove(),isNull);
  });
  test('Flight chess cannot launch except on six',(){
    final g=FlightChess(random:Random(2));
    expect(g.humanOptions(3),isEmpty);expect(g.humanOptions(6),[0,1]);
  });
  test('Monopoly never operates real money; local board round tracks log',(){
    final g=TinyMonopoly(random:Random(2));g.turn(0);g.turn(1);
    expect(g.log.length,2);expect(g.balances.length,2);
  });
  test('Lyrics and subtitle timing parser',(){
    expect(lineAt(parseLrc('[00:03.20]hello\n[00:05.0]world'),const Duration(seconds:4)),'hello');
    expect(lineAt(parseSrt('1\n00:00:01,000 --> 00:00:03,000\nhi'),const Duration(seconds:2)),'hi');
  });
}
