# Run from any directory with Ruby (standard library only) and Helm installed.
require 'yaml'
require 'open3'

ROOT = File.expand_path('../../..', __dir__)

def render(brand, settings = [])
  output, error, status = Open3.capture3('helm', 'template', brand, 'charts/marketplace',
    '--namespace', brand == 'lattaputta' ? 'venu' : brand == 'venu' ? 'venu-market' : 'theantique',
    '-f', "../backend/helm/#{brand}-values.yaml", *settings, chdir: ROOT)
  raise error unless status.success?
  YAML.load_stream(output).compact
end

def check_env(documents, enabled, countries, default_country = 'UZ')
  containers = documents.select { |doc| doc['kind'] == 'Deployment' }
    .flat_map { |doc| doc.dig('spec', 'template', 'spec', 'containers') }
    .select { |container| %w[api worker].include?(container['name']) }
  raise 'Expected API and worker' unless containers.map { |c| c['name'] }.sort == %w[api worker]
  expected = {
    'APP_ADDRESSES_INTERNATIONAL_ENABLED' => enabled,
    'APP_ADDRESSES_ALLOWED_COUNTRY_CODES' => countries,
    'APP_ADDRESSES_DEFAULT_COUNTRY_CODE' => default_country
  }
  containers.each do |container|
    actual = container.fetch('env').select { |env| env['name'].start_with?('APP_ADDRESSES_') }
    raise "Duplicate or missing env in #{container['name']}" unless actual.length == expected.length
    raise "Wrong env in #{container['name']}: #{actual}" unless
      actual.to_h { |env| [env['name'], env['value']] } == expected
  end
end

%w[venu lattaputta].each { |brand| check_env(render(brand), 'false', 'UZ') }
check_env(render('theantique'), 'true', '')
check_env(render('venu', ['--set', 'addresses.allowedCountryCodes={UZ,US}',
  '--set', 'addresses.defaultCountryCode=US']), 'false', 'UZ,US', 'US')
puts 'PASS: API/worker brand switches, explicit empty allowlist, comma list and default country'
