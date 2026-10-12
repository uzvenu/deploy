require 'yaml'
require 'open3'

ROOT = File.expand_path('..', __dir__)
SHA = '0123456789012345678901234567890123456789'

def check(value, message)
  raise message unless value
end

def render(chart, values, namespace, settings = {}, success: true)
  args = ['helm', 'template', 'test', chart, '-f', values, '--namespace', namespace]
  settings.each { |key, value| args.concat([%w[true false].include?(value) ? '--set' : '--set-string', "#{key}=#{value}"]) }
  output, error, status = Open3.capture3(*args, chdir: ROOT)
  check(status.success? == success, error)
  success ? YAML.load_stream(output).compact : []
end

chart = 'charts/image-service'
values = '../agent/helm/lattaputta-image-service-values.yaml'
render(chart, values, 'agent', { 'image.tag' => '' }, success: false)
render(chart, values, 'agent', { 'image.tag' => 'latest' }, success: false)
render(chart, values, 'venu-market', { 'image.tag' => SHA }, success: false)
render(chart, values, 'agent', { 'image.tag' => SHA, 'clientNamespace' => '' }, success: false)
render(chart, values, 'agent', { 'image.tag' => SHA, 'clientPodNames' => '' }, success: false)
docs = render(chart, values, 'agent', { 'image.tag' => SHA })
check(docs.map { |d| d['kind'] }.sort == %w[ConfigMap ConfigMap DaemonSet Deployment NetworkPolicy PersistentVolumeClaim Service], 'Unexpected service resources')
pod = docs.find { |d| d['kind'] == 'Deployment' }.dig('spec', 'template', 'spec')
check(pod['automountServiceAccountToken'] == false, 'Service account token exposed')
check(pod.dig('securityContext', 'runAsNonRoot') == true, 'Root runtime')
check(pod.dig('securityContext', 'seccompProfile', 'type') == 'Localhost', 'Seccomp profile missing')
profile = File.binread(File.join(ROOT, 'charts/image-service/files/seccomp-amd64.json'))
require 'digest'
hash = Digest::SHA256.hexdigest(profile)
check(pod.dig('securityContext', 'seccompProfile', 'localhostProfile') == "codex-image-service/#{hash}.json", 'Profile hash mismatch')
check(docs.find { |d| d['kind'] == 'ConfigMap' && d.dig('data', 'profile.json') }.dig('data', 'profile.json') == profile, 'ConfigMap bytes drifted')
installer = docs.find { |d| d['kind'] == 'DaemonSet' }.dig('spec', 'template', 'spec')
check(installer['nodeSelector'] == pod['nodeSelector'], 'Node eligibility differs')
check(installer['automountServiceAccountToken'] == false, 'Installer token exposed')
check(installer.dig('securityContext', 'seccompProfile', 'type') == 'RuntimeDefault', 'Installer seccomp weakened')
check(installer['containers'].first['volumeMounts'].nil?, 'Idle container host access')
check(installer['volumes'].select { |v| v['hostPath'] }.map { |v| v['hostPath'] } == [{'path' => '/sys/kernel/security/apparmor', 'type' => 'Directory'}, {'path' => '/var/lib/kubelet/seccomp/codex-image-service', 'type' => 'DirectoryOrCreate'}], 'Host scope broadened')
init = installer['initContainers'].first
check(init.dig('securityContext', 'runAsUser') == 0, 'Installer owner incorrect')
check(init.dig('securityContext', 'capabilities', 'drop') == ['ALL'], 'Installer capabilities')
check(init.dig('securityContext', 'allowPrivilegeEscalation') == false && init.dig('securityContext', 'readOnlyRootFilesystem') == true, 'Installer isolation')
check(init['command'].last.include?('ln "$tmp" "$target"'), 'Missing atomic no-clobber publication')
container = pod['containers'].first
check(container['image'].end_with?(SHA), 'Wrong immutable image')
check(container['securityContext'] == { 'allowPrivilegeEscalation' => false,
  'readOnlyRootFilesystem' => true, 'appArmorProfile' => { 'type' => 'Localhost', 'localhostProfile' => 'codex-image-service-v1' }, 'capabilities' => { 'drop' => ['ALL'] } }, 'Container security weakened')
check(pod['volumes'].none? { |v| v.key?('hostPath') }, 'Host mounts')
check(pod['volumes'].find { |v| v['name'] == 'home' }['persistentVolumeClaim'] == { 'claimName' => 'codex-image-service-home' }, 'Dedicated home claim missing')
pvc = docs.find { |d| d['kind'] == 'PersistentVolumeClaim' }
check(pvc.dig('metadata', 'annotations') == { 'helm.sh/resource-policy' => 'keep', 'argocd.argoproj.io/sync-options' => 'Prune=false,Delete=false' }, 'Credential retention missing')
check(pvc.dig('spec', 'accessModes') == ['ReadWriteOnce'] && pvc.dig('spec', 'resources', 'requests', 'storage') == '2Gi', 'Home capacity/access mismatch')
check(pvc.dig('spec', 'storageClassName') == 'local-path', 'Wrong storage class')
check(docs.find { |d| d['kind'] == 'Deployment' }.dig('spec', 'strategy', 'type') == 'Recreate', 'Concurrent auth writers')
check(container['volumeMounts'].find { |v| v['name'] == 'auth' }['readOnly'] == true, 'Seed writable')
check(pod['volumes'].find { |v| v['name'] == 'tmp' }['emptyDir'] == { 'sizeLimit' => '2Gi' }, 'Temporary workspace persisted')
ephemeral = render(chart, values, 'agent', { 'image.tag' => SHA, 'homePersistence.enabled' => 'false' })
check(ephemeral.none? { |d| d['kind'] == 'PersistentVolumeClaim' }, 'Optional PVC enabled implicitly')
check(container['env'].map { |e| e['name'] } == %w[IMAGE_SERVICE_TOKEN IMAGE_SERVICE_MODEL], 'Unrelated runtime secrets')
check(pod.dig('securityContext', 'appArmorProfile').nil?, 'AppArmor policy must be container-only')
apparmor = File.binread(File.join(ROOT, 'charts/image-service/files/apparmor.profile'))
check(apparmor == File.binread(File.join(ROOT, '../agent/services/image-service/apparmor.profile')), 'AppArmor artifact drift')
apparmor_hash = Digest::SHA256.hexdigest(apparmor)
cm = docs.find { |d| d['kind'] == 'ConfigMap' && d.dig('data', 'apparmor.profile') }
check(cm.dig('data', 'apparmor.profile') == apparmor && cm['immutable'] == true, 'AppArmor distribution bytes drift')
check(cm.dig('metadata', 'annotations', 'security.venu.uz/profile-sha256') == apparmor_hash, 'AppArmor artifact hash mismatch')
check(docs.find { |d| d['kind'] == 'Deployment' }.dig('spec', 'template', 'metadata', 'annotations', 'checksum/apparmor-profile') == apparmor_hash, 'AppArmor pod checksum mismatch')
check(installer.dig('securityContext', 'appArmorProfile').nil?, 'Installer AppArmor changed')
loader = installer['initContainers'].find { |c| c['name'] == 'load-apparmor' }
check(loader.dig('securityContext', 'capabilities') == { 'drop' => ['ALL'], 'add' => ['MAC_ADMIN'] }, 'Loader capability scope')
check(loader.dig('securityContext', 'appArmorProfile', 'type') == 'Unconfined', 'Administrative loader confinement')
check(loader.dig('securityContext', 'allowPrivilegeEscalation') == false && loader.dig('securityContext', 'readOnlyRootFilesystem') == true, 'Loader isolation')
loader_source = File.read(File.join(ROOT, 'charts/image-service/files/load-apparmor.cjs'))
check(loader_source.include?("parser('--add')") && !loader_source.include?('--replace'), 'Loader overwrites policy')
check(cm.dig('data', 'load-apparmor.cjs') == loader_source, 'Loader ConfigMap bytes drift')
combined_hash = Digest::SHA256.hexdigest(apparmor + loader_source)
check(cm.dig('metadata', 'name') == "codex-image-service-apparmor-#{combined_hash[0, 16]}", 'Immutable loader ConfigMap identity')
check(loader.dig('securityContext', 'seccompProfile', 'type') == 'RuntimeDefault' && loader.dig('securityContext', 'runAsUser') == 0, 'Loader security context drift')
check(loader['env'].nil? && loader['envFrom'].nil? && loader.dig('securityContext', 'privileged').nil?, 'Loader credential/privilege exposure')
check(loader['volumeMounts'].find { |v| v['name'] == 'apparmor-source' }['readOnly'] == true, 'Writable source')
check(loader['volumeMounts'].find { |v| v['name'] == 'apparmor-policy' }['mountPath'] == '/apparmor-policy', 'Masked securityfs mountpoint')
check(loader_source.include?('O_NOFOLLOW') && loader_source.include?('O_EXCL') && loader_source.include?('fs.fsyncSync(fd)'), 'Sentinel protection missing')
check(loader['command'] == ['/usr/local/bin/node', '/apparmor-source/load-apparmor.cjs', apparmor_hash], 'Loader source hash mismatch')
check(loader['volumeMounts'].map { |v| v['name'] } == %w[apparmor-source apparmor-policy profiles], 'Loader unrelated mounts')
check(installer['imagePullSecrets'] == [{'name' => pod['imagePullSecrets'].first['name']}], 'Installer private image pull missing')
check(loader.dig('resources', 'limits', 'memory') == '512Mi', 'Parser memory bound missing')
(installer['initContainers'].reject { |c| c == loader } + installer['containers']).each do |c|
  check(c.dig('securityContext', 'appArmorProfile').nil?, 'Installer container AppArmor changed')
end
workflow = File.read(File.join(ROOT, '../agent/.github/workflows/image-service-cd.yml'))
check(workflow.include?('--security-opt apparmor=codex-image-service-v1'), 'CI AppArmor differs from workload')
check(workflow.include?('sudo apparmor_parser --add --skip-cache services/image-service/apparmor.profile'), 'CI does not load enforcing policy')
check(!workflow.include?('apparmor=unconfined'), 'CI AppArmor bypass')
check(workflow.include?('--security-opt seccomp="${GITHUB_WORKSPACE}/services/image-service/seccomp-amd64.json"'), 'CI bounded seccomp missing')
check(!workflow.include?('--privileged') && !workflow.include?('seccomp=unconfined') && !workflow.include?('--cap-add'), 'CI privilege bypass')
policy = docs.find { |d| d['kind'] == 'NetworkPolicy' }['spec']
check(policy['policyTypes'] == ['Ingress'], 'Wrong network isolation type')
check(policy['ingress'].length == 1 && policy['ingress'].first['from'].length == 1, 'Additional ingress peers')
check(policy['ingress'].first['ports'] == [{'protocol' => 'TCP', 'port' => 8091}], 'Extra ingress ports')
check(docs.find { |d| d['kind'] == 'Service' }.dig('spec', 'type') == 'ClusterIP', 'Public service exposure')
peer = policy.dig('ingress', 0, 'from', 0)
check(peer.dig('namespaceSelector', 'matchLabels', 'kubernetes.io/metadata.name') == 'venu', 'Wrong client brand namespace')
check(peer.dig('podSelector', 'matchExpressions', 0, 'values') == %w[venu-api worker], 'Wrong client pods')

root = 'charts/marketplace'
root_values = '../backend/helm/lattaputta-values.yaml'
base = render(root, root_values, 'venu', { 'imageServiceApplication.enabled' => 'false' })
check(base.none? { |d| d.dig('metadata', 'name') == 'codex-image-service' }, 'Default bootstrap enabled')
active = render(root, root_values, 'venu', { 'imageServiceApplication.enabled' => 'true', 'imageServiceApplication.autoSync' => 'false' })
app = active.find { |d| d['kind'] == 'Application' && d.dig('metadata', 'name') == 'codex-image-service' }
check(app, 'Root Application missing')
check(app.dig('spec', 'destination', 'namespace') == 'agent', 'Wrong destination')
check(app.dig('spec', 'sources', 0, 'path') == chart, 'Wrong chart')
check(app.dig('spec', 'sources', 0, 'helm', 'valueFiles') == ['$values/helm/lattaputta-image-service-values.yaml'], 'Wrong brand values')
check(app.dig('spec', 'syncPolicy', 'automated').nil?, 'Auto-sync enabled before prerequisites')
check(active.reject { |d| d == app } == base, 'Existing marketplace resources changed')
render(root, '../backend/helm/venu-values.yaml', 'venu-market', { 'imageServiceApplication.enabled' => 'true' }, success: false)
puts 'Image service chart and bootstrap checks passed'
