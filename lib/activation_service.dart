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

  /// Supports both the original XY1 JSON license and the compact XY2 binary
  /// license. The Ed25519 public key is unchanged so old activations survive.
  Future<String?> _verify(String code, {required bool commit}) async {
    try {
      final pieces = code.split('.');
      if (pieces.length != 3 || (pieces[0] != 'XY1' && pieces[0] != 'XY2')) {
        return '激活码格式不正确。请直接粘贴完整激活码。';
      }
      List<int> decodePart(String value) {
        final pad = List.filled((4 - value.length % 4) % 4, '=').join();
        return base64Url.decode(value + pad);
      }
      final publicKey = SimplePublicKey(base64Decode(publicKeyBase64),
          type: KeyPairType.ed25519);
      final signature = Signature(decodePart(pieces[2]), publicKey: publicKey);
      final genuine = await Ed25519().verify(
        utf8.encode('${pieces[0]}.${pieces[1]}'), signature: signature);
      if (!genuine) return '签名校验失败：这不是管理员签发的有效激活码。';
      String license;
      int expiry;
      String boundDevice;
      if (pieces[0] == 'XY1') {
        final decoded = jsonDecode(utf8.decode(decodePart(pieces[1])));
        if (decoded is! Map) return '旧版激活码内容无效。';
        final data = Map<String, dynamic>.from(decoded);
        if (data['v'] != 1 || data['id'] is! String || data['exp'] is! int) {
          return '旧版激活码字段无效。';
        }
        boundDevice = '${data['d'] ?? ''}';
        license = data['id'] as String;
        expiry = data['exp'] as int;
      } else {
        final bytes = decodePart(pieces[1]);
        // 1 version + 10 device bytes + 4 expiration bytes + 4 serial bytes.
        if (bytes.length != 19 || bytes[0] != 2) return '新版激活码数据长度无效。';
        final hex = bytes.sublist(1, 11)
            .map((value) => value.toRadixString(16).padLeft(2, '0'))
            .join().toUpperCase();
        boundDevice = 'XY-${List.generate(5, (i) => hex.substring(i * 4, i * 4 + 4)).join('-')}';
        expiry = (bytes[11] << 24) | (bytes[12] << 16) |
            (bytes[13] << 8) | bytes[14];
        final serial = bytes.sublist(15, 19)
            .map((value) => value.toRadixString(16).padLeft(2, '0'))
            .join().toUpperCase();
        license = 'XY2-$serial';
      }
      if (boundDevice != deviceCode) {
        return '激活码与本机设备编号不匹配，请联系邀请人重新领取。';
      }
      if (expiry < 0 || license.isEmpty) return '激活码字段无效。';
      final day = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;
      if (expiry != 0 && day > expiry) return '激活码已过期，请联系邀请人。';
      if (commit) await _storage.write(key: _storageKey, value: code);
      isActivated = true;
      licenseId = license;
      expiryDay = expiry;
      notifyListeners();
      return null;
    } catch (_) {
      return '无法读取激活码。请尝试用「一键粘贴」输入完整内容。';
    }
  }
}
