# Ruby Config Validator

A simple tool to validate YAML or JSON configuration files against a predefined schema with detailed error reporting.

## Usage

```ruby
require 'config_validator'

schema = ConfigValidator::Schema.new do
  field :api_key, String
  field :timeout, Integer
  optional :retries, Integer
  field :webhook_url, String, url: true
end

result = ConfigValidator.load_and_validate('config.yaml', schema)

if result[:valid]
  puts "Config is valid!"
else
  puts "Errors found: #{result[:errors]}"
end
```

## Features

- **Type Validation**: Supports basic Ruby types, `:boolean`, and custom type procs.
- **Constraint Helpers**: `range`, `unique_array`, `required_fields` for common patterns.
- **Conditional Logic**: `required_if`, `forbidden_if`, and complex conditional schemas (`required_if_schema`).
- **Advanced Checks**: Regular expressions, precision for floats, and custom validation blocks.
- **Cross-Field Validation**: Validate relationships between multiple fields using `cross_validate`.
- **Batch Validation**: `validate_all` helper for validating multiple files at once.