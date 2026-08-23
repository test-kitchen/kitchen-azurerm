RSpec.describe Kitchen::Driver::Azure::ArmClient do
  subject(:client) do
    described_class.new(subscription_id:, environment:, token_provider: token_provider_double)
  end

  let(:subscription_id) { "115b12cb-b0d3-4ed9-94db-f73733be6f3c" }
  let(:environment) { Kitchen::Driver::Azure::Environments.fetch("Azure") }
  let(:base) { "https://management.azure.com/subscriptions/#{subscription_id}" }
  let(:resources_version) { described_class::RESOURCES_API_VERSION }
  let(:network_version) { described_class::NETWORK_API_VERSION }

  def token_provider_double
    instance_double(Kitchen::Driver::Azure::TokenProvider, authorization_header: "Bearer a-token")
  end

  describe "request framing" do
    it "authenticates every request" do
      stub = stub_request(:get, "#{base}/resourcegroups/rg/providers/Microsoft.Resources/deployments/d")
        .with(query: { "api-version" => resources_version }, headers: { "Authorization" => "Bearer a-token" })
        .to_return(status: 200, body: "{}")

      client.deployment("rg", "d")
      expect(stub).to have_been_requested
    end

    it "identifies itself" do
      stub = stub_request(:get, %r{/deployments/d})
        .with(headers: { "User-Agent" => "kitchen-azurerm/#{Kitchen::Driver::AZURERM_VERSION}" })
        .to_return(status: 200, body: "{}")

      client.deployment("rg", "d")
      expect(stub).to have_been_requested
    end

    it "escapes names that need it" do
      stub = stub_request(:head, "#{base}/resourcegroups/my%20group")
        .with(query: hash_including({}))
        .to_return(status: 204)

      client.resource_group_exists?("my group")
      expect(stub).to have_been_requested
    end
  end

  describe "#resource_group_exists?" do
    it "is true for a 204" do
      stub_request(:head, "#{base}/resourcegroups/rg").with(query: hash_including({})).to_return(status: 204)
      expect(client.resource_group_exists?("rg")).to be true
    end

    # A 404 is the API's way of saying "no", not a failure.
    it "is false for a 404" do
      stub_request(:head, "#{base}/resourcegroups/rg").with(query: hash_including({})).to_return(status: 404)
      expect(client.resource_group_exists?("rg")).to be false
    end

    it "raises for anything else" do
      stub_request(:head, "#{base}/resourcegroups/rg").with(query: hash_including({})).to_return(status: 403)
      expect { client.resource_group_exists?("rg") }.to raise_error(Kitchen::Driver::Azure::OperationError)
    end
  end

  describe "#create_or_update_resource_group" do
    it "PUTs the location and tags" do
      stub = stub_request(:put, "#{base}/resourcegroups/rg")
        .with(query: hash_including({}),
          body: { "location" => "eastus2", "tags" => { "owner" => "platform" } },
          headers: { "Content-Type" => "application/json" })
        .to_return(status: 200, body: '{"id":"/subscriptions/s/resourcegroups/rg"}')

      result = client.create_or_update_resource_group("rg", location: "eastus2", tags: { "owner" => "platform" })
      expect(stub).to have_been_requested
      expect(result["id"]).to eq("/subscriptions/s/resourcegroups/rg")
    end

    it "sends an empty tag object when given none" do
      stub = stub_request(:put, "#{base}/resourcegroups/rg")
        .with(query: hash_including({}), body: { "location" => "eastus2", "tags" => {} })
        .to_return(status: 200, body: "{}")

      client.create_or_update_resource_group("rg", location: "eastus2", tags: nil)
      expect(stub).to have_been_requested
    end
  end

  describe "#delete_resource_group" do
    it "DELETEs and returns without waiting" do
      stub = stub_request(:delete, "#{base}/resourcegroups/rg").with(query: hash_including({})).to_return(status: 202)
      expect(client.delete_resource_group("rg")).to be_nil
      expect(stub).to have_been_requested
    end
  end

  describe "#create_deployment" do
    it "PUTs the deployment body" do
      body = { "properties" => { "mode" => "Incremental", "template" => { "resources" => [] } } }
      stub = stub_request(:put, "#{base}/resourcegroups/rg/providers/Microsoft.Resources/deployments/deploy-1")
        .with(query: { "api-version" => resources_version }, body:)
        .to_return(status: 201, body: '{"id":"/deployments/deploy-1"}')

      client.create_deployment("rg", "deploy-1", body)
      expect(stub).to have_been_requested
    end
  end

  describe "#deployment_operations" do
    it "unwraps the value array" do
      stub_request(:get, "#{base}/resourcegroups/rg/providers/Microsoft.Resources/deployments/d/operations")
        .with(query: hash_including({}))
        .to_return(status: 200, body: '{"value":[{"properties":{"statusCode":"OK"}}]}')

      expect(client.deployment_operations("rg", "d")).to eq([{ "properties" => { "statusCode" => "OK" } }])
    end

    it "is an empty array when ARM returns no value key" do
      stub_request(:get, %r{/operations}).to_return(status: 200, body: "{}")
      expect(client.deployment_operations("rg", "d")).to eq([])
    end

    it "is an empty array when ARM returns something that is not an object" do
      stub_request(:get, %r{/operations}).to_return(status: 200, body: "[]")
      expect(client.deployment_operations("rg", "d")).to eq([])
    end
  end

  describe "network resources" do
    it "reads a public IP with the network API version" do
      stub = stub_request(:get, "#{base}/resourcegroups/rg/providers/Microsoft.Network/publicIPAddresses/publicip")
        .with(query: { "api-version" => network_version })
        .to_return(status: 200, body: '{"properties":{"ipAddress":"40.121.0.1"}}')

      expect(client.public_ip("rg", "publicip").dig("properties", "ipAddress")).to eq("40.121.0.1")
      expect(stub).to have_been_requested
    end

    it "reads a network interface" do
      stub_request(:get, "#{base}/resourcegroups/rg/providers/Microsoft.Network/networkInterfaces/nic-1")
        .with(query: hash_including({}))
        .to_return(status: 200, body: '{"name":"nic-1"}')

      expect(client.network_interface("rg", "nic-1")["name"]).to eq("nic-1")
    end
  end

  describe "error handling" do
    it "surfaces the Azure error code" do
      stub_request(:put, %r{/deployments/d}).to_return(
        status: 409,
        body: '{"error":{"code":"DeploymentActive","message":"already running"}}'
      )

      expect { client.create_deployment("rg", "d", {}) }
        .to raise_error(Kitchen::Driver::Azure::OperationError) { |e|
          expect(e.code).to eq("DeploymentActive")
          expect(e.status).to eq(409)
          expect(e.body.dig("error", "message")).to eq("already running")
        }
    end

    it "synthesizes a body when Azure returns something unparseable" do
      stub_request(:get, %r{/deployments/d}).to_return(status: 500, body: "<html>gateway blew up</html>")

      expect { client.deployment("rg", "d") }
        .to raise_error(Kitchen::Driver::Azure::OperationError) { |e|
          expect(e.code).to eq("Unknown")
          expect(e.body.dig("error", "message")).to include("gateway blew up")
        }
    end

    it "names the operation that failed" do
      stub_request(:delete, %r{/resourcegroups/rg}).to_return(status: 403, body: "{}")
      expect { client.delete_resource_group("rg") }.to raise_error(/HTTP 403 for DELETE/)
    end
  end

  describe "sovereign clouds" do
    let(:environment) { Kitchen::Driver::Azure::Environments.fetch("AzureUSGovernment") }

    it "targets that cloud's resource manager" do
      stub = stub_request(:get, "https://management.usgovcloudapi.net/subscriptions/#{subscription_id}/resourcegroups/rg/providers/Microsoft.Resources/deployments/d")
        .with(query: hash_including({}))
        .to_return(status: 200, body: "{}")

      client.deployment("rg", "d")
      expect(stub).to have_been_requested
    end
  end
end
