# coding: utf-8
lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'webhook_recorder/version'

Gem::Specification.new do |spec|
  spec.name          = 'webhook_recorder'
  spec.version       = WebhookRecorder::VERSION
  spec.authors       = ['Senthil V S']
  spec.email         = ['vss123@gmail.com']

  spec.summary       = 'Simple HTTP server helps to test behaviour that calls webhooks'
  spec.description   = 'It runs a HTTP server, exposes in internet via ngrok, and records the requests'
  spec.homepage      = 'https://github.com/siliconsenthil/webhook_recorder'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.3.8'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  # spec.bindir        = 'exe'
  # spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'activesupport', '~> 8.0'
  spec.add_runtime_dependency 'puma', '~> 6.5'
  spec.add_runtime_dependency 'ngrok-wrapper', '~> 0.3'
  spec.add_runtime_dependency 'rack', '~> 2.2.17'

  spec.add_development_dependency 'bundler', '~> 2.5'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'httpx', '~> 1.4'
end
