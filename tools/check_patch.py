from pathlib import Path
root=Path(__file__).resolve().parent.parent
source={p.relative_to(root).as_posix():p.read_text(encoding='utf-8') for p in (root/'lib').rglob('*.dart')}
required=['lib/main.dart','lib/ui_shell.dart','lib/ui_extras.dart','lib/ui_proactive.dart',
          'lib/v39/desktop_icon_settings.dart','lib/v39/app_launch_care.dart',
          'lib/v39/font_import_policy.dart']
for path in required:
    assert path in source, f'Missing {path}'
for filename, needles in {
  'lib/main.dart':['DesktopIconScale.initialize()', 'PhoneHomeScreen(controller: controller)'],
  'lib/ui_shell.dart':['ValueListenableBuilder<double>', 'DesktopIconScale.current.value',
      'AppLaunchCarePrompt.checkAndShow(context, controller)','processDueEvents()'],
  'lib/ui_extras.dart':['const DesktopIconSizeDialog()',
      'FontImportPolicy.validate(','FontImportPolicy.maxBytes'],
  'lib/ui_proactive.dart':['打开 App 时弹出关怀提示'],
  'lib/v39/desktop_icon_settings.dart':['SharedPreferencesAsync','current.value = next'],
  'lib/v39/app_launch_care.dart':['class AppLaunchCarePrompt', 'await showDialog<bool>'],
}.items():
    for needle in needles:
        assert needle in source[filename], f'{filename} missing {needle}'
for f, code in source.items():
    for match in __import__('re').finditer(r"^import '(?:\.\./)?(v39/[^']+)';", code, __import__('re').M):
        assert (root/'lib'/match.group(1)).is_file(), f'{f}: {match.group(1)} missing'
print('PASS: 7 Dart files, 3 UI integrations, local v39 imports exist')
