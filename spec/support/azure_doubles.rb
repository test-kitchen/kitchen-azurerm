# Doubles and fixtures standing in for Azure Resource Manager responses.
#
# The driver now talks to ARM over plain HTTP, so responses are ordinary parsed
# JSON. These helpers build that JSON in ARM's own shape - camelCase, nested
# under "properties" - so a spec that passes here is asserting against the
# structure Azure actually returns.
module AzureDoubles
  # A doubled ARM client.
  #
  # @param overrides [Hash] method name to return value.
  # @return [RSpec::Mocks::InstanceVerifyingDouble]
  def arm_client_double(**overrides)
    defaults = {
      resource_group_exists?: true,
      subscription: { "subscriptionId" => "115b12cb-b0d3-4ed9-94db-f73733be6f3c" },
      create_or_update_resource_group: { "id" => "/subscriptions/s/resourcegroups/rg" },
      delete_resource_group: nil,
      create_deployment: { "id" => "/deployments/d" },
      deployment: deployment_response("Succeeded"),
      deployment_operations: [],
      public_ip: public_ip_response,
      network_interface: network_interface_response,
      virtual_machine_instance_view: instance_view_response,
    }
    instance_double(Kitchen::Driver::Azure::ArmClient, **defaults.merge(overrides))
  end

  # An ARM deployment response.
  #
  # @param provisioning_state [String] e.g. +"Running"+ or +"Succeeded"+.
  # @return [Hash]
  def deployment_response(provisioning_state)
    { "properties" => { "provisioningState" => provisioning_state } }
  end

  # One entry from a deployment's operations list.
  #
  # @param provisioning_state [String]
  # @param status_code [String] e.g. +"OK"+ or +"Conflict"+.
  # @param status_message [String, nil] Azure's failure detail.
  # @param resource_name [String, nil]
  # @param resource_type [String, nil]
  # @return [Hash]
  def deployment_operation(provisioning_state: "Succeeded", status_code: "OK", status_message: nil,
    resource_name: nil, resource_type: nil)
    properties = {
      "provisioningState" => provisioning_state,
      "statusCode" => status_code,
      "statusMessage" => status_message,
    }

    if resource_name || resource_type
      properties["targetResource"] = { "resourceName" => resource_name, "resourceType" => resource_type }
    end

    { "properties" => properties }
  end

  # A public IP address resource.
  #
  # @param ip_address [String]
  # @param fqdn [String]
  # @return [Hash]
  def public_ip_response(ip_address: "40.121.0.1", fqdn: "kitchen-abc.eastus2.cloudapp.azure.com")
    {
      "name" => "publicip",
      "properties" => {
        "ipAddress" => ip_address,
        "dnsSettings" => { "fqdn" => fqdn },
      },
    }
  end

  # A virtual machine instance view.
  #
  # @param code [String] a status code, e.g. +"PowerState/running"+.
  # @param display_status [String] Azure's human-readable wording.
  # @return [Hash]
  def instance_view_response(code = "PowerState/running", display_status = "VM running")
    {
      "statuses" => [
        { "code" => "ProvisioningState/succeeded", "displayStatus" => "Provisioning succeeded" },
        { "code" => code, "displayStatus" => display_status },
      ],
    }
  end

  # A network interface resource.
  #
  # @param private_ip [String]
  # @return [Hash]
  def network_interface_response(private_ip: "10.0.0.4")
    {
      "name" => "nic",
      "properties" => {
        "ipConfigurations" => [
          { "properties" => { "privateIPAddress" => private_ip } },
        ],
      },
    }
  end

  # An ARM error.
  #
  # @param code [String] the Azure error code, e.g. +"DeploymentActive"+.
  # @param message [String]
  # @param status [Integer] HTTP status.
  # @return [Kitchen::Driver::Azure::OperationError]
  def azure_operation_error(code:, message: "something went wrong", status: 409)
    Kitchen::Driver::Azure::OperationError.new(
      "Azure returned HTTP #{status}",
      status:,
      body: { "error" => { "code" => code, "message" => message } }
    )
  end

  # Wires a driver up so the ARM client it builds is a double.
  #
  # @param driver [Kitchen::Driver::Azurerm]
  # @param arm_client [Object]
  # @return [Object] the client the driver will use.
  def stub_arm_client(driver, arm_client: arm_client_double)
    allow(Kitchen::Driver::AzureCredentials).to receive(:new).and_return(
      instance_double(Kitchen::Driver::AzureCredentials, arm_client:)
    )
    arm_client
  end
end
