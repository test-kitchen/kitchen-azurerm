RSpec.describe Kitchen::Driver::Azure::Http do
  let(:url) { "https://example.invalid/thing" }

  describe ".request" do
    it "returns the status and body" do
      stub_request(:get, url).to_return(status: 200, body: "hello")

      response = described_class.request(method: :get, url:)
      expect(response.status).to eq(200)
      expect(response.body).to eq("hello")
    end

    it "sends the headers it is given" do
      stub = stub_request(:get, url).with(headers: { "Authorization" => "Bearer t" }).to_return(status: 200)
      described_class.request(method: :get, url:, headers: { "Authorization" => "Bearer t" })
      expect(stub).to have_been_requested
    end

    it "sends a body when given one" do
      stub = stub_request(:put, url).with(body: "payload").to_return(status: 200)
      described_class.request(method: :put, url:, body: "payload")
      expect(stub).to have_been_requested
    end

    %i{get head put post delete}.each do |verb|
      it "supports #{verb.upcase}" do
        stub_request(verb, url).to_return(status: 200)
        expect(described_class.request(method: verb, url:).status).to eq(200)
      end
    end

    it "rejects an unsupported method rather than guessing" do
      expect { described_class.request(method: :patch, url:) }
        .to raise_error(ArgumentError, /Unsupported HTTP method/)
    end

    # Network blips must be distinguishable from real Azure responses so the
    # driver knows which are worth retrying.
    {
      "a connection timeout" => Net::OpenTimeout,
      "a read timeout" => Net::ReadTimeout,
      "a connection reset" => Errno::ECONNRESET,
      "a refused connection" => Errno::ECONNREFUSED,
      "a DNS failure" => SocketError,
      "a TLS failure" => OpenSSL::SSL::SSLError,
    }.each do |description, error_class|
      it "reports #{description} as transient" do
        stub_request(:get, url).to_raise(error_class)

        expect { described_class.request(method: :get, url:) }
          .to raise_error(Kitchen::Driver::Azure::TransientError, /#{error_class}/)
      end
    end

    # Corporate networks routinely put a proxy in front of Azure.
    it "routes through the proxy named by the environment" do
      ENV["https_proxy"] = "http://proxy.invalid:8080"
      expect(Net::HTTP).to receive(:new)
        .with("example.invalid", 443, "proxy.invalid", 8080, nil, nil)
        .and_call_original

      stub_request(:get, url).to_return(status: 200)
      described_class.request(method: :get, url:)
    end

    it "connects directly when the host is excluded from proxying" do
      ENV["https_proxy"] = "http://proxy.invalid:8080"
      ENV["no_proxy"] = "example.invalid"
      expect(Net::HTTP).to receive(:new).with("example.invalid", 443).and_call_original

      stub_request(:get, url).to_return(status: 200)
      described_class.request(method: :get, url:)
    end

    it "does not treat an HTTP error status as transient" do
      stub_request(:get, url).to_return(status: 500, body: "server error")
      expect(described_class.request(method: :get, url:).status).to eq(500)
    end
  end

  describe Kitchen::Driver::Azure::Http::Response do
    it "is successful for 2xx" do
      expect(described_class.new(204, "")).to be_success
    end

    it "is not successful for 4xx" do
      expect(described_class.new(404, "")).not_to be_success
    end

    it "parses a JSON body" do
      expect(described_class.new(200, '{"a":1}').json).to eq("a" => 1)
    end

    it "is nil for an empty body" do
      expect(described_class.new(204, "").json).to be_nil
    end

    it "is nil rather than raising for a non-JSON body" do
      expect(described_class.new(500, "<html>nope</html>").json).to be_nil
    end
  end
end
