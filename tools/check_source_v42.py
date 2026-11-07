from pathlib import Path
import re,sys,os
root=Path(__file__).resolve().parents[1] / 'lib'
errors=[]
for p in root.rglob('*.dart'):
 s=p.read_text()
 # simple structural scanner, skips quoted strings (including raw, triple) + comments.
 stack=[]; i=0; line=1; state='code'; start_line=1
 while i<len(s):
  c=s[i];n=s[i+1:i+2]
  if c=='\n':line+=1
  if state=='line':
   if c=='\n':state='code'
  elif state=='block':
   if s[i:i+2]=='*/':state='code';i+=1
  elif state.startswith('str'):
   quote=state.split(':')[1];triple=state.endswith(':3')
   if c=='\\':i+=1
   elif triple and s[i:i+3]==quote*3:state='code';i+=2
   elif not triple and c==quote:state='code'
  else:
   if s[i:i+2]=='//':state='line';i+=1
   elif s[i:i+2]=='/*':state='block';i+=1
   elif c in "'\"":
    if s[i:i+3]==c*3:state=f'str:{c}:3';i+=2
    else:state=f'str:{c}:1'
   elif c in '({[':stack.append((c,line))
   elif c in ')}]':
    if not stack or {'}':'{',')':'(',']':'['}[c]!=stack[-1][0]:
     errors.append(f'{p.relative_to(root)}:{line}: unexpected {c}, stack last {stack[-1] if stack else None}')
    else:stack.pop()
  i+=1
 if stack:errors.append(f'{p.relative_to(root)}: unclosed {stack[-5:]}')
 if state.startswith('str'):errors.append(f'{p.relative_to(root)}: unclosed string')

for required in ['app_controller.dart','ui_chat.dart','ui_extras.dart','ui_shell.dart',
 'v40/marketplace_page.dart','v41/chat_more_panel.dart','v41/digital_person_page.dart',
 'v41/digital_call_page.dart','v41/owned_gift_page.dart','v42/product_illustration.dart',
 'v42/animated_portrait.dart','v42/moment_photo_store.dart']:
 if not (root/required).is_file(): errors.append('missing file: '+required)

controller=(root/'app_controller.dart').read_text()
assert "String roleChatMode" in controller
assert "imagePath: imagePath" in controller
assert "'🎁虚拟礼物卡:$sku|$productName'" in controller
assert "coverPath:draft.coverPath" in (root/'ui_chat.dart').read_text()
assert '🎁虚拟礼物卡:' in (root/'ui_chat.dart').read_text()
assert "已加 ${_cart[p.id]}" in (root/'v40/marketplace_page.dart').read_text()
assert "FutureBuilder<String>(future:XyMomentPhotoStore.get" in (root/'ui_extras.dart').read_text()
assert 'speech_to_text' in (root/'v41/digital_call_page.dart').read_text()
assert 'XyAnimatedPortrait' in (root/'v41/digital_person_page.dart').read_text()
assert not errors, '\n'.join(errors)
print(f'Static structural source checks PASSED on {len(list(root.rglob("*.dart")))} Dart files. No Flutter compiler run.')
