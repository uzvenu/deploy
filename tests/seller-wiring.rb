require 'yaml'
require 'open3'

ROOT = File.expand_path('..', __dir__)
def check(value, message)
  raise message unless value
end

def render(chart, values, settings = [], success: true)
  namespace = values.include?('lattaputta') ? 'venu' : (values.include?('theantique') ? 'theantique' : 'venu-market')
  namespace = values.include?('lattaputta') ? 'agent' : (values.include?('theantique') ? 'theantique-agent' : 'venu-market-agent') if chart == 'charts/agent'
  out, err, status = Open3.capture3('helm', 'template', 'test', chart, '-f', values, '--namespace', namespace, *settings, chdir: ROOT)
  check(status.success? == success, "#{chart}: #{err}")
  success ? YAML.load_stream(out).compact : []
end

def container(docs, name)
  docs.find { |d| d['kind'] == 'Deployment' && d.dig('metadata', 'name') == name }.dig('spec', 'template', 'spec', 'containers', 0)
end

def env(c)
  names = c.fetch('env').map { |e| e.fetch('name') }
  check(names.uniq == names, 'Duplicate environment names')
  c.fetch('env').to_h { |e| [e['name'], e['value']] }
end

%w[lattaputta venu theantique].each do |brand|
  values = "../backend/helm/#{brand}-values.yaml"
  policy = YAML.load_file(File.join(ROOT, values)).fetch('productImport')
  docs = render('charts/marketplace', values)
  %w[venu-api worker].each do |name|
    actual = env(container(docs, name))
    check(actual['APP_PRODUCT_IMPORT_SELLER_IMAGE_MODE'] == policy.fetch('sellerImageMode'), "#{brand}/#{name}: seller mode")
    check(actual['APP_PRODUCT_IMPORT_SELLER_GENERATED_IMAGE_ROLES'] == policy.fetch('sellerGeneratedImageRoles').join(','), "#{brand}/#{name}: CSV roles, including explicit empty list")
  end
  agent_values = "../agent/helm/#{brand}-values.yaml"
  config = YAML.load_file(File.join(ROOT, agent_values))
  docs = render('charts/agent', agent_values)
  modern_name = config.fetch('modernAgent').fetch('name')
  modern = container(docs, modern_name)
  expected_mode = brand == 'theantique' ? 'provided' : 'generate'
  check(env(modern)['SELLER_IMPORT_IMAGE_MODE'] == expected_mode, "#{brand}: modern import policy missing")
  check(modern.fetch('env').count { |e| e['name'] == 'SELLER_IMPORT_IMAGE_MODE' } == 1, 'Modern policy must occur exactly once')
  independent = render('charts/agent', agent_values, ['--set', 'sellerAgent.enabled=false', '--set-json', 'sellerAgent.extraEnv=[{"name":"SELLER_IMPORT_IMAGE_MODE","value":"provided"}]'])
  check(env(container(independent, modern_name))['SELLER_IMPORT_IMAGE_MODE'] == expected_mode, 'Modern policy depends on seller settings')
  supplied = render('charts/agent', agent_values, ['--set-json', 'modernAgent.extraEnv=[{"name":"SELLER_IMPORT_IMAGE_MODE","value":"generate"},{"name":"SELLER_IMPORT_IMAGE_MODE","value":"provided"},{"name":"ALERT_SOURCE","valueFrom":{"fieldRef":{"fieldPath":"metadata.name"}}}]'])
  overridden = container(supplied, modern_name)
  check(env(overridden)['SELLER_IMPORT_IMAGE_MODE'] == 'provided', 'Repeated modern extraEnv must use last entry')
  source = overridden.fetch('env').find { |e| e['name'] == 'ALERT_SOURCE' }
  check(source.key?('valueFrom') && !source.key?('value'), 'Default and supplied valueFrom mixed')
  if brand == 'lattaputta'
    check(docs.none? { |d| d.dig('metadata', 'name') == 'seller-agent' }, 'Latta must stay combined')
    c = container(docs, 'lattaputta-agent')
    check(c['args'] == ['-mode', 'telegram,instagram,whatsapp,seller'], 'Latta modes changed')
    check(env(c)['SELLER_IMPORT_IMAGE_MODE'] == 'generate', 'Combined seller extraEnv missing')
    check(c.fetch('env').count { |e| e['name'] == 'SELLER_IMPORT_IMAGE_MODE' } == 1, 'Legacy policy must occur exactly once')
    merged = render('charts/agent', agent_values, ['--set-json', 'legacyAgent.extraEnv=[{"name":"SELLER_IMPORT_IMAGE_MODE","value":"provided"},{"name":"ALERT_SOURCE","value":"first"},{"name":"ALERT_SOURCE","value":"last"}]', '--set-json', 'sellerAgent.extraEnv=[{"name":"SELLER_IMPORT_IMAGE_MODE","value":"provided"},{"name":"SELLER_IMPORT_IMAGE_MODE","value":"generate"}]'])
    legacy = container(merged, 'lattaputta-agent')
    check(env(legacy)['SELLER_IMPORT_IMAGE_MODE'] == 'generate', 'Combined seller override precedence')
    check(env(legacy)['ALERT_SOURCE'] == 'last', 'Legacy default/extraEnv precedence')
  else
    c = container(docs, 'seller-agent')
    check(c['args'] == ['-mode', 'seller'], 'Seller mode must be isolated')
    check(c['envFrom'] == [{'secretRef' => {'name' => "#{brand}-seller-agent-env"}}], 'Customer Secret leaked')
    modern = container(docs, 'agent')
    %w[BRAND_NAME BRAND_SITE BRAND_PRODUCT_PATH CATALOG_PROVIDER CATALOG_API_BASE CATALOG_SITE_BASE].each do |key|
      check(env(c)[key] == env(modern).fetch(key), "Missing public inheritance: #{key}")
    end
    check((env(c).keys & %w[TELEGRAM_BOT_TOKEN CRM_INGESTION_TOKEN KB_SHEET_RANGE]).empty?, 'Customer env leaked')
    check(env(c)['SELLER_IMPORT_IMAGE_MODE'] == policy.fetch('sellerImageMode'), 'Agent/backend policy drift')
    check(env(c)['SELLER_AGENT_CONTROL_BASE_URL'].end_with?(':8080'), 'Control API must be origin, not /api/v1')
    check(!modern['args'].last.split(',').include?('seller'), 'Duplicate seller loop')
    check(c['ports'].nil? && c['livenessProbe'].nil? && c['readinessProbe'].nil?, 'Seller-only has no listener')
    d = docs.find { |r| r['kind'] == 'Deployment' && r.dig('metadata', 'name') == 'seller-agent' }
    check(d.dig('spec', 'replicas') == 1 && d.dig('spec', 'strategy', 'type') == 'Recreate', 'Concurrent polling risk')
    check(docs.none? { |r| %w[Service HTTPRoute].include?(r['kind']) && r.dig('metadata', 'name') == 'seller-agent' }, 'Unexpected seller exposure')
    disabled = render('charts/agent', "../agent/helm/#{brand}-values.yaml", ['--set', 'sellerAgent.enabled=false'])
    check(disabled.none? { |r| r.dig('metadata', 'name') == 'seller-agent' }, 'Disabled seller rendered')
  end
end
values = '../agent/helm/venu-values.yaml'
render('charts/agent', values, ['--set', 'sellerAgent.secretName='], success: false)
render('charts/agent', values, ['--set', 'sellerAgent.name=agent'], success: false)
render('charts/agent', values, ['--set-string', 'modernAgent.modes=seller'], success: false)
isolated = render('charts/agent', values, ['--set', 'legacyAgent.enabled=true'])
check(container(isolated, 'legacy-agent')['args'] == ['-mode', 'telegram,instagram,whatsapp'], 'Isolated seller must leave legacy loop')
override = render('charts/agent', values, ['--set', 'sellerAgent.extraEnv[2].name=BRAND_NAME', '--set-string', 'sellerAgent.extraEnv[2].value=Override'])
check(env(container(override, 'seller-agent'))['BRAND_NAME'] == 'Override', 'Seller public override lost')
values = '../backend/helm/venu-values.yaml'
render('charts/marketplace', values, ['--set', 'productImport.sellerImageMode=search'], success: false)
render('charts/marketplace', values, ['--set-json', 'productImport.sellerGeneratedImageRoles=[]'], success: false)
render('charts/marketplace', values, ['--set-json', 'productImport.sellerGeneratedImageRoles=["model","model"]'], success: false)
render('charts/marketplace', values, ['--set-json', 'productImport.sellerGeneratedImageRoles=["invalid"]'], success: false)
puts 'Seller wiring checks passed'
