import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/intimacy/core/pet_engine.dart';
import 'package:xinyu_os/v39/chat_extras.dart';

void main() {
  test('30 species split into white 15, green 10, gold 4, red 1', () {
    expect(petSpecies.length, 30);
    final counts = <String, int>{};
    for (final species in petSpecies) {
      counts.update(species.rarity, (count) => count + 1, ifAbsent: () => 1);
    }
    expect(counts, {'white': 15, 'green': 10, 'gold': 4, 'red': 1});
    expect(petSpecies.map((s) => s.id).toSet().length, 30);
    expect(rarityOdds.values.fold<int>(0, (sum, value) => sum + value), 100);
  });

  test('care earns rewards only once per real hour', () {
    final pet = PetState();
    final now = DateTime(2026, 11, 6, 12);
    expect(pet.canInteract(now), isTrue);
    pet.act('讲故事', now);
    final progress = pet.eggProgress;
    final attempts = pet.interactionCount;
    pet.act('讲故事', now.add(const Duration(minutes: 59)));
    expect(pet.eggProgress, progress);
    expect(pet.interactionCount, attempts);
    pet.act('讲故事', now.add(const Duration(hours: 1)));
    expect(pet.interactionCount, attempts + 1);
  });

  test('hatching needs 24 hours, 6 care actions and 80 progress', () {
    final pet = PetState();
    final now = DateTime.now();
    pet.eggProgress = 95;
    pet.interactionCount = 6;
    pet.setCreatedAt(now.subtract(const Duration(hours: 23)));
    expect(pet.canHatchAt(now), isFalse);
    pet.setCreatedAt(now.subtract(const Duration(hours: 25)));
    expect(pet.canHatchAt(now), isTrue);
    final species = pet.hatch(rng: Random(16));
    expect(pet.species, species.id);
    expect(pet.strokes, isEmpty);
    final old = PetState.fromJson(pet.toJson());
    expect(old.level, pet.level);
    expect(old.species, pet.species);
  });

  test('2 or 3 bubbles use one result and preserve natural sentences', () {
    const text = '今天见到你真的很开心。我们一起走过了湖边的那条小路。下次还想和你一起看夕阳。';
    expect(ReplySegmenter.split(text, 1).length, 1);
    expect(ReplySegmenter.split(text, 2).length, 2);
    expect(ReplySegmenter.split(text, 3).length, 3);
    expect(ReplySegmenter.split(text, 3).join(), text);
    expect(VirtualGiftOffer.parse(ReplySegmenter.split('今天有礼物送给你，记得收好啊。\n[虚拟红包:20]', 2).last), isNotNull);
    expect(ReplySegmenter.split('**16:45** | 湖边\n`抬头`', 3).length, 1);
  });

  test('gift tokens have strict amounts and end-of-message anchoring', () {
    expect(VirtualGiftOffer.parse('今天给你一个惊喜！\n[虚拟红包:20]')!.coins, 20);
    expect(VirtualGiftOffer.parse('[虚拟礼物:玫瑰]')!.name, '玫瑰');
    expect(VirtualGiftOffer.parse('[虚拟红包:999]'), isNull);
    expect(VirtualGiftOffer.parse('文字中[虚拟红包:20]并非可领标记'), isNull);
  });
}
