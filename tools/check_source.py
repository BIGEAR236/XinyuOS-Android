#!/usr/bin/env python3
"""Cheap offline consistency checks, NOT a replacement for flutter analyze/test."""
import re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
errors=[]
for p in (root/'lib').rglob('*.dart'):
    source=p.read_text(encoding='utf8')
    for ref in re.findall(r"import\s+['\"]([^'\"]+\.dart)['\"]\s*;",source):
        if ref.startswith('package:') or ref.startswith('dart:'):continue
        if not (p.parent/ref).resolve().exists():errors.append(f'{p.relative_to(root)}: missing {ref}')
needed={
    'lib/main.dart','lib/core/companion.dart','lib/core/pet_engine.dart',
    'lib/core/game_engines.dart','lib/core/story_parser.dart',
    'lib/core/storage.dart','lib/core/media_engine.dart',
    'lib/pages/hub_page.dart','lib/pages/pet_page.dart','lib/pages/game_page.dart',
    'lib/pages/media_page.dart','lib/pages/story_page.dart',
    'lib/widgets/pet_art.dart','lib/widgets/chat_overlay.dart',
    'test/companion_engines_test.dart','pubspec.yaml',
}
for rel in needed:
    if not (root/rel).exists():errors.append(f'missing {rel}')
s=(root/'lib/core/pet_engine.dart').read_text()
ids=re.findall(r"PetSpecies\('([^']+)'",s)
if len(ids)<15 or len(ids)!=len(set(ids)):errors.append(f'pet species unique count = {len(ids)}')
if errors:
    print('\n'.join('ERROR: '+e for e in errors))
    raise SystemExit(1)
print(f'Passed: {len(needed)} required paths, {len(ids)} pet species, local Dart imports resolved.')
print('Flutter SDK checks are still required: flutter pub get && flutter analyze && flutter test')
