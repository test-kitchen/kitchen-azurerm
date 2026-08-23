RSpec.describe Kitchen::Driver::Azure::Environments do
  describe ".fetch" do
    it "resolves a cloud by name" do
      expect(described_class.fetch("AzureChina").name).to eq("AzureChina")
    end

    it "is case-insensitive" do
      expect(described_class.fetch("azureusgovernment").name).to eq("AzureUSGovernment")
    end

    it "rejects an unknown cloud with the valid values" do
      expect { described_class.fetch("AzureAtlantis") }
        .to raise_error(Kitchen::UserError, /Unknown azure_environment 'AzureAtlantis'.*Azure, AzureUSGovernment, AzureChina, AzureGermanCloud/m)
    end
  end

  describe ".names" do
    it "lists every supported cloud" do
      expect(described_class.names).to contain_exactly("Azure", "AzureUSGovernment", "AzureChina", "AzureGermanCloud")
    end
  end

  describe "#token_url" do
    it "joins the authentication endpoint, tenant and oauth2 path" do
      expect(described_class.fetch("Azure").token_url("a-tenant"))
        .to eq("https://login.microsoftonline.com/a-tenant/oauth2/token")
    end

    it "does not double up the separator" do
      expect(described_class.fetch("AzureChina").token_url("t")).not_to include("//t")
    end
  end

  describe "#token_url_v2" do
    it "targets the v2.0 endpoint, which federated credentials require" do
      expect(described_class.fetch("Azure").token_url_v2("a-tenant"))
        .to eq("https://login.microsoftonline.com/a-tenant/oauth2/v2.0/token")
    end
  end

  describe "#default_scope" do
    {
      "Azure" => "https://management.azure.com/.default",
      "AzureUSGovernment" => "https://management.usgovcloudapi.net/.default",
      "AzureChina" => "https://management.chinacloudapi.cn/.default",
      "AzureGermanCloud" => "https://management.microsoftazure.de/.default",
    }.each do |cloud, scope|
      it "is #{scope} for #{cloud}" do
        expect(described_class.fetch(cloud).default_scope).to eq(scope)
      end
    end

    it "never doubles the separator" do
      described_class.names.each do |cloud|
        expect(described_class.fetch(cloud).default_scope).not_to include("//.default")
      end
    end
  end

  describe "#with_authority" do
    subject(:environment) { described_class.fetch("Azure") }

    it "replaces the Entra ID endpoint" do
      expect(environment.with_authority("https://login.example.invalid/").authentication_endpoint)
        .to eq("https://login.example.invalid/")
    end

    it "leaves everything else untouched" do
      overridden = environment.with_authority("https://login.example.invalid/")
      expect(overridden.name).to eq("Azure")
      expect(overridden.resource_manager_url).to eq(environment.resource_manager_url)
      expect(overridden.token_audience).to eq(environment.token_audience)
    end

    it "returns the same object when given nothing" do
      expect(environment.with_authority(nil)).to equal(environment)
      expect(environment.with_authority("")).to equal(environment)
    end

    it "does not mutate the shared table" do
      environment.with_authority("https://login.example.invalid/")
      expect(described_class.fetch("Azure").authentication_endpoint).to eq("https://login.microsoftonline.com/")
    end
  end

  it "freezes the table so a caller cannot mutate shared endpoints" do
    expect(described_class::ALL).to be_frozen
  end
end
