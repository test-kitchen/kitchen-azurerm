RSpec.describe "Kitchen::Driver::AZURERM_VERSION" do
  subject(:version) { Kitchen::Driver::AZURERM_VERSION }

  it "is a semantic version string" do
    expect(version).to match(/\A\d+\.\d+\.\d+(\.[\w.]+)?\z/)
  end

  it "is what the gemspec publishes" do
    gemspec = Gem::Specification.load(File.expand_path("../../../../kitchen-azurerm.gemspec", __dir__))
    expect(gemspec.version.to_s).to eq(version)
  end

  it "is frozen" do
    expect(version).to be_frozen
  end
end
