import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/v41/avatar_core.dart';
import 'package:xinyu_os/v41/desktop_grid.dart';
import 'package:xinyu_os/v40/catalog.dart';

void main() {
  test('digital person starts disabled and has independent service endpoints', () {
    final profile=DigitalPersonConfig('role-001');
    expect(profile.enabled,false);
    expect(profile.voiceConsent,false);
    expect(profile.imageEndpoint,'');
    expect(profile.sttEndpoint,'');
    expect(profile.ttsEndpoint,'');
    expect(profile.voiceId,'');
    profile.enabled=true;
    profile.portraitGallery=['/tmp/a.png','/tmp/b.png'];
    profile.voiceSamples=['/tmp/example.wav'];
    final restored=DigitalPersonConfig.fromJson(profile.roleId,profile.toJson());
    expect(restored.enabled,true);
    expect(restored.portraitGallery.length,2);
    expect(restored.voiceSamples.length,1);
    expect(restored.voiceConsent,false);
  });
  test('desktop has only intended eight modules and 12 blank locations', () {
    final slots=XyDesktopSlots.defaultSlots();
    expect(slots.length,20);
    expect(slots.where((key)=>key.isNotEmpty).toSet(),XyDesktopSlots.visible.toSet());
    expect(slots.where((key)=>key.isEmpty).length,12);
    for(final removed in ['world','wallet','pet','shop','watch']){
      expect(slots.contains(removed),false);
    }
  });
  test('previous 300 virtual shop products remain in the catalog', () {
    expect(xyProducts.length,300);
  });
}
