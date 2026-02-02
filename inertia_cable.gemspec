Gem::Specification.new do |spec|
  spec.name          = "inertia_cable"
  spec.version       = "0.1.0"
  spec.authors       = ["Cole Reynolds"]
  spec.summary       = "ActionCable broadcast DSL for Inertia Rails"
  spec.description   = "Lightweight ActionCable integration for Inertia.js Rails apps. Broadcasts refresh signals over WebSockets, triggering Inertia router.reload() on the client."
  spec.homepage      = "https://github.com/colereynolds/inertia_cable"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files         = Dir["lib/**/*", "app/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actioncable", ">= 7.0"
  spec.add_dependency "activejob", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "railties", ">= 7.0"
end
