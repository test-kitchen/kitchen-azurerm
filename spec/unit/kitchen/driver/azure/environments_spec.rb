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

  it "freezes the table so a caller cannot mutate shared endpoints" do
    expect(described_class::ALL).to be_frozen
  end
end
