# frozen_string_literal: true

require_relative "lib/itonoko/version"

Gem::Specification.new do |spec|
  spec.name        = "itonoko"
  spec.version     = Itonoko::VERSION
  spec.authors     = ["masak1yu"]
  spec.email       = ["antilogic@hey.com"]
  spec.summary        = "Pure Ruby nokogiri-compatible HTML/XML parser"
  spec.description    = "A pure Ruby implementation of nokogiri with no native extensions"
  spec.license        = "MIT"
  spec.homepage       = "https://github.com/masak1yu/itonoko"
  spec.metadata["source_code_uri"] = "https://github.com/masak1yu/itonoko"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.0"
end
