require 'yaml'
require 'json'
require_relative 'config_validator/errors'
require_relative 'config_validator/schema'

module ConfigValidator
  BOOLEAN_TYPES = [TrueClass, FalseClass].freeze

  def self.validate(config_data, schema, strict: false)
    errors = []
    validated_data = config_data ? config_data.dup : {}

    if strict && config_data.is_a?(Hash)
      unknown_keys = config_data.keys - schema.definitions.keys
      unknown_keys.each do |key|
        errors << "Unexpected configuration key: #{key}"
      end
    end

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
          nested_schema = rules[:schema] || ConfigValidator::Schema.new {}
          nested_result = validate(value, nested_schema, strict: strict)
          
          unless nested_result[:valid]
            errors.concat(nested_result[:errors].map { |e| "#{name}.#{e}" })
          end
          validated_data[name] = nested_result[:data]
        elsif value.nil?
          # This case is handled by the value.nil? check above, for clarity:
          next
        else
          errors << ValidationError.new(name, 'Hash (Nested Schema)', value)
        end
      elsif rules[:type] == Array
        if !value.is_a?(Array)
          errors << ValidationError.new(name, 'Array', value)
        elsif rules[:element_type]
          value.each_with_index do |item, idx|
            if rules[:element_type] == ConfigValidator::Schema
              nested_schema = rules[:schema] || ConfigValidator::Schema.new {}
              nested_result = validate(item, nested_schema, strict: strict)
              unless nested_result[:valid]
                errors.concat(nested_result[:errors].map { |e| "#{name}[#{idx}].#{e}" })
              end
              value[idx] = nested_result[:data]
            elsif rules[:element_type] == :boolean
              unless BOOLEAN_TYPES.any? { |t| item.is_a?(t) }
                errors << ValidationError.new("#{name}[#{idx}]", 'Boolean', item)
              end
            elsif !item.is_a?(rules[:element_type])
              errors << ValidationError.new("#{name}[#{idx}]", rules[:element_type], item)
            end
          end
        end
      elsif rules[:type] == :boolean
        unless BOOLEAN_TYPES.any? { |t| value.is_a?(t) }
          errors << ValidationError.new(name, 'Boolean', value)
        end
      elsif !value.is_a?(rules[:type])
        errors << ValidationError.new(name, rules[:type], value)
      end

      if rules[:validate] && !errors.any? { |e| e.is_a?(ValidationError) && e.path == name }
        unless rules[:validate].call(value)
          errors << "Validation failed for field: #{name}"
        end
      end
    end

    { valid: errors.empty?, errors: errors, data: validated_data }
  end

  def self.load_and_validate(file_path, schema, strict: false)
    ext = File.extname(file_path).downcase
    data = case ext
           when '.yaml', '.yml' then YAML.load_file(file_path)
           when '.json' then JSON.parse(File.read(file_path))
           else raise "Unsupported file format: #{ext}"
           end
    validate(data, schema, strict: strict)
  end
end