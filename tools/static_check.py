#!/usr/bin/env python3
"""Best-effort offline checks; NOT a Dart analyzer or Flutter build."""
from pathlib import Path
import re, sys
root=Path(__file__).resolve().parents[1]
darts=sorted(root.rglob('*.dart'))
assert len(darts)>=20, len(darts)

def delimiters(source):
    stack=[]; i=0; ln=1; n=len(source)
    while i<n:
        ch=source[i]
        if ch=='\n':ln+=1;i+=1;continue
        if source.startswith('//',i):
            j=source.find('\n',i)
            if j<0:break
            i=j;continue
        if source.startswith('/*',i):
            depth=1;i+=2
            while i<n and depth:
                if source.startswith('/*',i):depth+=1;i+=2
                elif source.startswith('*/',i):depth-=1;i+=2
                else:
                    if source[i]=='\n':ln+=1
                    i+=1
            continue
        # Dart raw and regular strings (both triple and single-quoted).
        if ch in "'\"" or (ch in 'rR' and i+1<n and source[i+1] in "'\"" and (i==0 or not(source[i-1].isalnum() or source[i-1]=='_'))):
            if ch in 'rR':i+=1;ch=source[i];raw=True
            else:raw=False
            tri=source.startswith(ch*3,i);i+=3 if tri else 1
            while i<n:
                if source[i]=='\n':ln+=1
                if not raw and source[i]=='\\':i+=2;continue
                if (tri and source.startswith(ch*3,i)) or (not tri and source[i]==ch):
                    i+=3 if tri else 1;break
                i+=1
            continue
        if ch in '({[': stack.append((ch,ln))
        elif ch in ')}]':
            if not stack or stack[-1][0]!=dict(zip(')}]','({['))[ch]:
                return f'line {ln}: unmatched {ch}, stack={stack[-4:]}'
            stack.pop()
        i+=1
    return f'unclosed: {stack[-4:]}' if stack else ''

bad=[]
for path in darts:
    err=delimiters(path.read_text())
    if err: bad.append(f'{path.relative_to(root)} {err}')
    for imp in re.findall(r"(?m)^\s*import\s+['\"](\.{1,2}/[^'\"]+)['\"]",path.read_text()):
        # the original repo has other intact files that aren't part of the patch.
        target=(path.parent/imp).resolve()
        if not target.exists() and str(target).startswith(str((root/'lib/v41').resolve())):
            bad.append(f'{path.relative_to(root)} missing new module import {imp}')
base=(root/'lib/v41/desktop_grid.dart').read_text()
assert base.count("'chat','api','music','video','settings','memo','diary','album'")==1
assert 'SliverGridDelegateWithFixedCrossAxisCount' in base
assert 'const SliverGridDelegateWithFixedCrossAxisCount' not in base
assert "dy: ((json['dy'] as num?) ?? .33).toDouble().clamp(0, 1).toDouble()" in (root/'lib/v41/avatar_core.dart').read_text()
assert "'voiceConsent': voiceConsent" in (root/'lib/v41/avatar_core.dart').read_text()
assert "roleChatMode" in (root/'lib/app_controller.dart').read_text()
assert "XyChatMorePanel.open" in (root/'lib/ui_chat.dart').read_text()
assert "XyDesktopGrid" in (root/'lib/ui_shell.dart').read_text()
if bad:
    print('Static issues:')
    for b in bad:print(' -',b)
    sys.exit(1)
print(f'PASS: {len(darts)} Dart sources: balanced tokens, v41 local imports, 8 desktop apps, digital defaults and chat entry references')
