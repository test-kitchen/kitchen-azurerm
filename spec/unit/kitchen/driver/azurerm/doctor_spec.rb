RSpec.describe Kitchen::Driver::Azurerm, "#doctor" do
  subject(:driver) { build_driver(**config) }

  let(:config) { {} }
  let(:arm_client) { arm_client_double }
  let(:state) { {} }
  let(:reported) { [] }

  before do
    stub_arm_client(driver, arm_client:)
    allow(Kitchen.logger).to receive(:error) { |message| reported << message }
  end

  describe "a healthy configuration" do
    it "finds no problems" do
      expect(driver.doctor(state)).to be false
    end

    it "reports nothing" do
      driver.doctor(state)
      expect(reported).to be_empty
    end

    # A HEAD on a resource group answers 404 for a subscription that does not
    # exist and for one that merely has no such group, so it cannot tell a
    # wrong subscription from a healthy one. Reading the subscription can.
    it "proves the credentials reach the subscription by reading it" do
      driver.doctor(state)
      expect(arm_client).to have_received(:subscription)
    end
  end

  describe "when required settings are missing" do
    let(:config) { { subscription_id: nil, location: nil, machine_size: nil } }

    it "finds problems" do
      expect(driver.doctor(state)).to be true
    end

    it "names every missing setting" do
      driver.doctor(state)
      expect(reported.join("\n")).to include("subscription_id").and include("location").and include("machine_size")
    end

    it "does not bother Azure when there is no subscription to ask about" do
      driver.doctor(state)
      expect(arm_client).not_to have_received(:subscription)
    end
  end

  describe "when a required setting is blank rather than absent" do
    let(:config) { { location: "" } }

    it "counts as missing" do
      expect(driver.doctor(state)).to be true
      expect(reported.join("\n")).to include("location")
    end
  end

  describe "when Azure rejects the credentials" do
    before do
      allow(arm_client).to receive(:subscription)
        .and_raise(azure_operation_error(code: "AuthorizationFailed", message: "does not have authorization", status: 403))
    end

    it "finds a problem" do
      expect(driver.doctor(state)).to be true
    end

    it "passes Azure's own reason along" do
      driver.doctor(state)
      expect(reported.join("\n")).to include("AuthorizationFailed").and include("does not have authorization")
    end
  end

  describe "when the subscription does not exist" do
    before do
      allow(arm_client).to receive(:subscription)
        .and_raise(azure_operation_error(code: "SubscriptionNotFound",
          message: "The subscription '00000000-0000-0000-0000-000000000000' could not be found.", status: 404))
    end

    it "finds a problem and names the subscription" do
      expect(driver.doctor(state)).to be true
      expect(reported.join("\n")).to include("SubscriptionNotFound").and include("could not be found")
    end
  end

  describe "when Azure cannot be reached" do
    before do
      allow(arm_client).to receive(:subscription)
        .and_raise(Kitchen::Driver::Azure::TransientError, "Net::OpenTimeout: timed out")
    end

    it "finds a problem and says why" do
      expect(driver.doctor(state)).to be true
      expect(reported.join("\n")).to include("timed out")
    end
  end

  describe "when credentials cannot be resolved at all" do
    before do
      allow(Kitchen::Driver::AzureCredentials).to receive(:new)
        .and_raise(Kitchen::Driver::Azure::OperationError.new("The Azure CLI (`az`) was not found on PATH"))
    end

    it "finds a problem and says why" do
      expect(driver.doctor(state)).to be true
      expect(reported.join("\n")).to include("was not found on PATH")
    end

    # Nothing reached Azure, so saying Azure rejected it sends the reader
    # looking in the wrong place.
    it "does not blame Azure for a request that was never made" do
      driver.doctor(state)
      expect(reported.join("\n")).not_to include("Azure rejected")
    end
  end
end
