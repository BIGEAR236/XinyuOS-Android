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
    # Microphone access for the V4.1 digital-person voice rounds (record plugin).
    if 'android.permission.RECORD_AUDIO' not in text:
        text = text.replace('<application',
            '    <uses-permission android:name="android.permission.RECORD_AUDIO" />\n    <application', 1)
    # V4.2 小雨机: launcher display name only; applicationId / signing stay untouched.
    text = re.sub(r'android:label="[^"]+"', 'android:label="小雨机"', text, count=1)
    # V4.2 speech_to_text + flutter_tts need package visibility for on-device
    # speech recognition and TTS services (Android 11+). Keep exactly one <queries>.
    if 'android.speech.RecognitionService' not in text:
        text = text.replace('<application',
            '    <queries>\n'
            '        <intent>\n'
            '            <action android:name="android.speech.RecognitionService" />\n'
            '        </intent>\n'
            '        <intent>\n'
            '            <action android:name="android.intent.action.TTS_SERVICE" />\n'
            '        </intent>\n'
            '    </queries>\n'
            '    <application', 1)
    # Local, inexact event notifications; no exact-alarm permission required.
    if 'android.permission.RECEIVE_BOOT_COMPLETED' not in text:
        text = text.replace('<application',
            '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />\n    <application', 1)
    if 'ScheduledNotificationReceiver' not in text:
        receivers = '''
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
          <intent-filter>
            <action android:name="android.intent.action.BOOT_COMPLETED" />
            <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            <action android:name="android.intent.action.QUICKBOOT_POWERON" />
            <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
          </intent-filter>
        </receiver>
'''
        text = text.replace('</application>', receivers + '\n    </application>', 1)

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
            # flutter_local_notifications uses java.time on old Android;
            # enable core library desugaring in the generated project.
            if name == 'build.gradle.kts':
                if 'isCoreLibraryDesugaringEnabled' not in source:
                    source = source.replace('compileOptions {',
                        'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
                if 'coreLibraryDesugaring(' not in source:
                    source += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
            else:
                if 'coreLibraryDesugaringEnabled' not in source:
                    source = source.replace('compileOptions {',
                        'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
                if 'coreLibraryDesugaring ' not in source:
                    source += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
            gradle.write_text(source, encoding='utf-8')
    settings = root / 'android/settings.gradle.kts'
    if settings.exists():
        text = settings.read_text('utf-8')
        if 'maven.aliyun.com' not in text:
            # Mirror FIRST: aliyun serves artifacts directly. Maven Central
            # may redirect some large artifacts (e.g. kotlin-compiler-
            # embeddable) to GitHub releases, which is unreliable.
            mirror = ('        maven { url = uri("https://maven.aliyun.com/repository/public") }\n'
                      '        maven { url = uri("https://maven.aliyun.com/repository/google") }\n')
            text = text.replace('repositories {', 'repositories {\n' + mirror)
            settings.write_text(text, encoding='utf-8')
            print('✓ Gradle 仓库已前置阿里云镜像（直供构件，避开 GitHub 重定向）。')
        else:
            print('✓ Gradle 仓库镜像已配置。')
    icons = root / 'android_icons'
    res = root / 'android/app/src/main/res'
    if icons.is_dir() and res.is_dir():
        import shutil
        for item in icons.iterdir():
            if item.is_dir():
                shutil.copytree(item, res / item.name, dirs_exist_ok=True)
        print('✓ 已应用自定义安卓启动器图标（adaptive + legacy）。')
    print('✓ Android 已设置 HTTPS 网络权限、麦克风权限、语音服务可见性（queries）和应用显示名。')
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

# Keep the iOS display name consistent with the V4.2 小雨机 rebrand.
plist = root / 'ios/Runner/Info.plist'
if plist.exists():
    text = plist.read_text('utf-8')
    text = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)',
                  r'\g<1>小雨机\g<2>', text)
    if '<key>CFBundleDisplayName</key>' not in text:
        text = text.replace('</dict>',
                            '  <key>CFBundleDisplayName</key>\n  <string>小雨机</string>\n</dict>', 1)
    plist.write_text(text, encoding='utf-8')
    print('✓ iOS 已设置 14.0 最低版本和应用名称；设备安装仍需 Xcode 签名。')
else:
    print('! iOS 工程不存在：需在安装 Flutter 的电脑上执行 flutter create。')
