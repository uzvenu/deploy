# Run from any directory with Ruby (standard library only) and Helm installed.
require 'yaml'
require 'open3'

ROOT = File.expand_path('..', __dir__)
BASE = ['helm', 'template', 'venu', 'charts/marketplace', '-f',
        '../backend/helm/lattaputta-values.yaml',
        '--set', 'crmApplication.enabled=false',
        '--set', 'crmApplication.namespaceEnabled=false',
        '--set', 'crmApplication.autoSync=false'].freeze

def check(condition, message)
  raise message unless condition
end

def render(settings = {})
  args = settings.flat_map { |key, value| ['--set', "#{key}=#{value}"] }
  output, error, status = Open3.capture3(*BASE, *args, chdir: ROOT)
  check(status.success?, error)
  YAML.load_stream(output).compact
end

def bootstrap(documents)
  documents.select do |doc|
    doc['kind'] == 'Namespace' ||
      (doc['kind'] == 'Application' && doc.dig('metadata', 'name') == 'crm')
  end
end

def application(documents, automatic)
  app = documents.find { |doc| doc['kind'] == 'Application' }
  check(app && app['apiVersion'] == 'argoproj.io/v1alpha1', 'Application missing')
  metadata = app.fetch('metadata')
  check(metadata['name'] == 'crm' && metadata['namespace'] == 'argocd', 'Application identity')
  check(metadata.dig('labels', 'app.kubernetes.io/part-of') == 'venu-crm', 'Application label')
  check(metadata['annotations'] == {
    'argocd.argoproj.io/sync-wave' => '0',
    'argocd.argoproj.io/sync-options' => 'Delete=false'
  }, 'Application annotations')
  check(!metadata.key?('finalizers'), 'Unexpected cascading finalizer')
  spec = app.fetch('spec')
  check(spec['project'] == 'default', 'Application project')
  check(spec['sources'] == [
    { 'repoURL' => 'https://github.com/uzvenu/deploy.git', 'targetRevision' => 'master',
      'path' => 'charts/crm', 'helm' => { 'releaseName' => 'crm',
      'valueFiles' => ['$values/helm/crm-values.yaml'] } },
    { 'repoURL' => 'https://github.com/uzvenu/crm.git', 'targetRevision' => 'main',
      'ref' => 'values' }
  ], 'Multi-source contract')
  check(spec['destination'] == { 'server' => 'https://kubernetes.default.svc',
    'namespace' => 'venu-crm' }, 'Application destination')
  policy = spec.fetch('syncPolicy')
  check(policy['syncOptions'] == ['CreateNamespace=true', 'ApplyOutOfSyncOnly=true'], 'Sync options')
  check(policy['retry'] == { 'limit' => 5, 'backoff' => {
    'duration' => '10s', 'maxDuration' => '3m', 'factor' => 2 } }, 'Retry policy')
  if automatic
    check(policy['automated'] == { 'prune' => true, 'selfHeal' => true }, 'Automatic sync policy')
  else
    check(!policy.key?('automated'), 'Registration must not auto-sync')
  end
end

baseline = render
check(bootstrap(baseline).empty?, 'Defaults must not bootstrap CRM')
check(bootstrap(render('crmApplication.autoSync' => true)).empty?, 'Auto-sync alone enables nothing')
namespace_settings = { 'crmApplication.namespaceEnabled' => true }
ns_only = bootstrap(render(namespace_settings))
check(ns_only.length == 1 && ns_only.first['kind'] == 'Namespace', 'Namespace-only phase')
ns = ns_only.first
check(ns['apiVersion'] == 'v1' && ns.dig('metadata', 'name') == 'venu-crm', 'Namespace identity')
check(!ns.fetch('metadata').key?('namespace'), 'Namespace must be cluster-scoped')
check(ns.dig('metadata', 'labels', 'app.kubernetes.io/part-of') == 'venu-crm', 'Namespace label')
check(ns.dig('metadata', 'annotations') == {
  'argocd.argoproj.io/sync-wave' => '-1',
  'argocd.argoproj.io/sync-options' => 'Prune=false,Delete=false'
}, 'Namespace retention and ordering')

app_settings = { 'crmApplication.enabled' => true }
app_only = bootstrap(render(app_settings))
check(app_only.length == 1, 'Application toggle must not implicitly render Namespace')
application(app_only, false)
both_settings = namespace_settings.merge(app_settings)
both = render(both_settings)
check(bootstrap(both).length == 2, 'Registration phase resources')
application(bootstrap(both), false)
check(both.reject { |doc| bootstrap([doc]).any? } == baseline, 'Existing resources changed')
auto = bootstrap(render(both_settings.merge('crmApplication.autoSync' => true)))
check(auto.length == 2, 'Automatic phase resources')
application(auto, true)
check(render(both_settings.merge('enabled' => false)).empty?, 'Global disable must suppress bootstrap')

fields = %w[name partOf namespace chartPath releaseName valuesRepoURL valuesRevision valuesFile]
fields.each do |field|
  output, error, status = Open3.capture3(*BASE, '--set', 'crmApplication.enabled=true',
    '--set', "crmApplication.#{field}=", chdir: ROOT)
  check(!status.success? && error.include?("crmApplication.#{field} is required"),
    "Missing #{field} must fail enabled render: #{output} #{error}")
end
# Namespace-only provisioning must not require Application source fields.
render(namespace_settings.merge('crmApplication.valuesRepoURL' => ''))
puts 'PASS: defaults, namespace-only, inert registration, auto-sync, exact fields, retention, global gate and required-field validation'
