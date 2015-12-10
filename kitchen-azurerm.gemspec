# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = 'kitchen-azurerm'
  spec.version       = '0.2.2'
  spec.authors       = ['Stuart Preston']
  spec.email         = ['stuart@pendrica.com']
  spec.summary       = 'Test Kitchen driver for Azure Resource Manager.'
  spec.description   = 'Test Kitchen driver for the Microsoft Azure Resource Manager (ARM) API'
  spec.homepage      = 'https://github.com/pendrica/kitchen-azurerm'
  spec.license       = 'Apache-2.0'

  spec.files         = Dir['LICENSE', 'README.md', 'CHANGELOG.md', 'lib/**/*']
  spec.require_paths = ['lib']

  spec.add_dependency 'inifile', '~> 2.0'
  spec.add_dependency 'azure_mgmt_resources', '0.1.1'
  spec.add_dependency 'azure_mgmt_network', '0.1.1'

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rubocop', '~> 0'
  spec.add_development_dependency 'rspec', '~> 0'
end
