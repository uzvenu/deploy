# Dedicated enforcing profile for Ubuntu 24.04+/AppArmor 4 and Codex bubblewrap.
# Explicit userns permission avoids Ubuntu's unprivileged_userns transition.
abi <abi/4.0>,
include <tunables/global>

profile codex-image-service-v1 flags=(attach_disconnected,mediate_deleted) {
  userns,
  file,
  network inet stream,
  network inet dgram,
  network inet6 stream,
  network inet6 dgram,
  network unix,
  network netlink raw,
  network netlink dgram,

  # Linux capability sets stay empty in the outer container. These checks are
  # needed only for bubblewrap's setup in its freshly created user namespace.
  capability setpcap,
  capability sys_admin,
  capability sys_chroot,
  capability net_admin,
  capability setuid,
  capability setgid,
  capability sys_ptrace,
  mount,
  umount,
  pivot_root,

  signal (receive) peer=unconfined,
  signal (receive) peer=runc,
  signal (receive) peer=crun,
  signal (send,receive) peer=codex-image-service-v1,
  ptrace (trace,tracedby,read,readby) peer=codex-image-service-v1,

  # Preserve Docker-style sensitive proc/sys denials despite allowing the
  # namespace-local filesystem setup that docker-default forbids outright.
  deny @{PROC}/* w,
  deny @{PROC}/{[^1-9/],[^1-9/][^0-9/],[^1-9s/][^0-9y/][^0-9s/],[^1-9/][^0-9/][^0-9/][^0-9/]*}/** w,
  deny @{PROC}/sys/[^k]** w,
  deny @{PROC}/sys/kernel/{?,??,[^s][^h][^m]**} w,
  deny @{PROC}/sysrq-trigger rwklx,
  deny @{PROC}/kcore rwklx,
  deny /sys/[^f]*/** wklx,
  deny /sys/f[^s]*/** wklx,
  deny /sys/fs/[^c]*/** wklx,
  deny /sys/fs/c[^g]*/** wklx,
  deny /sys/fs/cg[^r]*/** wklx,
  deny /sys/firmware/** rwklx,
  deny /sys/devices/virtual/powercap/** rwklx,
  deny /sys/kernel/security/** rwklx,
}
