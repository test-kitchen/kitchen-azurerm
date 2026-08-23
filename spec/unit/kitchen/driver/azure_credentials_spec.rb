RSpec.describe Kitchen::Driver::AzureCredentials do
  subject(:credentials) { described_class.new(subscription_id:, environment:) }

  let(:subscription_id) { CredentialsFileHelper::SUBSCRIPTIONS[:service_principal] }
  let(:environment) { "Azure" }

  describe ".default_config_path" do
    it "resolves against the current home directory rather than the one present at load time" do
      first = described_class.default_config_path

      Dir.mktmpdir do |elsewhere|
        ENV["HOME"] = elsewhere
        expect(described_class.default_config_path).to eq(File.join(elsewhere, ".azure", "credentials"))
        expect(described_class.default_config_path).not_to eq(first)
      end
    end
  end

  describe "#initialize" do
    it "exposes the subscription id" do
      expect(credentials.subscription_id).to eq(subscription_id)
    end

    it "defaults the environment to Azure" do
      expect(described_class.new(subscription_id:).environment).to eq("Azure")
    end

    it "treats an explicit nil environment as Azure" do
      expect(described_class.new(subscription_id:, environment: nil).environment).to eq("Azure")
    end

    it "keeps a supplied environment" do
      expect(described_class.new(subscription_id:, environment: "AzureChina").environment).to eq("AzureChina")
    end

    it "rejects an unknown environment with an actionable message" do
      expect { described_class.new(subscription_id:, environment: "AzureAtlantis") }
        .to raise_error(Kitchen::UserError, /Unknown azure_environment 'AzureAtlantis'.*Azure, AzureUSGovernment, AzureChina, AzureGermanCloud/m)
    end

    it "accepts a known environment in any case" do
      expect { described_class.new(subscription_id:, environment: "AZUREUSGOVERNMENT") }.not_to raise_error
    end
  end

  describe "#config_path" do
    it "defaults to ~/.azure/credentials" do
      expect(credentials.config_path).to eq(described_class.default_config_path)
    end

    it "honours AZURE_CONFIG_FILE" do
      path = use_fixture_credentials_file
      expect(credentials.config_path).to eq(path)
    end

    it "expands a relative AZURE_CONFIG_FILE" do
      ENV["AZURE_CONFIG_FILE"] = "creds.ini"
      expect(credentials.config_path).to eq(File.expand_path("creds.ini"))
    end
  end

  describe "credential resolution" do
    subject(:provider) { credentials.token_provider }

    context "with no credentials file and no environment variables" do
      it "logs which path it looked in" do
        expect(Kitchen.logger).to receive(:debug).with(/#{Regexp.escape(described_class.default_config_path)} was not found/)
        provider
      end

      it "warns that it is falling back to the Azure CLI" do
        allow(Kitchen.logger).to receive(:warn)
        provider
        expect(Kitchen.logger).to have_received(:warn).with("Using tenant id set through `az login`.")
      end

      it "falls back to the Azure CLI token provider" do
        expect(provider).to be_an_instance_of(Kitchen::Driver::Azure::AzureCliToken)
      end
    end

    context "when reading the credentials file at its default location" do
      before { use_default_location_credentials_file }

      it "resolves the tenant id from the matching subscription section" do
        expect(tenant_id_of(provider)).to eq("19d3ea3e-ea8f-48f3-9f7a-00ae2810991f")
      end

      it "does not read another subscription's section" do
        other = described_class.new(subscription_id: CredentialsFileHelper::SUBSCRIPTIONS[:user_assigned_identity])
        expect(other.token_provider).to be_an_instance_of(Kitchen::Driver::Azure::ManagedIdentityToken)
      end

      it "warns only once about a missing tenant id, however often it is asked" do
        unknown = described_class.new(subscription_id: "00000000-0000-0000-0000-000000000000")
        allow(Kitchen.logger).to receive(:warn)

        3.times { unknown.send(:tenant_id!) }

        expect(Kitchen.logger).to have_received(:warn).with(/does not contain tenant_id/).once
      end

      it "warns when the subscription has no section at all" do
        unknown = described_class.new(subscription_id: "00000000-0000-0000-0000-000000000000")
        allow(Kitchen.logger).to receive(:warn)
        unknown.token_provider
        expect(Kitchen.logger).to have_received(:warn).with(/does not contain tenant_id/)
      end
    end

    context "when AZURE_CONFIG_FILE points somewhere else" do
      it "reads that file instead of the default" do
        use_default_location_credentials_file
        use_credentials_file(<<~INI)
          [#{subscription_id}]
          tenant_id = "overridden-tenant"
          client_id = "overridden-client"
          client_secret = "overridden-secret"
        INI

        expect(tenant_id_of(provider)).to eq("overridden-tenant")
        expect(client_id_of(provider)).to eq("overridden-client")
      end
    end

    context "when the credentials file is malformed" do
      it "surfaces the parse error rather than silently continuing" do
        use_credentials_file("this is not = valid [ini\n[[[")
        expect { provider }.to raise_error(IniFile::Error)
      end
    end

    describe "credential precedence" do
      before { use_fixture_credentials_file }

      it "prefers environment variables over the credentials file" do
        set_env("AZURE_TENANT_ID" => "env-tenant", "AZURE_CLIENT_ID" => "env-client", "AZURE_CLIENT_SECRET" => "env-secret")

        expect(provider).to be_an_instance_of(Kitchen::Driver::Azure::ServicePrincipalToken)
        expect(tenant_id_of(provider)).to eq("env-tenant")
        expect(client_id_of(provider)).to eq("env-client")
      end

      it "ignores environment variables that are exported but empty" do
        set_env("AZURE_CLIENT_SECRET" => "")

        expect(secret_of(provider)).to eq(":Qnt[7?:7RXzdMXrXE0ygBROA1hY1iV[")
      end

      it "mixes environment and file values" do
        set_env("AZURE_TENANT_ID" => "env-tenant")

        expect(tenant_id_of(provider)).to eq("env-tenant")
        expect(client_id_of(provider)).to eq("b5f3d6df-00bf-4451-a4f2-db3bc7731b58")
      end
    end

    describe "token provider selection" do
      before { use_fixture_credentials_file }

      context "with client_id, client_secret and tenant_id" do
        let(:subscription_id) { CredentialsFileHelper::SUBSCRIPTIONS[:service_principal] }

        it "uses a service principal token provider" do
          expect(provider).to be_an_instance_of(Kitchen::Driver::Azure::ServicePrincipalToken)
        end

        it "passes the client id and secret through" do
          expect(client_id_of(provider)).to eq("b5f3d6df-00bf-4451-a4f2-db3bc7731b58")
          expect(secret_of(provider)).to eq(":Qnt[7?:7RXzdMXrXE0ygBROA1hY1iV[")
        end
      end

      context "with client_id and tenant_id but no secret" do
        let(:subscription_id) { CredentialsFileHelper::SUBSCRIPTIONS[:user_assigned_identity] }

        it "uses a managed identity token provider" do
          expect(provider).to be_an_instance_of(Kitchen::Driver::Azure::ManagedIdentityToken)
        end

        it "binds the identity's client id" do
          expect(client_id_of(provider)).to eq("2801f9e6-c4c2-4667-a6e1-479f8827b0af")
        end
      end

      context "with only a tenant_id" do
        let(:subscription_id) { CredentialsFileHelper::SUBSCRIPTIONS[:system_assigned_identity] }

        it "uses a managed identity token provider" do
          expect(provider).to be_an_instance_of(Kitchen::Driver::Azure::ManagedIdentityToken)
        end

        it "binds no client id" do
          expect(client_id_of(provider)).to be_nil
        end
      end

      context "with an empty section" do
        let(:subscription_id) { CredentialsFileHelper::SUBSCRIPTIONS[:azure_cli] }

        it "falls back to the Azure CLI" do
          expect(provider).to be_an_instance_of(Kitchen::Driver::Azure::AzureCliToken)
        end
      end
    end

    describe "cloud endpoints" do
      # rubocop:disable Layout/ExtraSpacing
      {
        "Azure" => { resource_manager_url: "https://management.azure.com/",
                     authentication_endpoint: "https://login.microsoftonline.com/",
                     token_audience: "https://management.core.windows.net/" },
        "AzureUSGovernment" => { resource_manager_url: "https://management.usgovcloudapi.net",
                                 authentication_endpoint: "https://login.microsoftonline.us/",
                                 token_audience: "https://management.core.usgovcloudapi.net/" },
        "AzureChina" => { resource_manager_url: "https://management.chinacloudapi.cn",
                          authentication_endpoint: "https://login.chinacloudapi.cn/",
                          token_audience: "https://management.core.chinacloudapi.cn/" },
        "AzureGermanCloud" => { resource_manager_url: "https://management.microsoftazure.de",
                                authentication_endpoint: "https://login.microsoftonline.de/",
                                token_audience: "https://management.core.cloudapi.de/" },
      }.each do |cloud, expected|
        # rubocop:enable Layout/ExtraSpacing
        context "for #{cloud}" do
          let(:environment) { cloud }

          expected.each do |attribute, value|
            it "sets the #{attribute}" do
              expect(credentials.azure_environment.public_send(attribute)).to eq(value)
            end
          end
        end

        context "for #{cloud} spelled in a different case" do
          let(:environment) { cloud.downcase }

          it "resolves the same endpoints" do
            expect(credentials.azure_environment.resource_manager_url).to eq(expected[:resource_manager_url])
          end
        end
      end
    end

    it "builds an ARM client bound to the subscription" do
      expect(credentials.arm_client.subscription_id).to eq(subscription_id)
    end
  end

  # @param provider [Kitchen::Driver::Azure::TokenProvider]
  # @return [String, nil] the tenant it authenticates against.
  def tenant_id_of(provider)
    provider.instance_variable_get(:@tenant_id)
  end

  # @param provider [Kitchen::Driver::Azure::TokenProvider]
  # @return [String, nil]
  def client_id_of(provider)
    provider.instance_variable_get(:@client_id)
  end

  # @param provider [Kitchen::Driver::Azure::TokenProvider]
  # @return [String, nil]
  def secret_of(provider)
    provider.instance_variable_get(:@client_secret)
  end
end
