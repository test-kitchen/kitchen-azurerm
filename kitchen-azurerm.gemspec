lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "kitchen/driver/azurerm_version"

Gem::Specification.new do |spec|
  spec.name          = "kitchen-azurerm"
  spec.version       = Kitchen::Driver::AZURERM_VERSION
  spec.authors       = ["Stuart Preston"]
  spec.email         = ["stuart@chef.io"]
  spec.summary       = "Test Kitchen driver for Azure Resource Manager."
  spec.description   = "Test Kitchen driver for the Microsoft Azure Resource Manager (ARM) API"
  spec.homepage      = "https://github.com/test-kitchen/kitchen-azurerm"
  spec.license       = "Apache-2.0"

  spec.files         = Dir["LICENSE", "lib/**/*", "templates/**/*"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.6"

  spec.add_dependency "azure_mgmt_network2", "~> 0.27"
  spec.add_dependency "azure_mgmt_resources2", "~> 0.19"
  spec.add_dependency "inifile", "~> 3.0", ">= 3.0.0"
  spec.add_dependency "sshkey", ">= 1.0.0", "< 3"
  spec.add_dependency "test-kitchen", ">= 1.20", "< 4.0"
end
