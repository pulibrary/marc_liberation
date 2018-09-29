source 'https://rubygems.org'

gem 'bootstrap-sass', '~> 3.3.3'
gem 'ffi', '>= 1.9.25'
gem 'high_voltage', '~> 3.0'
gem 'jbuilder', '~> 2.0'
gem 'jquery-rails'
gem 'loops', github: 'kovyrin/loops', branch: 'master'
gem 'mysql2'
gem 'rails', '~> 5.1'
gem 'ruby-oci8', '~> 2.2.1' unless ENV['CI']
gem 'sass-rails', '~> 5.0'
gem 'sdoc', '~> 0.4.0', group: :doc
gem 'stomp'
gem 'turbolinks'
gem 'uglifier', '>= 1.3.0'

gem 'friendly_id', '~> 5.1.0'
gem 'gyoku', '~> 1.0'
gem 'lightly'
gem 'locations', github: "pulibrary/locations", tag: 'v1.2.0'
gem 'marc', '~> 1.0'
gem 'marc_cleanup', github: "pulibrary/marc_cleanup", tag: 'v0.7.0'
gem 'multi_json', '~> 1.10.1'
gem 'oj'
gem 'rack-conneg', '~> 0.1.5'
gem 'responders', '~> 2.3'
gem 'rubyzip', '>= 1.2.2'
gem 'voyager_helpers', github: "pulibrary/voyager_helpers", tag: 'v0.6.6'
gem 'yaml_db', '~> 0.6.0'

gem 'capybara'
gem 'devise', '~> 4.3'
gem 'omniauth-cas'
gem 'poltergeist'
gem 'sidekiq'

gem 'faraday', '~> 0.13'
gem 'faraday_middleware', '~> 0.12'
gem 'honeybadger', '~> 3.1'
gem 'iso-639'
gem 'library_stdnums'
gem 'loofah', '~> 2.2.1'
gem 'net-sftp', '~> 2.1', '>= 2.1.2'
gem 'orangetheses', github: 'pulibrary/orangetheses', tag: 'v0.3.0'
gem 'rsolr'
gem 'stringex', github: "pulibrary/stringex", tag: 'vpton.2.5.2.2'
gem 'traject', '2.3.1'

gem 'bixby', '~> 1.0'
gem 'rspec-rails', '~> 3.5'
gem 'rubocop', '~> 0.52.1'
gem 'rubocop-rspec', '~> 1.22'

group :development do
  gem 'capistrano-rails', '~> 1.1.1'
  gem 'spring'
end

group :development, :test do
  # bundler and rake come in from the voyager_helpers gemspec
  gem 'coveralls', '0.8.21'
  gem "factory_bot_rails", "~> 4.0"
  gem 'pry-byebug', '~> 3.0'
  gem 'rails-controller-testing'
  gem 'rerun', '~> 0.10.0'
  gem 'simplecov', '0.14.1'
  gem 'webmock'
end
