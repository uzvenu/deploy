require 'yaml'
require 'open3'

ROOT = File.expand_path('..', __dir__)
PREFIX = '/api/integrations/robothub/v1'

def render(*settings)
  args = ['helm', 'template', 'routing-test', 'charts/storefront', '--set', 'enabled=true', '--set', 'partOf=test', '--set', 'registrySecretName=test-registry', '--set', 'secretName=test-env', '--set', 'route.hostname=example.test']
  output, error, status = Open3.capture3(*args, *settings, chdir: ROOT)
  raise error unless status.success?
  YAML.load_stream(output).compact.find { |doc| doc['kind'] == 'HTTPRoute' }
end

def target(route, path)
  candidates = route.fetch('spec').fetch('rules').flat_map do |rule|
    rule.fetch('matches').filter_map do |match|
      value = match.fetch('path').fetch('value')
      exact = match.fetch('path').fetch('type') == 'Exact'
      matches = exact ? path == value : (value == '/' || path == value || path.start_with?(value + '/'))
      [value.length, rule.fetch('backendRefs').first.fetch('name')] if matches
    end
  end
  candidates.max_by(&:first)&.last
end

def check(value, message)
  raise message unless value
end

baseline = render
check(target(baseline, PREFIX + '/seller/info') == 'storefront', 'Integration routing must be opt-in')
configured = render('--set', "panel.additionalBackendPrefixes[0]=#{PREFIX}")
[PREFIX, PREFIX + '/seller/info', PREFIX + '/products', PREFIX + '/openapi.yaml'].each do |path|
  check(target(configured, path) == 'venu-api', "#{path} must reach backend")
end
['/', '/products', '/api/auth/session', '/api/v1/products', PREFIX + '-other/products'].each do |path|
  check(target(configured, path) == 'storefront', "#{path} must retain frontend routing")
end
check(target(configured, '/seller') == 'venu-api', 'Seller panel routing changed')
check(target(configured, '/admin') == 'venu-api', 'Admin panel routing changed')
disabled = render('--set', 'panel.enabled=false', '--set', "panel.additionalBackendPrefixes[0]=#{PREFIX}")
check(target(disabled, PREFIX + '/products') == 'storefront', 'Disabled backend routing must remain disabled')
puts 'Storefront integration routing checks passed'
