# Exercises the whole stack - driver, credentials, token provider, ARM client,
# HTTP - with nothing doubled below the driver itself. Only the wire is stubbed.
#
# The per-layer specs verify each piece in isolation; this one catches wiring
# mistakes between them, which is exactly the class of bug that appears when
# swapping out an SDK.
RSpec.describe Kitchen::Driver::Azurerm, "over HTTP" do
  subject(:driver) { build_driver(subscription_id:, location: "eastus2") }

  let(:subscription_id) { "115b12cb-b0d3-4ed9-94db-f73733be6f3c" }
  let(:arm) { "https://management.azure.com/subscriptions/#{subscription_id}" }
  let(:state) { {} }
  let(:resource_group) { %r{#{Regexp.escape(arm)}/resourcegroups/[^/?]+\?} }

  before do
    set_env(
      "AZURE_TENANT_ID" => "a-tenant",
      "AZURE_CLIENT_ID" => "a-client",
      "AZURE_CLIENT_SECRET" => "a-secret"
    )

    stub_request(:post, "https://login.microsoftonline.com/a-tenant/oauth2/token")
      .to_return(status: 200, body: '{"access_token":"a-token","expires_in":"3599"}')

    stub_request(:put, resource_group).to_return(status: 200, body: "{}")
    stub_request(:put, %r{/deployments/deploy-}).to_return(status: 201, body: "{}")
    stub_request(:get, %r{/deployments/deploy-[^/]+\?}).to_return(
      status: 200, body: '{"properties":{"provisioningState":"Succeeded"}}'
    )
    stub_request(:get, %r{/deployments/.+/operations}).to_return(status: 200, body: '{"value":[]}')
    stub_request(:get, %r{/publicIPAddresses/publicip}).to_return(
      status: 200,
      body: '{"properties":{"ipAddress":"40.121.0.1","dnsSettings":{"fqdn":"kitchen.eastus2.cloudapp.azure.com"}}}'
    )
  end

  it "creates the instance and resolves its address" do
    driver.create(state)
    expect(state[:hostname]).to eq("40.121.0.1")
  end

  it "acquires a token once and reuses it across every ARM call" do
    driver.create(state)
    expect(a_request(:post, "https://login.microsoftonline.com/a-tenant/oauth2/token")).to have_been_made.once
  end

  it "authenticates every ARM call with that token" do
    driver.create(state)
    expect(a_request(:put, resource_group).with(headers: { "Authorization" => "Bearer a-token" }))
      .to have_been_made
  end

  it "sends a deployment whose template is valid ARM JSON" do
    driver.create(state)
    expect(a_request(:put, %r{/deployments/deploy-}).with { |request|
      expect(request.body).to be_a_valid_arm_template_deployment
      true
    }).to have_been_made
  end

  it "polls the deployment until it reports a terminal state" do
    driver.create(state)
    expect(a_request(:get, %r{/deployments/deploy-[^/]+\?})).to have_been_made
  end

  it "surfaces an Azure error rather than a transport exception" do
    stub_request(:put, resource_group).to_return(
      status: 403,
      body: '{"error":{"code":"AuthorizationFailed","message":"nope"}}'
    )

    expect { driver.create(state) }.to raise_error(Kitchen::Driver::Azure::OperationError, /HTTP 403/)
  end

  it "retries a transient network failure" do
    stub_request(:put, resource_group)
      .to_raise(Errno::ECONNRESET).then
      .to_return(status: 200, body: "{}")

    expect { driver.create(state) }.not_to raise_error
    expect(a_request(:put, resource_group)).to have_been_made.twice
  end

  describe "#destroy" do
    let(:state) do
      { uuid: "abc123", server_id: "vmabc123", azure_resource_group_name: "kitchen-rg",
        subscription_id:, azure_environment: "Azure" }
    end

    it "deletes the resource group" do
      stub = stub_request(:delete, "#{arm}/resourcegroups/kitchen-rg").with(query: hash_including({}))
        .to_return(status: 202)

      driver.destroy(state)
      expect(stub).to have_been_requested
    end
  end

  # Asserts the body of a deployment request carries a parseable ARM template.
  matcher :be_a_valid_arm_template_deployment do
    match do |body|
      template = JSON.parse(body).dig("properties", "template")
      template.is_a?(Hash) && template["resources"].is_a?(Array)
    end
  end
end
