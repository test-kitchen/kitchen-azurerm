RSpec.describe Kitchen::Driver::Azure::OperationError do
  subject(:error) do
    described_class.new("boom", status: 409, body: { "error" => { "code" => "DeploymentActive", "message" => "busy" } })
  end

  it "carries the message" do
    expect(error.message).to eq("boom")
  end

  it "carries the HTTP status" do
    expect(error.status).to eq(409)
  end

  it "exposes the Azure error code" do
    expect(error.code).to eq("DeploymentActive")
  end

  it "exposes the raw body" do
    expect(error.body.dig("error", "message")).to eq("busy")
  end

  it "has no code when Azure sent no error object" do
    expect(described_class.new("boom").code).to be_nil
  end

  it "defaults the body to an empty Hash" do
    expect(described_class.new("boom").body).to eq({})
  end

  it "has no code when the body is not a Hash" do
    expect(described_class.new("boom", body: "plain text").code).to be_nil
  end

  # These classes live inside `module Kitchen`, where Test Kitchen already
  # defines `Kitchen::StandardError`. A bare `StandardError` in this namespace
  # resolves to that instead of ::StandardError, which silently breaks both
  # `rescue StandardError` and any `rescue => e` expectations callers have.
  describe "constant resolution" do
    [described_class, Kitchen::Driver::Azure::TransientError].each do |klass|
      it "#{klass} descends from ::StandardError, not Kitchen::StandardError" do
        expect(klass.superclass).to eq(::StandardError)
      end

      it "#{klass} is caught by a bare rescue" do
        caught = begin
          raise klass, "boom"
                 rescue => e
                   e
        end

        expect(caught).to be_a(klass)
      end
    end
  end
end
