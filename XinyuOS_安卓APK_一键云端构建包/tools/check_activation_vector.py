from pathlib import Path
import base64, json
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
v=json.loads((Path(__file__).resolve().parents[1]/'test_vectors/activation_test_vector.json').read_text('utf-8'))
parts=v['code'].split('.')
def decode(s):return base64.urlsafe_b64decode(s+'='*((4-len(s)%4)%4))
key=Ed25519PublicKey.from_public_bytes(base64.b64decode(v['publicKeyBase64']))
key.verify(decode(parts[2]), ('XY1.'+parts[1]).encode())
payload=json.loads(decode(parts[1]))
assert payload['d']==v['device']
try:
 key.verify(decode(parts[2]),('XY1.'+parts[1]+'x').encode())
 raise AssertionError('Tampered signature accepted')
except Exception as e:
 if isinstance(e,AssertionError):raise
print('PASS: valid signature, correct device, tamper rejection')
