# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "buildrake/version"

Gem::Specification.new do |spec|
  spec.name          = "buildrake"
  spec.version       = Buildrake::VERSION
  spec.authors       = ["mskz-3110"]
  spec.email         = ["mskz.saito@gmail.com"]

  spec.summary       = %q{Multiplatform build for c.}
  spec.description   = %q{Multiplatform build for c.}
  spec.homepage      = "https://github.com/mskz-3110/buildrake/rubygems/buildrake"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", "~> 10.0"
end
