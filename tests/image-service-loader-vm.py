"""Disposable KVM/cloud-init validation; no SSH, credentials or host policy writes.

Requires qemu-system-x86_64, qemu-img, genisoimage and a downloaded Ubuntu cloud
image. VM apt downloads require network. Export the tested service image as
image.tar with tag codex-image-service:apparmor-loader into an EMPTY workdir.
Only this disposable VM's kernel policy and disk are modified.
"""
from pathlib import Path
import argparse
import subprocess
import json
import hashlib
import time

args = argparse.ArgumentParser(description=__doc__)
args.add_argument('--cloud-image', required=True, type=Path)
args.add_argument('--workdir', required=True, type=Path)
args.add_argument('--timeout', type=int, default=900)
options = args.parse_args()
root = Path(__file__).resolve().parents[1]
work = options.workdir.resolve()
image = options.cloud_image.resolve(strict=True)
if not (work / 'image.tar').is_file():
 raise SystemExit('Export tested image.tar into the workdir first')
if (work / 'disk.qcow2').exists():
 raise SystemExit('Use a fresh workdir: refusing to modify an existing VM disk')
for name in ['apparmor.profile','load-apparmor.cjs','seccomp-amd64.json']:
 (work/name).write_bytes((root/'charts/image-service/files'/name).read_bytes())
h=hashlib.sha256((work/'apparmor.profile').read_bytes()).hexdigest()
script='''#!/bin/bash
set -euxo pipefail
mkdir -p /shared /var/lib/kubelet/seccomp/codex-image-service
mount -t 9p -o trans=virtio,version=9p2000.L share /shared
exec > /shared/results.log 2>&1
trap 'dmesg | grep -E "apparmor=.*codex-image-service|DENIED" || true' EXIT
if ! command -v docker; then apt-get update; apt-get install -y docker.io apparmor; fi
uname -r
systemctl start docker
docker load -i /shared/image.tar
mkdir -p /source
cp /shared/apparmor.profile /shared/load-apparmor.cjs /source/
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --entrypoint /usr/sbin/apparmor_parser codex-image-service:apparmor-loader --version
run_loader() {
 docker run --rm --network none --read-only --memory 512m --cpus 1 --user 0:0 --cap-drop ALL --cap-add MAC_ADMIN --security-opt no-new-privileges --security-opt apparmor=unconfined --mount type=bind,src=/sys/kernel/security/apparmor,dst=/apparmor-policy --mount type=bind,src=/var/lib/kubelet/seccomp/codex-image-service,dst=/profiles --mount type=bind,src=/source,dst=/apparmor-source,readonly --entrypoint /usr/local/bin/node codex-image-service:apparmor-loader /apparmor-source/load-apparmor.cjs HASH
}
cp /sys/kernel/security/apparmor/profiles /tmp/before
run_loader
run_loader
grep -qx 'codex-image-service-v1 (enforce)' /sys/kernel/security/apparmor/profiles
cp /sys/kernel/security/apparmor/profiles /tmp/after
python3 -c "from pathlib import Path; before=set(Path('/tmp/before').read_text().splitlines()); after=set(Path('/tmp/after').read_text().splitlines()); assert before <= after; assert after-before == {'codex-image-service-v1 (enforce)'}"
cp /source/apparmor.profile /tmp/original-policy
printf '\\n# changed source\\n' >> /source/apparmor.profile
if run_loader; then exit 1; fi
cp /tmp/original-policy /source/apparmor.profile
printf 'conflict\\n' > /var/lib/kubelet/seccomp/codex-image-service/codex-image-service-v1.sha256
if run_loader; then exit 1; fi
printf 'HASH\\n' > /var/lib/kubelet/seccomp/codex-image-service/codex-image-service-v1.sha256
run_loader
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --security-opt apparmor=codex-image-service-v1 --user 1000:1000 --entrypoint /bin/sh codex-image-service:apparmor-loader -ec 'cat /proc/self/attr/current; grep -E "CapEff|NoNewPrivs|Seccomp:" /proc/self/status'
docker run --rm --network none --read-only --cap-drop ALL --security-opt no-new-privileges --security-opt apparmor=codex-image-service-v1 --security-opt seccomp=/shared/seccomp-amd64.json --user 1000:1000 --tmpfs /tmp:rw,exec,nosuid,nodev,mode=1777 --tmpfs /home/node:rw,exec,nosuid,nodev,uid=1000,gid=1000,mode=0700 --entrypoint /app/sandbox-check.sh codex-image-service:apparmor-loader
echo LOADER_VM_TEST_PASSED
shutdown -h now
'''.replace('HASH',h)
cloud={'write_files':[{'path':'/root/test.sh','permissions':'0700','content':script}], 'runcmd':[['bash','-c','/root/test.sh > /dev/ttyS0 2>&1 || { echo LOADER_VM_TEST_FAILED > /dev/ttyS0; shutdown -h now; }']]}
(work/'user-data').write_text('#cloud-config\n'+json.dumps(cloud))
(work/'meta-data').write_text(f'instance-id: apparmor-loader-{time.time_ns()}\nlocal-hostname: disposable-loader\n')
subprocess.run(['genisoimage','-quiet','-output',str(work/'seed.iso'),'-volid','cidata','-joliet','-rock',str(work/'user-data'),str(work/'meta-data')],check=True)
disk = work / 'disk.qcow2'
subprocess.run(['qemu-img','create','-f','qcow2','-F','qcow2','-b',str(image),str(disk),'12G'],check=True)
log=open(work/'console.log','wb')
p=subprocess.Popen(['qemu-system-x86_64','-enable-kvm','-m','3072','-smp','2','-display','none','-serial','stdio','-no-reboot','-drive',f'file={disk},if=virtio','-drive',f'file={work}/seed.iso,media=cdrom,readonly=on','-netdev','user,id=net0','-device','virtio-net-pci,netdev=net0','-virtfs',f'local,path={work},mount_tag=share,security_model=none'],stdout=log,stderr=log,start_new_session=True)
print('Disposable VM pid', p.pid, flush=True)
try:
 p.wait(timeout=options.timeout)
except subprocess.TimeoutExpired:
 p.terminate()
 p.wait(timeout=15)
 raise SystemExit('VM validation timed out; inspect console.log/results.log')
finally:
 log.close()
result = work / 'results.log'
if p.returncode != 0 or not result.exists() or 'LOADER_VM_TEST_PASSED' not in result.read_text():
 raise SystemExit('VM validation failed; inspect console.log/results.log')
print(result.read_text())
