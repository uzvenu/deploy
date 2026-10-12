"""Generate chart assets explicitly; validation never silently fixes drift."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
source = root.parent / 'agent/services/image-service'
assets = root / 'charts/image-service/files'
for name in ('seccomp-amd64.json', 'LICENSE.moby'):
    if sys.argv[1:] == ['--sync']:
        shutil.copyfile(source / name, assets / name)
    assert (source / name).read_bytes() == (assets / name).read_bytes(), f'{name}: run python3 tests/image-service-profile.py --sync'
subprocess.run(['python3', str(source / 'test-seccomp.py')], check=True)
profile = (assets / 'seccomp-amd64.json').read_bytes()
assert json.loads(profile)['defaultAction'] == 'SCMP_ACT_ERRNO'
print('codex-image-service/' + hashlib.sha256(profile).hexdigest() + '.json')
