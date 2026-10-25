#!/usr/bin/env python3
"""Check known retired photographic files and embedded GLB images.
This is a regression guard, not a general copyright/license validator.
Blender packed-image verification is recorded separately by the asset build.
"""
from pathlib import Path
import hashlib, json, struct, sys
ROOT = Path(__file__).resolve().parents[1]
RETIRED = {
    '5efdaa62897cb622ee700fe151d1228b976764957d08857f5d7eaec9bc334fc5': 'retired retailer photo',
    'd2694975c797208a55ce704c2c61ca03fa50f138dd19d094b9392c53931d1909': 'retired photographic logo bake',
}
def digest(data): return hashlib.sha256(data).hexdigest()
def audit():
    findings = []
    images = []
    for path in (ROOT / 'assets').rglob('*'):
        if not path.is_file(): continue
        data = path.read_bytes()
        if digest(data) in RETIRED:
            findings.append(str(path.relative_to(ROOT)))
        if path.suffix != '.glb': continue
        if data[:4] != b'glTF':
            findings.append('invalid GLB: ' + str(path)); continue
        chunks = {}; offset = 12
        while offset < len(data):
            size, kind = struct.unpack_from('<II', data, offset)
            chunks[kind] = data[offset+8:offset+8+size]; offset += 8+size
        document = json.loads(chunks[0x4E4F534A])
        binary = chunks.get(0x004E4942, b'')
        for image in document.get('images', []):
            if 'bufferView' not in image:
                findings.append('external image requires manual audit: ' + str(image)); continue
            view = document['bufferViews'][image['bufferView']]
            offset = view.get('byteOffset', 0)
            content = binary[offset:offset+view['byteLength']]
            sha = digest(content)
            images.append({'file': str(path.relative_to(ROOT)), 'name': image.get('name'), 'sha256': sha})
            if sha in RETIRED: findings.append(str(path.relative_to(ROOT)) + ': ' + RETIRED[sha])
    print(json.dumps({'passed': not findings, 'findings': findings, 'embedded_images': images}, indent=2))
    return 1 if findings else 0
if __name__ == '__main__': sys.exit(audit())
