import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:android_id/android_id.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Only the *public* verification key lives in the distributed APK.
/// The private issuing key stays in the developer-only offline admin tool.
class ActivationService extends ChangeNotifier {
  static const String publicKeyBase64 = 'H9PdnTZUtLrw5M1AXwLdqMdD8ODOo9fY92UsQBkKd70=';
  static const String _storageKey = 'xinyuos_activation_v1';
  final FlutterSecureStorage _storage;
  final String deviceCode;
  bool isActivated = false;
  String? licenseId;
  int? expiryDay;

  ActivationService._(this._storage, this.deviceCode);

  static Future<ActivationService> create() async {
    const storage = FlutterSecureStorage();
    String fingerprintSource;
    if (Platform.isAndroid) {
      final androidId = await const AndroidId().getId();
      if (androidId == null || androidId.isEmpty) {
        throw const FormatException('读取设备编号失败，请确认 Android 系统正常。');
      }
      fingerprintSource = 'xinyuos-android-v1|$androidId';
    } else {
      // Future iOS support: a private installation identifier stored in Keychain.
      // Not as persistent as an Android scoped identifier after reinstall.
      var instanceId = await storage.read(key: 'xinyuos_install_id_v1');
      if (instanceId == null || instanceId.isEmpty) {
        final random = Random.secure();
        instanceId = List.generate(24, (_) => random.nextInt(256))
            .map((v) => v.toRadixString(16).padLeft(2, '0')).join();
        await storage.write(key: 'xinyuos_install_id_v1', value: instanceId);
      }
      fingerprintSource = 'xinyuos-ios-v1|$instanceId';
    }
    final hash = await Sha256().hash(utf8.encode(fingerprintSource));
    final hex = hash.bytes.map((n) => n.toRadixString(16).padLeft(2, '0'))
        .join().substring(0, 20).toUpperCase();
    final parts = List.generate(5, (i) => hex.substring(i * 4, i * 4 + 4));
    final activation = ActivationService._(storage, 'XY-${parts.join('-')}');
    final saved = await storage.read(key: _storageKey);
    if (saved != null) await activation._verify(saved, commit: false);
    return activation;
  }

  /// The same check runs when a code is entered and every time the app opens.
  Future<String?> activate(String rawCode) async {
    final code = rawCode.trim().replaceAll(RegExp(r'\s+'), '');
    final message = await _verify(code, commit: true);
    return message;
  }

  Future<String?> _verify(String code, {required bool commit}) async {
    try {
      final pieces = code.split('.');
      if (pieces.length != 3 || pieces[0] != 'XY1') {
        return '激活码格式不正确，请重新复制完整激活码。';
      }
      List<int> decodePart(String value) {
        final pad = List.filled((4 - value.length % 4) % 4, '=').join();
        return base64Url.decode(value + pad);
      }
      final message = utf8.encode('XY1.${pieces[1]}');
      final decoded = jsonDecode(utf8.decode(decodePart(pieces[1])));
      if (decoded is! Map) return '激活码内容无效。';
      final payload = Map<String, dynamic>.from(decoded);
      final publicKey = SimplePublicKey(base64Decode(publicKeyBase64),
          type: KeyPairType.ed25519);
      final signature = Signature(decodePart(pieces[2]), publicKey: publicKey);
      final genuine = await Ed25519().verify(message, signature: signature);
      if (!genuine) return '激活码签名无效，不是管理员签发的有效激活码。';
      if (payload['v'] != 1 || payload['d'] != deviceCode) {
        return '此激活码属于其他设备，请发送本机设备编号重新领取。';
      }
      final id = payload['id'];
      final expiry = payload['exp'];
      if (id is! String || id.isEmpty || expiry is! int || expiry < 0) {
        return '激活码字段不正确。';
      }
      final today = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;
      if (expiry != 0 && today > expiry) return '激活码已过期，请联系邀请人续期。';
      if (commit) await _storage.write(key: _storageKey, value: code);
      isActivated = true;
      licenseId = id;
      expiryDay = expiry;
      notifyListeners();
      return null;
    } catch (_) {
      return '激活码无法读取或校验失败，请复制完整激活码。';
    }
  }
}
