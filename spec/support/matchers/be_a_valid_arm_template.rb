require "json"

# Asserts that a String parses as JSON and looks like an ARM deployment template.
#
# Every ERB template in this gem is string-interpolated, so a conditional that
# emits a stray comma produces a file that is structurally plausible but
# unparseable. This matcher makes that failure mode explicit and gives a useful
# message, rather than a JSON::ParserError from somewhere deep in the driver.
RSpec::Matchers.define :be_a_valid_arm_template do
  match do |actual|
    @parsed = JSON.parse(actual)
    @failure = "is not a JSON object" unless @parsed.is_a?(Hash)
    @failure ||= "has no $schema" unless @parsed.key?("$schema")
    @failure ||= "has no resources array" unless @parsed["resources"].is_a?(Array)
    @failure.nil?
  rescue JSON::ParserError => e
    @failure = "is not parseable JSON: #{e.message}"
    false
  end

  failure_message do |actual|
    "expected an ARM template, but it #{@failure}\n\n#{actual.to_s[0, 2000]}"
  end

  failure_message_when_negated do
    "expected the value not to be a valid ARM template, but it was"
  end
end
