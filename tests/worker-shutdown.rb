require 'yaml'
require 'open3'
root = File.expand_path('..', __dir__)
backend = File.expand_path(ARGV.fetch(0, '../../backend'), __dir__)
%w[lattaputta venu theantique].each do |brand|
  values = File.join(backend, 'helm', "#{brand}-values.yaml")
  namespace = { 'lattaputta' => 'venu', 'venu' => 'venu-market', 'theantique' => 'theantique' }.fetch(brand)
  args = ['helm', 'template', brand, 'charts/marketplace', '-n', namespace, '-f', values]
  out, err, status = Open3.capture3(*args, chdir: root)
  raise err unless status.success?
  docs = YAML.load_stream(out).compact
  pod = docs.find { |d| d['kind'] == 'Deployment' && d.dig('metadata', 'name') == 'worker' }.dig('spec', 'template', 'spec')
  raise 'Worker shutdown grace mismatch' unless pod.fetch('terminationGracePeriodSeconds') == 650
  raise 'preStop must not consume drain budget' if pod.fetch('containers').any? { |c| c.dig('lifecycle', 'preStop') }
  _, _, invalid = Open3.capture3(*args, '--set', 'worker.terminationGracePeriodSeconds=620', chdir: root)
  raise 'Accepted unsafe shutdown budget' if invalid.success?
  puts "#{brand}: worker shutdown budget OK"
end
