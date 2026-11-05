import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinyu_os/activation_service.dart';

void main() {
  test('内置公钥可验证内测激活签名测试向量', () async {
    // This fixture carries no secret private key.
    const body = 'eyJ2IjoxLCJkIjoiWFktMTIzNC1BQkNELTU2NzgtRUYwMS0yMzQ1IiwiaWQiOiJURVNUVkVDVE9SIiwiZXhwIjowfQ';
    const signatureB64 = 'EakvaOlAvmwBlFRKBhdiCObULKUyUjlKxD_6y_5TiCWG7nnou2cGvrO6jwrnF50knWWIWaV4i0oX29yhxaYsDg';
    final pub = SimplePublicKey(base64Decode(ActivationService.publicKeyBase64),
      type: KeyPairType.ed25519);
    String padded(String s) => s + List.filled((4 - s.length % 4) % 4, '=').join();
    expect(await Ed25519().verify(utf8.encode('XY1.$body'),
      signature: Signature(base64Url.decode(padded(signatureB64)), publicKey: pub)), isTrue);
    expect(await Ed25519().verify(utf8.encode('XY1.${body}X'),
      signature: Signature(base64Url.decode(padded(signatureB64)), publicKey: pub)), isFalse);
    final payload = jsonDecode(utf8.decode(base64Url.decode(padded(body)))) as Map;
    expect(payload['d'], 'XY-1234-ABCD-5678-EF01-2345');
  });
}
