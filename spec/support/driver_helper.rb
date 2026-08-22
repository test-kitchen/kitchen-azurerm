# Helpers for building a driver wired to a doubled Test Kitchen instance.
module DriverHelper
  # Configuration every example starts from. Individual specs merge over it.
  DEFAULT_CONFIG = {
    subscription_id: "115b12cb-b0d3-4ed9-94db-f73733be6f3c",
    location: "eastus2",
    machine_size: "Standard_D4_v3",
    image_urn: "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest",
    azure_environment: "Azure",
    # Keep the deployment poller from actually waiting.
    deployment_sleep: 0,
  }.freeze

  # Builds a driver with a doubled instance already attached.
  #
  # @param transport [Object] the transport double, see {#transport_double}.
  # @param platform_name [String] the platform name reported by the instance.
  # @param instance_name [String] the instance name.
  # @param config [Hash] driver configuration, merged over {DEFAULT_CONFIG}.
  # @return [Kitchen::Driver::Azurerm]
  def build_driver(transport: transport_double, platform_name: "ubuntu-22.04", instance_name: "default-ubuntu-2204", **config)
    driver = Kitchen::Driver::Azurerm.new(DEFAULT_CONFIG.merge(config))
    instance = instance_double(
      Kitchen::Instance,
      name: instance_name,
      logger: Kitchen.logger,
      transport:,
      platform: Kitchen::Platform.new(name: platform_name),
      to_str: "<#{instance_name}>"
    )
    allow(driver).to receive(:instance).and_return(instance)
    allow(driver).to receive(:sleep)
    driver
  end

  # A transport stand-in.
  #
  # @param name [String] the transport name, e.g. +"Ssh"+ or +"Winrm"+.
  # @param settings [Hash] settings readable through +transport[:key]+.
  # @return [RSpec::Mocks::InstanceVerifyingDouble]
  def transport_double(name: "Dummy", **settings)
    double = instance_double(Kitchen::Transport::Dummy, name:)
    allow(double).to receive(:[]) { |key| settings[key] }
    double
  end

  # Reads a driver's merged configuration, including defaults.
  #
  # @param driver [Kitchen::Driver::Azurerm]
  # @return [Hash]
  def driver_config(driver)
    driver.instance_variable_get(:@config)
  end

  # Renders and parses the driver's virtual machine deployment template.
  #
  # @param driver [Kitchen::Driver::Azurerm]
  # @return [Hash] the parsed ARM template.
  def rendered_template(driver)
    JSON.parse(driver.virtual_machine_deployment_template)
  end

  # Finds the virtual machine resource in a parsed ARM template.
  #
  # @param template [Hash] a parsed ARM template.
  # @return [Hash, nil]
  def vm_resource(template)
    template["resources"].find { |resource| resource["type"] == "Microsoft.Compute/virtualMachines" }
  end
end
