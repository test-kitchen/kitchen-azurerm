require "spec_helper"
require "kitchen/transport/dummy"

describe Kitchen::Driver::Azurerm do
  let(:logged_output) { StringIO.new }
  let(:logger)        { Logger.new(logged_output) }
  let(:platform)      { Kitchen::Platform.new(name: "fake_platform") }
  let(:transport)     { Kitchen::Transport::Dummy.new }
  let(:driver)        { described_class.new(config) }

  let(:subscription_id) { "115b12cb-b0d3-4ed9-94db-f73733be6f3c" }
  let(:location) { "eastus2" }
  let(:machine_size) { "Standard_D4_v3" }
  let(:vm_tags) do
    {
      os_type: "linux",
      distro: "redhat",
    }
  end

  let(:image_urn) { "RedHat:rhel-byos:rhel-raw76:7.6.20190620" }
  let(:vm_name) { "my-awesome-vm" }

  let(:config) do
    {
      subscription_id: subscription_id,
      location: location,
      machine_size: machine_size,
      vm_tags: vm_tags,
      image_urn: image_urn,
      vm_name: vm_name,
    }
  end

  let(:instance) do
    instance_double(Kitchen::Instance,
      logger:    logger,
      transport: transport,
      platform:  platform,
      to_str:    "instance_str")
  end

  before do
    allow(driver).to receive(:instance).and_return(instance)
  end

  it "driver API version is 2" do
    expect(driver.diagnose_plugin[:api_version]).to eq(2)
  end

  describe "#name" do
    it "has an overridden name" do
      expect(driver.name).to eq("Azurerm")
    end
  end

  describe "#create" do
  end

  describe "#virtual_machine_deployment_template" do
    subject { driver.send(:virtual_machine_deployment_template) }

    let(:parsed_json) { JSON.parse(subject) }
    let(:vm_resource) { parsed_json["resources"].find { |x| x["type"] == "Microsoft.Compute/virtualMachines" } }

    context "when plan config is provided" do
      let(:plan_name) { "plan-abc" }
      let(:plan_product) { "my-product" }
      let(:plan_publisher) { "captain-america" }
      let(:plan_promotion_code) { "50-percent-off" }

      let(:plan) do
        {
          name: plan_name,
          product: plan_product,
          publisher: plan_publisher,
          promotion_code: plan_promotion_code,
        }
      end

      let(:config) do
        {
          subscription_id: subscription_id,
          location: location,
          machine_size: machine_size,
          vm_tags: vm_tags,
          plan: plan,
          image_urn: image_urn,
          vm_name: vm_name,
        }
      end

      it "includes plan information in deployment template" do
        expect(vm_resource).to have_key("plan")
        expect(vm_resource["plan"]["name"]).to eq(plan_name)
        expect(vm_resource["plan"]["product"]).to eq(plan_product)
        expect(vm_resource["plan"]["publisher"]).to eq(plan_publisher)
        expect(vm_resource["plan"]["promotionCode"]).to eq(plan_promotion_code)
      end
    end

    context "when plan config is not provided" do
      let(:config) do
        {
          subscription_id: subscription_id,
          location: location,
          machine_size: machine_size,
          vm_tags: vm_tags,
          image_urn: image_urn,
          vm_name: vm_name,
        }
      end

      it "does not include plan information in deployment template" do
        expect(vm_resource).not_to have_key("plan")
      end
    end
  end
end
