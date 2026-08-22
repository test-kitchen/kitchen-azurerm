# Doubles and real SDK model objects standing in for the Azure Resource Manager
# and Network management APIs.
#
# Where the SDK ships a plain model class (deployment operations, resource
# groups) these helpers build the real object, so the driver is exercised
# against the same attribute names Azure actually returns. Only the operation
# groups that would perform HTTP are doubled.
module AzureDoubles
  RESOURCES = Azure::Resources2::Profiles::Latest::Mgmt
  NETWORK = Azure::Network2::Profiles::Latest::Mgmt

  # A doubled resource management client.
  #
  # @param resource_groups [Object] stand-in for the resource groups operations.
  # @param deployments [Object] stand-in for the deployments operations.
  # @param deployment_operations [Object] stand-in for the deployment operations.
  # @return [RSpec::Mocks::InstanceVerifyingDouble]
  def resource_client_double(resource_groups: resource_groups_double,
    deployments: deployments_double,
    deployment_operations: deployment_operations_double)
    instance_double(RESOURCES::Client, resource_groups:, deployments:, deployment_operations:)
  end

  # @param exists [Boolean] what +check_existence+ reports.
  # @return [RSpec::Mocks::InstanceVerifyingDouble]
  def resource_groups_double(exists: true)
    instance_double(RESOURCES::ResourceGroups, check_existence: exists, create_or_update: nil, begin_delete: nil)
  end

  # @param provisioning_state [String] the state reported by +get+.
  # @return [RSpec::Mocks::InstanceVerifyingDouble]
  def deployments_double(provisioning_state: "Succeeded")
    instance_double(
      RESOURCES::Deployments,
      begin_create_or_update_async: accepted_request,
      get: deployment_extended(provisioning_state)
    )
  end

  # @param operations [Array] deployment operations returned by +list+.
  # @return [RSpec::Mocks::InstanceVerifyingDouble]
  def deployment_operations_double(operations: [])
    instance_double(RESOURCES::DeploymentOperations, list: operations)
  end

  # The value returned by the SDK's +*_async+ methods: something answering
  # +value!+ once the request has been accepted.
  #
  # @return [RSpec::Mocks::Double]
  def accepted_request
    double("MsRest::Promise", value!: nil)
  end

  # A real +DeploymentExtended+ carrying a provisioning state.
  #
  # @param provisioning_state [String]
  # @return [Azure::Resources2::Profiles::Latest::Mgmt::Models::DeploymentExtended]
  def deployment_extended(provisioning_state)
    deployment = RESOURCES::Models::DeploymentExtended.new
    deployment.properties = RESOURCES::Models::DeploymentPropertiesExtended.new
    deployment.properties.provisioning_state = provisioning_state
    deployment
  end

  # A real +DeploymentOperation+.
  #
  # @param provisioning_state [String] e.g. +"Running"+ or +"Succeeded"+.
  # @param status_code [String] e.g. +"OK"+ or +"Conflict"+.
  # @param status_message [String, nil] Azure's failure detail.
  # @param resource_name [String, nil] name of the resource being operated on.
  # @param resource_type [String, nil] type of the resource being operated on.
  # @return [Azure::Resources2::Profiles::Latest::Mgmt::Models::DeploymentOperation]
  def deployment_operation(provisioning_state: "Succeeded", status_code: "OK", status_message: nil,
    resource_name: nil, resource_type: nil)
    operation = RESOURCES::Models::DeploymentOperation.new
    operation.properties = RESOURCES::Models::DeploymentOperationProperties.new
    operation.properties.provisioning_state = provisioning_state
    operation.properties.status_code = status_code
    operation.properties.status_message = status_message

    if resource_name || resource_type
      operation.properties.target_resource = RESOURCES::Models::TargetResource.new
      operation.properties.target_resource.resource_name = resource_name
      operation.properties.target_resource.resource_type = resource_type
    end

    operation
  end

  # A doubled network management client.
  #
  # @param public_ipaddresses [Object] stand-in for the public IP operations.
  # @return [RSpec::Mocks::InstanceVerifyingDouble]
  def network_client_double(public_ipaddresses: public_ip_addresses_double)
    instance_double(NETWORK::Client, public_ipaddresses:)
  end

  # @param ip_address [String] the address reported by +get+.
  # @param fqdn [String] the DNS name reported by +get+.
  # @return [RSpec::Mocks::InstanceVerifyingDouble]
  def public_ip_addresses_double(ip_address: "40.121.0.1", fqdn: "kitchen-abc.eastus2.cloudapp.azure.com")
    instance_double(NETWORK::PublicIPAddresses, get: public_ip(ip_address:, fqdn:))
  end

  # @param ip_address [String]
  # @param fqdn [String]
  # @return [RSpec::Mocks::Double]
  def public_ip(ip_address: "40.121.0.1", fqdn: "kitchen-abc.eastus2.cloudapp.azure.com")
    double("PublicIPAddress", ip_address:, dns_settings: double("PublicIPAddressDnsSettings", fqdn:))
  end

  # @param private_ip [String] the address of the NIC's first IP configuration.
  # @return [RSpec::Mocks::Double]
  def network_interface(private_ip: "10.0.0.4")
    double("NetworkInterface", ip_configurations: [double("IPConfiguration", private_ipaddress: private_ip)])
  end

  # An +MsRestAzure2::AzureOperationError+ carrying an Azure error body.
  #
  # @param code [String] the Azure error code, e.g. +"DeploymentActive"+.
  # @param message [String] the Azure error message.
  # @return [MsRestAzure2::AzureOperationError]
  def azure_operation_error(code:, message: "something went wrong")
    error = MsRestAzure2::AzureOperationError.new("Azure operation failed")
    error.body = { "error" => { "code" => code, "message" => message } }
    error
  end

  # Wires a driver up so that every Azure client it constructs is a double.
  #
  # @param driver [Kitchen::Driver::Azurerm]
  # @param resource_client [Object]
  # @param network_client [Object]
  # @return [void]
  def stub_azure_clients(driver, resource_client: resource_client_double, network_client: network_client_double)
    allow(RESOURCES::Client).to receive(:new).and_return(resource_client)
    allow(NETWORK::Client).to receive(:new).and_return(network_client)
    allow(Kitchen::Driver::AzureCredentials).to receive(:new).and_return(
      instance_double(Kitchen::Driver::AzureCredentials, azure_options: { subscription_id: driver_config(driver)[:subscription_id] })
    )
  end
end
