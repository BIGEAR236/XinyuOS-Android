#!/usr/bin/env python3
"""Run after `flutter create --platforms=android,ios ... .`.
Patches generated native projects for the app's secure HTTPS and permissions policy.
Safe to execute repeatedly.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
manifest = root / 'android/app/src/main/AndroidManifest.xml'
if manifest.exists():
    text = manifest.read_text('utf-8')
    if 'android.permission.INTERNET' not in text:
        text = text.replace('<application',
                            '    <uses-permission android:name="android.permission.INTERNET" />\n    <application', 1)
    text = re.sub(r'android:label="[^"]+"', 'android:label="心屿 OS"', text, count=1)
    for attr, val in [('android:allowBackup', 'false'),
                      ('android:usesCleartextTraffic', 'false'),
                      ('android:fullBackupContent', 'false')]:
        if attr not in text:
            text = text.replace('<application', f'<application {attr}="{val}"', 1)
    manifest.write_text(text, encoding='utf-8')
    for name in ['build.gradle.kts', 'build.gradle']:
        gradle = root / 'android/app' / name
        if gradle.exists():
            source = gradle.read_text('utf-8')
            source = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion',
                            'minSdk = 24', source)
            source = source.replace('minSdkVersion flutter.minSdkVersion',
                                    'minSdkVersion 24')
            gradle.write_text(source, encoding='utf-8')
    print('✓ Android 已设置 HTTPS 网络权限、禁用明文通信和系统自动备份。')
else:
    print('! Android 工程不存在：请先运行 flutter create --platforms=android,ios .')

podfile = root / 'ios/Podfile'
if podfile.exists():
    text = podfile.read_text('utf-8')
    text = re.sub(r"(?m)^\s*#?\s*platform\s+:ios\s*,\s*['\"]\d+\.\d+['\"]",
                  "platform :ios, '14.0'", text)
    if not re.search(r'(?m)^platform :ios,', text):
        text = "platform :ios, '14.0'\n" + text
    podfile.write_text(text, encoding='utf-8')

project = root / 'ios/Runner.xcodeproj/project.pbxproj'
if project.exists():
    text = project.read_text('utf-8')
    text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET\s*=\s*[\d.]+\s*;',
                  'IPHONEOS_DEPLOYMENT_TARGET = 14.0;', text)
    project.write_text(text, encoding='utf-8')

plist = root / 'ios/Runner/Info.plist'
if plist.exists():
    text = plist.read_text('utf-8')
    text = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
                  r'\g<1>心屿 OS\g<2>', text)
    if '<key>CFBundleDisplayName</key>' not in text:
        text = text.replace('</dict>',
                            '  <key>CFBundleDisplayName</key>\n  <string>心屿 OS</string>\n</dict>', 1)
    plist.write_text(text, encoding='utf-8')
    print('✓ iOS 已设置 14.0 最低版本和应用名称；设备安装仍需 Xcode 签名。')
else:
    print('! iOS 工程不存在：需在安装 Flutter 的电脑上执行 flutter create。')
