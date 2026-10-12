require 'yaml'
require 'open3'

ROOT = File.expand_path('..', __dir__)
SHA = '0123456789012345678901234567890123456789'

def check(value, message)
  raise message unless value
end

def render(chart, values, namespace, settings = {}, success: true)
  args = ['helm', 'template', 'test', chart, '-f', values, '--namespace', namespace]
  settings.each { |key, value| args.concat(['--set-string', "#{key}=#{value}"]) }
  output, error, status = Open3.capture3(*args, chdir: ROOT)
  check(status.success? == success, error)
  success ? YAML.load_stream(output).compact : []
end

chart = 'charts/image-service'
values = '../agent/helm/lattaputta-image-service-values.yaml'
render(chart, values, 'agent', {}, success: false)
render(chart, values, 'agent', { 'image.tag' => 'latest' }, success: false)
render(chart, values, 'venu-market', { 'image.tag' => SHA }, success: false)
docs = render(chart, values, 'agent', { 'image.tag' => SHA })
check(docs.map { |d| d['kind'] }.sort == %w[ConfigMap DaemonSet Deployment NetworkPolicy Service], 'Unexpected service resources')
pod = docs.find { |d| d['kind'] == 'Deployment' }.dig('spec', 'template', 'spec')
check(pod['automountServiceAccountToken'] == false, 'Service account token exposed')
check(pod.dig('securityContext', 'runAsNonRoot') == true, 'Root runtime')
check(pod.dig('securityContext', 'seccompProfile', 'type') == 'Localhost', 'Seccomp profile missing')
profile = File.binread(File.join(ROOT, 'charts/image-service/files/seccomp-amd64.json'))
require 'digest'
hash = Digest::SHA256.hexdigest(profile)
check(pod.dig('securityContext', 'seccompProfile', 'localhostProfile') == "codex-image-service/#{hash}.json", 'Profile hash mismatch')
check(docs.find { |d| d['kind'] == 'ConfigMap' }.dig('data', 'profile.json') == profile, 'ConfigMap bytes drifted')
installer = docs.find { |d| d['kind'] == 'DaemonSet' }.dig('spec', 'template', 'spec')
check(installer['nodeSelector'] == pod['nodeSelector'], 'Node eligibility differs')
check(installer['automountServiceAccountToken'] == false, 'Installer token exposed')
check(installer.dig('securityContext', 'seccompProfile', 'type') == 'RuntimeDefault', 'Installer seccomp weakened')
check(installer['containers'].first['volumeMounts'].nil?, 'Idle container host access')
check(installer['volumes'].select { |v| v['hostPath'] }.map { |v| v['hostPath'] } == [{'path' => '/var/lib/kubelet/seccomp/codex-image-service', 'type' => 'DirectoryOrCreate'}], 'Host scope broadened')
init = installer['initContainers'].first
check(init.dig('securityContext', 'runAsUser') == 0, 'Installer owner incorrect')
check(init.dig('securityContext', 'capabilities', 'drop') == ['ALL'], 'Installer capabilities')
check(init.dig('securityContext', 'allowPrivilegeEscalation') == false && init.dig('securityContext', 'readOnlyRootFilesystem') == true, 'Installer isolation')
check(init['command'].last.include?('ln "$tmp" "$target"'), 'Missing atomic no-clobber publication')
container = pod['containers'].first
check(container['image'].end_with?(SHA), 'Wrong immutable image')
check(container['securityContext'] == { 'allowPrivilegeEscalation' => false,
  'readOnlyRootFilesystem' => true, 'capabilities' => { 'drop' => ['ALL'] } }, 'Container security weakened')
check(pod['volumes'].none? { |v| v.key?('hostPath') || v.key?('persistentVolumeClaim') }, 'Persistent or host mounts')
check(container['env'].map { |e| e['name'] } == %w[IMAGE_SERVICE_TOKEN IMAGE_SERVICE_MODEL], 'Unrelated runtime secrets')
peer = docs.find { |d| d['kind'] == 'NetworkPolicy' }.dig('spec', 'ingress', 0, 'from', 0)
check(peer.dig('namespaceSelector', 'matchLabels', 'kubernetes.io/metadata.name') == 'venu', 'Wrong client brand namespace')
check(peer.dig('podSelector', 'matchExpressions', 0, 'values') == %w[venu-api worker], 'Wrong client pods')

root = 'charts/marketplace'
root_values = '../backend/helm/lattaputta-values.yaml'
base = render(root, root_values, 'venu')
check(base.none? { |d| d.dig('metadata', 'name') == 'codex-image-service' }, 'Default bootstrap enabled')
active = render(root, root_values, 'venu', { 'imageServiceApplication.enabled' => 'true' })
app = active.find { |d| d['kind'] == 'Application' && d.dig('metadata', 'name') == 'codex-image-service' }
check(app, 'Root Application missing')
check(app.dig('spec', 'destination', 'namespace') == 'agent', 'Wrong destination')
check(app.dig('spec', 'sources', 0, 'path') == chart, 'Wrong chart')
check(app.dig('spec', 'sources', 0, 'helm', 'valueFiles') == ['$values/helm/lattaputta-image-service-values.yaml'], 'Wrong brand values')
check(app.dig('spec', 'syncPolicy', 'automated').nil?, 'Auto-sync enabled before prerequisites')
check(active.reject { |d| d == app } == base, 'Existing marketplace resources changed')
render(root, '../backend/helm/venu-values.yaml', 'venu-market', { 'imageServiceApplication.enabled' => 'true' }, success: false)
puts 'Image service chart and bootstrap checks passed'
