require 'yaml'
require 'json'
require_relative 'config_validator/errors'
require_relative 'config_validator/schema'

module ConfigValidator
  def self.validate(config_data, schema)
    errors = []
    validated_data = config_data ? config_data.dup : {}

    schema.definitions.each do |name, rules|
      value = validated_data[name]

      if value.nil?
        if rules[:default].nil? && rules[:required]
          errors << "Missing required field: #{name}"
          next
        elsif rules[:default].nil?
          next
        else
          validated_data[name] = rules[:default]
          value = rules[:default]
        end
      end

      if rules[:type] == ConfigValidator::Schema
        if value.is_a?(Hash)
          # Recursively validate nested schema
          # We need to find the specific schema instance associated with this field
          # Since the 'type' is just the class, we check if there's a specific schema provided
          nested_schema = rules[:schema] || ConfigValidator::Schema.new {}
          nested_result = validate(value, nested_schema)
          
          unless nested_result[:valid]
            errors.concat(nested_result[:errors].map { |e| "#{name}.#{e}" })
          end
          validated_data[name] = nested_result[:data]
        else
          errors << ValidationError.new(name, 'Hash (Nested Schema)', value)
        end
      elsif !value.is_a?(rules[:type])
        errors << ValidationError.new(name, rules[:type], value)
      end
    end

    { valid: errors.empty?, errors: errors, data: validated_data }
  end

  def self.load_and_validate(file_path, schema)
    ext = File.extname(file_path).downcase
    data = case ext
           when '.yaml', '.yml' then YAML.load_file(file_path)
           when '.json' then JSON.parse(File.read(file_path))
           else raise "Unsupported file format: #{ext}"
           end
    validate(data, schema)
  end
end