#!/usr/bin/env python3
"""Restore the signing keystore from one GitHub Actions secret; never log it."""
import os, json, base64, pathlib, sys
raw = os.environ.get('XY_RELEASE_SIGNING_BUNDLE','').strip()
if not raw:
    sys.exit('没有配置 GitHub Actions 仓库机密 XY_RELEASE_SIGNING_BUNDLE；已停止构建，绝不使用不稳定的临时签名。')
try:
    data=json.loads(base64.b64decode(raw,validate=True).decode('utf-8'))
    key=base64.b64decode(data['keystore'],validate=True)
    assert len(key)>1000
    for name in ['alias','storePassword','keyPassword']:
        assert isinstance(data[name],str) and len(data[name])>=5
        assert '\n' not in data[name] and '\r' not in data[name]
except Exception as ex:
    raise SystemExit('签名密钥配置内容无法解析，已停止构建（不会回退到 debug 签名）。') from ex
path=pathlib.Path('android/app/release-signing.jks')
path.write_bytes(key)
path.chmod(0o600)
# Env values are never printed to the log.
for val in [data['storePassword'],data['keyPassword']]:
    print(f'::add-mask::{val}')
with open(os.environ['GITHUB_ENV'],'a',encoding='utf-8') as f:
    f.write(f"XY_KEY_ALIAS={data['alias']}\nXY_STORE_PASSWORD={data['storePassword']}\nXY_KEY_PASSWORD={data['keyPassword']}\n")
print('已恢复稳定的正式 APK 签名证书。')
