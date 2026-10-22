require 'yaml'
require 'open3'

ROOT = File.expand_path('../../..', __dir__)
BUCKET = 'lattaputta-model-references-7bcb03fe'
KEY = 'private/model-references/d076bdd3bad41a19913493ae930e962a2e2f18f5579978dacf90a2ff0d84c734.jpg'
%w[lattaputta venu theantique].each do |brand|
  output, error, status = Open3.capture3('helm', 'template', brand, 'charts/marketplace', '--namespace', brand == 'lattaputta' ? 'venu' : brand == 'venu' ? 'venu-market' : 'theantique', '-f', "../backend/helm/#{brand}-values.yaml", chdir: ROOT)
  raise error unless status.success?
  containers = YAML.load_stream(output).compact.select { |d| d['kind'] == 'Deployment' }
    .flat_map { |d| d.dig('spec', 'template', 'spec', 'containers') }
    .select { |c| %w[api worker].include?(c['name']) }
  raise 'Expected API and worker' unless containers.map { |c| c['name'] }.sort == %w[api worker]
  containers.each do |container|
    refs = container.fetch('env').select { |e| e['name'].start_with?('APP_PRODUCT_IMPORT_MODEL_REFERENCE_') }
    expected = brand == 'lattaputta' ? [
      { 'name' => 'APP_PRODUCT_IMPORT_MODEL_REFERENCE_BUCKET', 'value' => BUCKET },
      { 'name' => 'APP_PRODUCT_IMPORT_MODEL_REFERENCE_KEY', 'value' => KEY }
    ] : []
    raise "Reference leaked or missing for #{brand}/#{container['name']}" unless refs == expected
  end
end
puts 'PASS: private model reference configured only for Lattaputta API/worker'
