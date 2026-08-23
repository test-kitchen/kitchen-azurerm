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
        allow(Kitchen.logger).to receive(:debug)
        provider
        expect(Kitchen.logger).to have_received(:debug)
          .with(/#{Regexp.escape(described_class.default_config_path)} was not found/)
      end

      # Configuring no credentials at all is how someone signed in with
      # `az login` is meant to use the driver. Warning about it on every
      # create and destroy trained users to ignore the warnings that matter.
      it "does not warn, because this is a supported way to authenticate" do
        allow(Kitchen.logger).to receive(:warn)
        provider
        expect(Kitchen.logger).not_to have_received(:warn)
      end

      it "explains at debug level which credentials it settled on" do
        allow(Kitchen.logger).to receive(:debug)
        provider
        expect(Kitchen.logger).to have_received(:debug).with(/az login/)
      end

      # The file is not there at all, so it cannot be missing a tenant_id.
      it "does not claim a file that does not exist is missing a tenant_id" do
        allow(Kitchen.logger).to receive(:warn)
        provider
        expect(Kitchen.logger).not_to have_received(:warn).with(/does not contain tenant_id/)
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

      # Having a credentials file but no entry for the subscription under test
      # is worth saying out loud: the deployment is about to run as whoever is
      # signed in to the CLI, which may be a different identity entirely.
      it "warns when the subscription has no section at all" do
        unknown = described_class.new(subscription_id: "00000000-0000-0000-0000-000000000000")
        allow(Kitchen.logger).to receive(:warn)
        unknown.token_provider
        expect(Kitchen.logger).to have_received(:warn)
          .with(/no \[00000000-0000-0000-0000-000000000000\] section/)
      end

      it "names the file it read when the section is missing" do
        unknown = described_class.new(subscription_id: "00000000-0000-0000-0000-000000000000")
        allow(Kitchen.logger).to receive(:warn)
        unknown.token_provider
        expect(Kitchen.logger).to have_received(:warn)
          .with(/#{Regexp.escape(described_class.default_config_path)}/)
      end

      # An empty section is how a user says "for this subscription, use the
      # CLI" - deliberate, so it must not warn.
      it "stays quiet when the subscription has an empty section" do
        empty = described_class.new(subscription_id: CredentialsFileHelper::SUBSCRIPTIONS[:azure_cli])
        allow(Kitchen.logger).to receive(:warn)
        empty.token_provider
        expect(Kitchen.logger).not_to have_received(:warn)
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

    # A half-configured service principal is the case that genuinely deserves
    # a warning: without it the run silently authenticates as whoever is
    # signed in to the Azure CLI, which in CI is usually nobody at all.
    describe "incomplete credentials" do
      before { ENV.delete("AZURE_CONFIG_FILE") }

      it "warns when a client id and secret are set but the tenant is not" do
        set_env("AZURE_CLIENT_ID" => "c", "AZURE_CLIENT_SECRET" => "s")
        allow(Kitchen.logger).to receive(:warn)

        credentials.token_provider

        expect(Kitchen.logger).to have_received(:warn).with(/Incomplete Azure credentials.*tenant_id/)
      end

      it "still falls back to the Azure CLI so the run can continue" do
        set_env("AZURE_CLIENT_ID" => "c", "AZURE_CLIENT_SECRET" => "s")
        expect(credentials.token_provider).to be_an_instance_of(Kitchen::Driver::Azure::AzureCliToken)
      end

      it "warns when a federated token file is set without a client id" do
        set_env("AZURE_FEDERATED_TOKEN_FILE" => File.join(ENV.fetch("HOME"), "token").tap { |f| File.write(f, "a") })
        allow(Kitchen.logger).to receive(:warn)

        credentials.token_provider

        expect(Kitchen.logger).to have_received(:warn).with(/Incomplete Azure credentials.*client_id/)
      end

      it "lists every missing value rather than only the first" do
        set_env("AZURE_CLIENT_SECRET" => "s")
        allow(Kitchen.logger).to receive(:warn)

        credentials.token_provider

        expect(Kitchen.logger).to have_received(:warn).with(/tenant_id.*client_id|client_id.*tenant_id/)
      end
    end

    describe "token provider selection" do
      before { use_fixture_credentials_file }

      # Each row is the combination a user actually configures, and the
      # provider it must resolve to. Getting this table wrong is how an
      # instance silently authenticates as the wrong thing - or, worse, falls
      # through to a credential that is not present in CI at all.
      describe "the full matrix" do
        let(:token_file) { File.join(ENV.fetch("HOME"), "federated-token").tap { |f| File.write(f, "assertion") } }

        before { ENV.delete("AZURE_CONFIG_FILE") }

        {
          "nothing configured" => [{}, Kitchen::Driver::Azure::AzureCliToken],
          "a tenant alone" => [{ "AZURE_TENANT_ID" => "t" }, Kitchen::Driver::Azure::ManagedIdentityToken],
          "a client id alone" => [{ "AZURE_CLIENT_ID" => "c" }, Kitchen::Driver::Azure::ManagedIdentityToken],
          "a client id and tenant" => [{ "AZURE_CLIENT_ID" => "c", "AZURE_TENANT_ID" => "t" }, Kitchen::Driver::Azure::ManagedIdentityToken],
          "an explicit AZURE_USE_MSI" => [{ "AZURE_USE_MSI" => "1" }, Kitchen::Driver::Azure::ManagedIdentityToken],
          "a full service principal" => [{ "AZURE_CLIENT_ID" => "c", "AZURE_CLIENT_SECRET" => "s", "AZURE_TENANT_ID" => "t" }, Kitchen::Driver::Azure::ServicePrincipalToken],
        }.each do |label, (env, expected)|
          it "resolves #{label} to #{expected.to_s.split("::").last}" do
            set_env(env)
            expect(described_class.new(subscription_id: "s").token_provider).to be_an_instance_of(expected)
          end
        end

        it "resolves a federated token file to WorkloadIdentityToken" do
          set_env("AZURE_FEDERATED_TOKEN_FILE" => token_file, "AZURE_CLIENT_ID" => "c", "AZURE_TENANT_ID" => "t")
          expect(described_class.new(subscription_id: "s").token_provider)
            .to be_an_instance_of(Kitchen::Driver::Azure::WorkloadIdentityToken)
        end

        it "prefers federation over a service principal secret" do
          set_env("AZURE_FEDERATED_TOKEN_FILE" => token_file, "AZURE_CLIENT_ID" => "c",
            "AZURE_CLIENT_SECRET" => "s", "AZURE_TENANT_ID" => "t")
          expect(described_class.new(subscription_id: "s").token_provider)
            .to be_an_instance_of(Kitchen::Driver::Azure::WorkloadIdentityToken)
        end

        it "ignores an empty AZURE_FEDERATED_TOKEN_FILE" do
          set_env("AZURE_FEDERATED_TOKEN_FILE" => "", "AZURE_CLIENT_ID" => "c",
            "AZURE_CLIENT_SECRET" => "s", "AZURE_TENANT_ID" => "t")
          expect(described_class.new(subscription_id: "s").token_provider)
            .to be_an_instance_of(Kitchen::Driver::Azure::ServicePrincipalToken)
        end

        # The instance metadata service never sees a tenant, so requiring one
        # only stopped the identity from being usable.
        it "needs no tenant for a user-assigned managed identity" do
          set_env("AZURE_CLIENT_ID" => "c")
          provider = described_class.new(subscription_id: "s").token_provider
          expect(client_id_of(provider)).to eq("c")
        end
      end

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

    describe "AZURE_AUTHORITY_HOST" do
      it "redirects token exchange at the authority the platform names" do
        set_env("AZURE_AUTHORITY_HOST" => "https://login.example.invalid/")
        expect(credentials.azure_environment.authentication_endpoint).to eq("https://login.example.invalid/")
      end

      it "leaves the resource manager endpoint alone" do
        set_env("AZURE_AUTHORITY_HOST" => "https://login.example.invalid/")
        expect(credentials.azure_environment.resource_manager_url).to eq("https://management.azure.com/")
      end

      it "is ignored when empty" do
        set_env("AZURE_AUTHORITY_HOST" => "")
        expect(credentials.azure_environment.authentication_endpoint).to eq("https://login.microsoftonline.com/")
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
