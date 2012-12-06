Gem::Specification.new do |s|
  s.name         = 'djc'
  s.version      = '1.0.0'
  s.homepage     = 'http://rubygems.org/gems/djc'
  s.summary      = 'JSON to CSV mapping DSL'
  s.description  = 'Map JSON fields into CSV columns easily'
  s.authors      = %w(Mason Glenna)
  s.email        = 'djc@chipped.net'
  s.files        = Dir["{lib}/**/*.rb", "bin/*", "LICENSE", "*.md"]
  s.require_path = 'lib'
  s.bindir       = 'bin'

  s.add_development_dependency 'rspec'
end
