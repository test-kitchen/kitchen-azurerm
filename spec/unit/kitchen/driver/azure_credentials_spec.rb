require "spec_helper"

describe Kitchen::Driver::AzureCredentials do
  CLIENT_ID_AND_SECRET_SUB = 0
  CLIENT_ID_SUB = 1
  NO_CLIENT_SUB = 2

  let(:instance) do
    opts = {}
    opts[:subscription_id] = subscription_id
    opts[:environment] = environment if environment
    described_class.new(**opts)
  end

  let(:environment) { "Azure" }
  let(:fixtures_path) { File.expand_path("../../../../fixtures", __FILE__) }
  let(:subscription_id) { ini_credentials.sections[CLIENT_ID_AND_SECRET_SUB] }
  let(:client_id) { ini_credentials[subscription_id]["client_id"] }
  let(:client_secret) { ini_credentials[subscription_id]["client_secret"] }
  let(:tenant_id) { ini_credentials[subscription_id]["tenant_id"] }
  let(:config_path) { File.expand_path(described_class::CONFIG_PATH) }
  let(:ini_credentials) { IniFile.load("#{fixtures_path}/azure_credentials") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("AZURE_CONFIG_FILE").and_return(nil)
    allow(ENV).to receive(:[]).with("AZURE_TENANT_ID").and_return(nil)
    allow(ENV).to receive(:[]).with("AZURE_CLIENT_ID").and_return(nil)
    allow(ENV).to receive(:[]).with("AZURE_CLIENT_SECRET").and_return(nil)

    allow(File).to receive(:file?).and_call_original
    allow(File).to receive(:file?).with(config_path).and_return(true)

    allow(IniFile).to receive(:load).with(config_path).and_return(ini_credentials)
  end

  subject { instance }

  it { is_expected.to respond_to(:subscription_id) }
  it { is_expected.to respond_to(:environment) }
  it { is_expected.to respond_to(:azure_options) }

  describe "::new" do
    it "sets subscription_id" do
      expect(subject.subscription_id).to eq(subscription_id)
    end

    context "when an environment is provided" do
      let(:environment) { "AzureChina" }

      it "sets environment, when one is provided" do
        expect(subject.environment).to eq(environment)
      end
    end

    context "no environment is provided" do
      let(:environment) { nil }

      it "sets Azure as the environment" do
        expect(subject.environment).to eq("Azure")
      end
    end
  end

  describe "#azure_options" do
    subject { azure_options }

    let(:azure_options) { instance.azure_options }
    let(:credentials) { azure_options[:credentials] }
    let(:token_provider) { credentials.instance_variable_get(:@token_provider) }
    let(:active_directory_settings) { azure_options[:active_directory_settings] }

    context "when environment is Azure" do
      let(:environment) { "Azure" }

      its([:base_url]) { is_expected.to eq("https://management.azure.com/") }

      context "active_directory_settings" do
        it "sets the authentication_endpoint correctly" do
          expect(active_directory_settings.authentication_endpoint).to eq("https://login.microsoftonline.com/")
        end

        it "sets the token_audience correctly" do
          expect(active_directory_settings.token_audience).to eq("https://management.core.windows.net/")
        end
      end
    end

    context "when environment is AzureUSGovernment" do
      let(:environment) { "AzureUSGovernment" }

      its([:base_url]) { is_expected.to eq("https://management.usgovcloudapi.net") }

      context "active_directory_settings" do
        it "sets the authentication_endpoint correctly" do
          expect(active_directory_settings.authentication_endpoint).to eq("https://login-us.microsoftonline.com/")
        end

        it "sets the token_audience correctly" do
          expect(active_directory_settings.token_audience).to eq("https://management.core.usgovcloudapi.net/")
        end
      end
    end

    context "when environment is AzureChina" do
      let(:environment) { "AzureChina" }

      its([:base_url]) { is_expected.to eq("https://management.chinacloudapi.cn") }

      context "active_directory_settings" do
        it "sets the authentication_endpoint correctly" do
          expect(active_directory_settings.authentication_endpoint).to eq("https://login.chinacloudapi.cn/")
        end

        it "sets the token_audience correctly" do
          expect(active_directory_settings.token_audience).to eq("https://management.core.chinacloudapi.cn/")
        end
      end
    end

    context "when environment is AzureGermanCloud" do
      let(:environment) { "AzureGermanCloud" }

      its([:base_url]) { is_expected.to eq("https://management.microsoftazure.de") }

      context "active_directory_settings" do
        it "sets the authentication_endpoint correctly" do
          expect(active_directory_settings.authentication_endpoint).to eq("https://login.microsoftonline.de/")
        end

        it "sets the token_audience correctly" do
          expect(active_directory_settings.token_audience).to eq("https://management.core.cloudapi.de/")
        end
      end
    end

    shared_examples "common option specs" do
      it { is_expected.to be_instance_of(Hash) }
      its([:tenant_id]) { is_expected.to eq(tenant_id) }
      its([:subscription_id]) { is_expected.to eq(subscription_id) }
      its([:credentials]) { is_expected.to be_instance_of(MsRest::TokenCredentials) }
      its([:client_id]) { is_expected.to eq(client_id) }
      its([:client_secret]) { is_expected.to eq(client_secret) }
      its([:base_url]) { is_expected.to eq("https://management.azure.com/") }
    end

    context "when using client_id and client_secret" do
      let(:subscription_id) { ini_credentials.sections[CLIENT_ID_AND_SECRET_SUB] }

      include_examples "common option specs"

      it "uses token provider: MsRestAzure::ApplicationTokenProvider" do
        expect(token_provider).to be_instance_of(MsRestAzure::ApplicationTokenProvider)
      end

      it "sets the client_id" do
        expect(token_provider.instance_variables).to include(:@client_id)
        expect(token_provider.send(:client_id)).to eq(client_id)
      end

      it "sets the client_secret" do
        expect(token_provider.instance_variables).to include(:@client_secret)
        expect(token_provider.send(:client_secret)).to eq(client_secret)
      end
    end

    context "when using client_id, without client_secret" do
      let(:subscription_id) { ini_credentials.sections[CLIENT_ID_SUB] }

      include_examples "common option specs"

      it "uses token provider: MsRestAzure::MSITokenProvider" do
        expect(token_provider).to be_instance_of(MsRestAzure::MSITokenProvider)
      end

      it "sets the client_id" do
        expect(token_provider.instance_variables).to include(:@client_id)
        expect(token_provider.send(:client_id)).to eq(client_id)
      end

      it "does not set client_secret" do
        expect(token_provider.instance_variables).not_to include(:@client_secret)
      end
    end

    context "when not using client_id or client_secret" do
      let(:subscription_id) { ini_credentials.sections[NO_CLIENT_SUB] }

      include_examples "common option specs"

      it "uses token provider: MsRestAzure::MSITokenProvider" do
        expect(token_provider).to be_instance_of(MsRestAzure::MSITokenProvider)
      end

      it "does not set the client_id" do
        expect(token_provider.instance_variables).not_to include(:@client_id)
      end

      it "does not set client_secret" do
        expect(token_provider.instance_variables).not_to include(:@client_secret)
      end
    end
  end
end
