# Helpers for manipulating the process environment inside an example.
#
# The suite-wide +around+ hook in +spec_helper.rb+ snapshots and restores +ENV+
# for every example, so these helpers can mutate it directly rather than
# stubbing +ENV#[]+. Stubbing the accessor forces every incidental variable read
# by any gem in the stack to be enumerated as well, which is how the previous
# suite ended up asserting on +GEM_SKIP+.
module EnvHelper
  # Sets environment variables for the remainder of the example.
  #
  # @param vars [Hash{String,Symbol => String,nil}] a nil value deletes the key.
  # @return [void]
  def set_env(vars)
    vars.each do |key, value|
      if value.nil?
        ENV.delete(key.to_s)
      else
        ENV[key.to_s] = value.to_s
      end
    end
  end

  # Sets environment variables for the duration of the block only.
  #
  # @param vars [Hash{String,Symbol => String,nil}]
  # @yield with the variables applied.
  # @return [Object] the block's return value.
  def with_env(vars)
    original = vars.keys.to_h { |key| [key.to_s, ENV[key.to_s]] }
    set_env(vars)
    yield
  ensure
    set_env(original)
  end
end
