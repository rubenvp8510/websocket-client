Gem::Specification.new do |gem|
  gem.name        = 'websocket-client'
  gem.version     = '0.0.1'
  gem.date        = '2017-06-21'
  gem.summary     = 'This is a websocket client based on faye-websocket'
  gem.description = 'This is a websocket client based on faye-websocket, it hidden all details about eventmachine'
  gem.authors     = ['Ruben Vargas']
  gem.email       = 'rvargasp@redhat.com'
  gem.files       = ['lib/websocket-client.rb']
  gem.license     = 'Apache-2.0'
  gem.homepage    = 'https://github.com/rubenvp8510/websocket-client'

  gem.add_runtime_dependency 'websocket-driver'
  gem.add_runtime_dependency 'event_emitter',  '~> 0.2'


  gem.add_development_dependency 'coveralls', '~> 0.8'
  gem.add_development_dependency 'rspec-rails', '~> 3.0'
  gem.add_development_dependency 'rake', '~> 11'
  gem.add_development_dependency 'rubocop', '= 0.34.2'
  gem.add_development_dependency 'shoulda', '~> 3.5'
  gem.add_development_dependency 'vcr', '~> 2.9'
  gem.add_development_dependency 'webmock', '~> 1.7'

end