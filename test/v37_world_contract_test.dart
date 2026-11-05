import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/api_client.dart';
import 'package:xinyu_os/local_tools.dart';
import 'package:xinyu_os/models.dart';
import 'package:xinyu_os/request_gate.dart';

void main() {
  test('cancelled request cannot mutate a newer generation', () {
    final gate=RequestGate();
    final first=gate.start('private:1');
    expect(gate.isCurrent('private:1',first),true);
    gate.cancel('private:1');
    expect(gate.isCurrent('private:1',first),false);
    final second=gate.start('private:1');
    expect(gate.isCurrent('private:1',second),true);
    expect(gate.isCurrent('private:1',first),false);
    expect(gate.start('group:1'),1);
  });

  test('device clock is explicit and has weekday and UTC offset', () {
    final now=DateTime(2026,11,5,18,22);
    final text=MultiModelApi.clockContext(now);
    expect(text,contains('2026-11-05'));
    expect(text,contains('周四'));
    final prompt=MultiModelApi.systemPrompt('角色设定',roleName:'小满',
      now:now,chatMode:'story',formatMode:'markdown');
    expect(prompt,contains('2026-11-05'));
    expect(prompt,contains('Markdown'));
    expect(prompt,contains('沉浸剧情'));
  });

  test('structured output wins over roleplay formatting defaults', () {
    final profile=ApiProfile(id:'p', label:'relay',provider:'custom',
      baseUrl:'https://relay.example/v1',modelId:'test-model',streaming:false);
    final req=MultiModelApi.buildRequest(profile:profile,apiKey:'test',
      persona:'长篇戏剧', roleName:'小满',formatMode:'json',
      turns:[const ModelTurn('user','按JSON输出')]);
    final msgs=req.payload['messages'] as List;
    final sys=msgs.first['content'] as String;
    expect(sys,contains('严格合法的 JSON'));
    expect(sys,contains('用户明确提出的输出结构'));
  });

  test('offline tools never call a remote model', () {
    expect(LocalTools.run('/calc 6*7',DateTime.now()),contains('42'));
    expect(LocalTools.run('/calc 6/0',DateTime.now()),contains('零'));
    expect(LocalTools.run('/time',DateTime.utc(2026,11,5)),contains('2026'));
    expect(LocalTools.run('普通消息',DateTime.now()),isNull);
  });

  test('V3.6 state migrates to virtual world safely', () {
    final j=AppData.initial().toJson();
    for(final key in ['threadFormats','worldBalance','worldLedger','worldPet',
      'worldOrders','worldEvents','worldCart','lastWatchPath',
      'autoMomentPosting','autoMomentEveryHours','lastAiPostAt']) {
      j.remove(key);
    }
    final data=AppData.fromJson(j);
    expect(data.worldBalance,1200);
    expect(data.autoMomentPosting,false);
    expect(data.worldPet.name,'团团');
    expect(data.worldOrders,isEmpty);
    expect(data.desktopOrder,contains('world'));
  });

  test('virtual balances, pet, orders, comments and format survive JSON', () {
    final data=AppData.initial();
    data.worldBalance=842;
    data.threadFormats={'private:a':'json'};
    data.worldPet=VirtualPet(name:'雪球',hunger:60,happiness:80);
    data.worldLedger=[VirtualLedgerEntry(id:'l', createdAt:DateTime(2026,11,5),
      delta:-22,description:'虚拟红包',characterId:'sample_xiaoman')];
    data.worldOrders=[VirtualOrder(id:'o',createdAt:DateTime(2026,11,5),
      title:'星星小夜灯',count:1,total:72)];
    data.worldCart={'food':2};
    data.worldEvents=[WorldEvent(id:'e',createdAt:DateTime(2026,11,5),
      kind:'pet',description:'一起照顾宠物')];
    data.lastAiPostAt={'sample_xiaoman':'2026-11-05T12:00:00'};
    final restored=AppData.fromJson(mapJson(jsonDecode(data.serialize())));
    expect(restored.worldBalance,842);
    expect(restored.threadFormats['private:a'],'json');
    expect(restored.worldPet.name,'雪球');
    expect(restored.worldLedger.single.delta,-22);
    expect(restored.worldOrders.single.total,72);
    expect(restored.worldEvents.single.kind,'pet');
    expect(restored.worldCart['food'],2);
    expect(restored.lastAiPostAt['sample_xiaoman'],isNotNull);
  });

  test('virtual shop has unique identifiers, nonzero prices', () {
    expect(virtualShop.map((e)=>e.id).toSet().length,virtualShop.length);
    expect(virtualShop.every((i)=>i.cost>0),true);
  });
}
