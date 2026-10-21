# Run from any directory with Ruby (standard library only) and Helm installed.
require 'yaml'
require 'open3'

ROOT = File.expand_path('../../..', __dir__)

def render(brand, settings = [], success: true)
  output, error, status = Open3.capture3('helm', 'template', brand, 'charts/marketplace',
    '--namespace', brand == 'lattaputta' ? 'venu' : brand == 'venu' ? 'venu-market' : 'theantique',
    '-f', "../backend/helm/#{brand}-values.yaml", *settings, chdir: ROOT)
  raise "Unexpected render result: #{error}" unless status.success? == success
  return error unless success
  YAML.load_stream(output).compact
end

def check_env(brand, expected, settings = [])
  documents = render(brand, settings)
  containers = documents.select { |doc| doc['kind'] == 'Deployment' }
    .flat_map { |doc| doc.dig('spec', 'template', 'spec', 'containers') }
    .select { |container| %w[api worker].include?(container['name']) }
  raise 'Expected API and worker' unless containers.map { |c| c['name'] }.sort == %w[api worker]
  containers.each do |container|
    entries = container.fetch('env').select { |env| env['name'].start_with?('APP_DELIVERY_EMU_') }
    expected_entries = expected.nil? ? [] : [{ 'name' => 'APP_DELIVERY_EMU_ENABLED', 'value' => expected }]
    raise "Wrong EMU env for #{brand}/#{container['name']}: #{entries}" unless entries == expected_entries
    secret = YAML.load_file(File.join(ROOT, "../backend/helm/#{brand}-values.yaml")).fetch('api').fetch('secretName')
    raise 'Brand Secret import missing' unless container.fetch('envFrom').include?('secretRef' => { 'name' => secret })
  end
end

%w[venu lattaputta].each { |brand| check_env(brand, nil) }
check_env('theantique', 'true')
check_env('theantique', 'false', ['--set', 'api.emuEnabled=false'])
check_env('venu', 'true', ['--set', 'api.emuEnabled=true'])
check_env('venu', 'false', ['--set', 'api.emuEnabled=false'])
error = render('venu', ['--set-string', 'api.emuEnabled=false'], success: false)
raise 'Expected boolean schema validation' unless error.include?('emuEnabled') && error.include?('boolean')
puts 'PASS: optional EMU API/worker switch, explicit true/false strings, Secret inheritance and boolean validation'
