source "https://rubygems.org"

gemspec development_group: :test

group :test do
  gem "rake", ">= 11.0"
  gem "rspec", "~> 3.13"
  gem "simplecov", "~> 0.22"
  gem "webmock", "~> 3.19"
end

group :development do
  gem "yard", "~> 0.9"
end

group :debug do
  gem "pry"
end

group :cookstyle do
  gem "cookstyle", "~> 8.4"
end

# Only needed to run the suites in integration/, which deploy real virtual
# machines. `bundle install --without integration` skips them.
group :integration do
  # Ubuntu 22.04's sshd will not negotiate ciphers with net-ssh 4, which older
  # resolutions of this tree can otherwise pick up.
  gem "net-ssh", "~> 7.3"
  gem "winrm", "~> 2.3"
  gem "winrm-elevated", "~> 1.2"
  gem "winrm-fs", "~> 1.3"
end
