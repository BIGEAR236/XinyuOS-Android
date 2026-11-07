import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/v43/red_packet_presenter.dart';

void main() {
  test('new red packet shows blessing only and never an amount', () {
    final view = XyRedPacketPresenter.blessing('🧧 虚拟红包 祝你每天都有小惊喜');
    expect(view, '祝你每天都有小惊喜');
    expect(view.contains('20'), false);
    expect(view.contains('星币'), false);
  });

  test('old red packet custom cover and amount stay hidden', () {
    final view = XyRedPacketPresenter.blessing(
      '🧧 虚拟红包 20 星币：我的自定义封面 · 祝你每天都有小惊喜');
    expect(view, '祝你每天都有小惊喜');
  });

  test('old preset covers stay hidden', () {
    expect(XyRedPacketPresenter.blessing(
      '🧧 虚拟红包 50 星币：星空心愿 · 永远开心'), '永远开心');
  });

  test('a blank blessing gets a neutral greeting', () {
    expect(XyRedPacketPresenter.blessing('🧧 虚拟红包 '), '恭喜发财，大吉大利');
  });
}
