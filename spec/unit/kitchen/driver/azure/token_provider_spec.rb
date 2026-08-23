RSpec.describe "Azure token providers" do
  let(:environment) { Kitchen::Driver::Azure::Environments.fetch("Azure") }

  describe Kitchen::Driver::Azure::TokenProvider do
    it "is abstract - a subclass must say how to fetch a token" do
      expect { described_class.new(environment:).access_token }.to raise_error(NotImplementedError)
    end
  end

  describe Kitchen::Driver::Azure::ServicePrincipalToken do
    subject(:provider) do
      described_class.new(environment:, tenant_id: "a-tenant", client_id: "a-client", client_secret: "a-secret")
    end

    let(:token_url) { "https://login.microsoftonline.com/a-tenant/oauth2/token" }

    it "posts a client_credentials grant for the ARM audience" do
      stub = stub_request(:post, token_url)
        .with(body: {
                "grant_type" => "client_credentials",
                "client_id" => "a-client",
                "client_secret" => "a-secret",
                "resource" => "https://management.core.windows.net/",
              })
        .to_return(status: 200, body: '{"access_token":"tok","expires_in":"3599"}')

      expect(provider.access_token).to eq("tok")
      expect(stub).to have_been_requested
    end

    it "formats an Authorization header" do
      stub_request(:post, token_url).to_return(status: 200, body: '{"access_token":"tok","expires_in":"3599"}')
      expect(provider.authorization_header).to eq("Bearer tok")
    end

    it "caches the token rather than fetching per request" do
      stub = stub_request(:post, token_url).to_return(status: 200, body: '{"access_token":"tok","expires_in":"3599"}')

      3.times { provider.access_token }
      expect(stub).to have_been_requested.once
    end

    # A long deployment must not fail because the token aged out mid-flight.
    it "refetches once the cached token is near expiry" do
      stub = stub_request(:post, token_url)
        .to_return({ status: 200, body: '{"access_token":"first","expires_in":"60"}' },
          { status: 200, body: '{"access_token":"second","expires_in":"3599"}' })

      expect(provider.access_token).to eq("first")
      expect(provider.access_token).to eq("second")
      expect(stub).to have_been_requested.twice
    end

    it "honours an absolute expires_on" do
      stub_request(:post, token_url)
        .to_return(status: 200, body: %({"access_token":"tok","expires_on":"#{Time.now.to_i + 3600}"}))

      expect(provider.access_token).to eq("tok")
    end

    it "raises with the status when the endpoint rejects the credentials" do
      stub_request(:post, token_url).to_return(status: 401, body: '{"error":"invalid_client"}')

      expect { provider.access_token }
        .to raise_error(Kitchen::Driver::Azure::OperationError, /service principal token endpoint \(HTTP 401\)/)
    end

    it "raises when the response carries no token" do
      stub_request(:post, token_url).to_return(status: 200, body: "{}")
      expect { provider.access_token }.to raise_error(Kitchen::Driver::Azure::OperationError)
    end

    it "raises when the response is not an object at all" do
      stub_request(:post, token_url).to_return(status: 200, body: "[]")
      expect { provider.access_token }
        .to raise_error(Kitchen::Driver::Azure::OperationError) { |e| expect(e.body).to eq({}) }
    end

    context "in a sovereign cloud" do
      let(:environment) { Kitchen::Driver::Azure::Environments.fetch("AzureChina") }

      it "authenticates against that cloud's endpoint and audience" do
        stub = stub_request(:post, "https://login.chinacloudapi.cn/a-tenant/oauth2/token")
          .with(body: hash_including("resource" => "https://management.core.chinacloudapi.cn/"))
          .to_return(status: 200, body: '{"access_token":"tok","expires_in":"3599"}')

        provider.access_token
        expect(stub).to have_been_requested
      end
    end
  end

  describe Kitchen::Driver::Azure::ManagedIdentityToken do
    subject(:provider) { described_class.new(environment:) }

    let(:imds) { "http://169.254.169.254/metadata/identity/oauth2/token" }

    # The old SDK used the legacy MSI extension endpoint on port 50342; IMDS is
    # the supported endpoint on modern Azure VMs.
    it "asks the instance metadata service" do
      stub = stub_request(:get, imds)
        .with(query: { "api-version" => "2018-02-01", "resource" => "https://management.core.windows.net/" },
          headers: { "Metadata" => "true" })
        .to_return(status: 200, body: '{"access_token":"tok","expires_in":"3599"}')

      expect(provider.access_token).to eq("tok")
      expect(stub).to have_been_requested
    end

    it "sends no client_id for a system-assigned identity" do
      stub_request(:get, imds).with(query: hash_excluding("client_id")).to_return(status: 200, body: '{"access_token":"tok"}')
      expect(provider.access_token).to eq("tok")
    end

    context "with a user-assigned identity" do
      subject(:provider) { described_class.new(environment:, client_id: "an-identity") }

      it "names the identity" do
        stub = stub_request(:get, imds)
          .with(query: hash_including("client_id" => "an-identity"))
          .to_return(status: 200, body: '{"access_token":"tok"}')

        provider.access_token
        expect(stub).to have_been_requested
      end
    end

    it "raises when there is no metadata service to talk to" do
      stub_request(:get, imds).with(query: hash_including({})).to_return(status: 400, body: '{"error":"invalid_request"}')
      expect { provider.access_token }.to raise_error(Kitchen::Driver::Azure::OperationError, /instance metadata service/)
    end
  end

  describe Kitchen::Driver::Azure::AzureCliToken do
    subject(:provider) { described_class.new(environment:) }

    let(:success) { instance_double(Process::Status, success?: true) }
    let(:failure) { instance_double(Process::Status, success?: false) }

    it "shells out for the ARM audience" do
      expect(Open3).to receive(:capture3).with(
        "az", "account", "get-access-token",
        "--resource", "https://management.core.windows.net/",
        "--output", "json"
      ).and_return(['{"accessToken":"tok","expiresOn":"2099-01-01 00:00:00.000000"}', "", success])

      expect(provider.access_token).to eq("tok")
    end

    it "caches the result rather than shelling out per request" do
      allow(Open3).to receive(:capture3)
        .and_return(['{"accessToken":"tok","expiresOn":"2099-01-01 00:00:00.000000"}', "", success])

      3.times { provider.access_token }
      expect(Open3).to have_received(:capture3).once
    end

    it "tells the user to sign in when the CLI is not signed in" do
      allow(Open3).to receive(:capture3).and_return(["", "Please run 'az login'", failure])

      expect { provider.access_token }
        .to raise_error(Kitchen::Driver::Azure::OperationError, /Run `az login` first/)
    end

    it "explains when the CLI is not installed" do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

      expect { provider.access_token }
        .to raise_error(Kitchen::Driver::Azure::OperationError, /was not found on PATH/)
    end

    it "reports an unparseable response rather than crashing" do
      allow(Open3).to receive(:capture3).and_return(["not json", "", success])

      expect { provider.access_token }
        .to raise_error(Kitchen::Driver::Azure::OperationError, /Could not understand the response/)
    end

    it "honours a numeric expires_on from the CLI" do
      allow(Open3).to receive(:capture3)
        .and_return([%({"accessToken":"tok","expires_on":#{Time.now.to_i + 3600}}), "", success])

      expect(provider.access_token).to eq("tok")
    end

    it "falls back to a one hour lifetime when the expiry makes no sense" do
      allow(Open3).to receive(:capture3).and_return(['{"accessToken":"tok","expiresOn":"nonsense"}', "", success])
      expect(provider.access_token).to eq("tok")
    end
  end
end
