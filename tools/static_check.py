#!/usr/bin/env python3
"""Basic local consistency checks when Flutter SDK is unavailable.
NOT a replacement for flutter analyze / flutter test / native builds.
"""
from pathlib import Path
import re
import yaml

base = Path(__file__).resolve().parents[1]
source_files = list((base / 'lib').glob('*.dart'))
assert len(source_files) >= 8
assert (base / 'test/api_contract_test.dart').exists()
pubspec = yaml.safe_load((base / 'pubspec.yaml').read_text('utf-8'))
assert pubspec['name'] == 'xinyu_os'
for package in ('http', 'flutter_secure_storage', 'file_picker', 'path_provider',
                'just_audio', 'archive', 'cryptography', 'android_id'):
    assert package in pubspec['dependencies'], package

for path in source_files:
    source = path.read_text('utf-8')
    for relative in re.findall(r"import '([^']+\.dart)';", source):
        if relative.startswith('package:'): continue
        assert (path.parent / relative).exists(), f'{path.name}: missing {relative}'
    assert source.count('class ') > 0, path

models = (base / 'lib/models.dart').read_text('utf-8')
api = (base / 'lib/api_client.dart').read_text('utf-8')
controller = (base / 'lib/app_controller.dart').read_text('utf-8')
assert "api_key_$profileId" in controller and 'FlutterSecureStorage' in controller
assert 'apiKey' not in re.search(r'Map<String, dynamic> toJson\(\) => \{\'id\': id, \'label\': label,(.*?)\}; // API Key',
                                   models, re.S).group(1)
assert 'followRedirects = false' in api
assert 'https' in api and 'HTTP $status' in api
assert 'await MultiModelApi.call(' in controller
assert "if (!c.allowMoments)" in controller
assert 'replied >= group.maxReplies' in controller
assert (base / 'lib/activation_service.dart').exists()
assert (base / 'lib/ui_activation.dart').exists()
activation = (base / 'lib/activation_service.dart').read_text('utf-8')
assert 'Ed25519().verify' in activation and "pieces[0] != 'XY2'" in activation
assert 'XinyuApp(controller: controller, activation: activation)' in (base / 'lib/main.dart').read_text('utf-8')
assert (base / 'lib/music_controller.dart').exists()
assert 'desktopIcons' in models and 'avatarPath' in models
assert 'parseSseText' in api and 'onText' in api
assert (base / '.github/workflows/android-build.yml').exists()
assert (base / '.github/workflows/ios-simulator-build.yml').exists()
print(f'PASS: {len(source_files)} 个 Dart 源码模块、依赖引用、密钥分离、HTTPS/重定向、')
print('      API 调用、群聊上限、朋友圈默认权限，以及 Android/iOS 构建流程结构。')
print('NOTE: 未执行 Flutter/Dart 编译器，不能证明 APK/IPA 可用。')
