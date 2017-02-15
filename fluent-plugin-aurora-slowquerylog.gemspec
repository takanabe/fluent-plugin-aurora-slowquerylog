# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-aurora-slowquerylog"
  spec.version       = "0.0.4"
  spec.authors       = ["Takayuki WATANABE"]
  spec.email         = ["takanabe.w@gmail.com"]

  spec.summary       = "A fluentd plugin that collects AWS Aurora slow query logs with `log_output=FILE`"
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/takanabe/fluent-plugin-aurora-slowquerylog"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "fluentd"
  spec.add_runtime_dependency "aws-sdk", '~> 2'
  spec.add_runtime_dependency "myslog"
  spec.add_runtime_dependency "activesupport"

  spec.add_development_dependency "test-unit", ">= 3.0.0"
  spec.add_development_dependency "pry-byebug"
end
