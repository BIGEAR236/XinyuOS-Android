"""Run once from the ROOT of your current Flutter repo.
Only changes the display name; NEVER changes Android applicationId, package,
signing key, activation logic, or users' private data.
"""
from pathlib import Path
import re

root = Path.cwd()

def replace_existing(path, transform):
    file = root / path
    if not file.is_file():
        print('SKIP not found:', path)
        return
    original = file.read_text(encoding='utf-8')
    updated = transform(original)
    if updated != original:
        file.write_text(updated, encoding='utf-8')
        print('UPDATED:', path)
    else:
        print('NO CHANGE:', path)

replace_existing('lib/main.dart', lambda s:
    s.replace("title: '心屿 OS'", "title: '小雨机'")
     .replace('title: "心屿 OS"', 'title: "小雨机"'))

# Main manifest label may be a direct string OR an @string/app_name reference.
manifest = root / 'android/app/src/main/AndroidManifest.xml'
if manifest.is_file():
    old = manifest.read_text(encoding='utf-8')
    new = re.sub(r'(android:label\s*=\s*[\"\'])(?!@string/)[^\"\']+([\"\'])',
                 r'\g<1>小雨机\g<2>', old, count=1)
    if new != old:
        manifest.write_text(new, encoding='utf-8')
        print('UPDATED Android launcher label')
    else:
        print('Android label might reference a string resource; checking strings.xml')
else:
    print('SKIP manifest missing')

replace_existing('android/app/src/main/res/values/strings.xml',
                 lambda s: re.sub(r'(<string\s+name=[\"\']app_name[\"\']\s*>)[^<]*(</string>)',
                                   r'\g<1>小雨机\g<2>', s, count=1))
print('Check AndroidManifest.xml application android:label equals 小雨机 or @string/app_name.')
print('Do NOT change Android applicationId or signing: that would prevent overlay install.')
