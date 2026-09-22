# Ruby Config Validator

A simple tool to validate YAML or JSON configuration files against a predefined schema.

## Usage

```ruby
require 'config_validator'

schema = ConfigValidator::Schema.new do
  field :api_key, String
  field :timeout, Integer
  field :retries, Integer, required: false
end

result = ConfigValidator.load_and_validate('config.yaml', schema)

if result[:valid]
  puts "Config is valid!"
else
  puts "Errors found: #{result[:errors]}"
end
```