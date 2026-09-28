require 'yaml'
require 'json'
require_relative 'config_validator/errors'
require_relative 'config_validator/schema'

module ConfigValidator
  BOOLEAN_TYPES = [TrueClass, FalseClass].freeze

  def self.valid?(config_data, schema, strict: false)
    validate(config_data, schema, strict: strict)[:valid]
  end

  def self.validate(config_data, schema, strict: false)
    errors = []
    validated_data = config_data ? config_data.dup : {}

    if strict && config_data.is_a?(Hash)
      unknown_keys = config_data.keys - schema.definitions.keys
      unknown_keys.each do |key|
        errors << ValidationError.new(key, 'Known Key', key)
      end
    end

    schema.definitions.each do |name, rules|
      exists = validated_data.key?(name)
      value = validated_data[name]

      if !exists
        is_required = rules[:required]
        
        if rules[:required_if]
          dep_field = rules[:required_if].to_s
          dep_value = rules[:required_if_value]
          current_dep_val = validated_data[dep_field]

          if dep_value.nil?
            is_required = true if current_dep_val && !BOOLEAN_TYPES.any? { |t| current_dep_val.is_a?(t) } || current_dep_val == true
          else
            is_required = true if current_dep_val == dep_value
          end
        end

        if is_required && rules[:default].nil?
          msg = rules[:required_message] || 'Required'
          errors << ValidationError.new(name, msg, 'nil')
          next
        elsif rules[:default].nil?
          next
        else
          validated_data[name] = rules[:default]
          value = rules[:default]
        end
      elsif value.nil? && !rules[:allow_nil]
        errors << ValidationError.new(name, 'Cannot be nil', value)
        next
      end

      next if value.nil? && rules[:allow_nil]

      type_error = nil
      type_msg = rules[:type_message]

      if rules[:type] == ConfigValidator::Schema
        if value.is_a?(Hash)
          nested_schema = rules[:schema] || ConfigValidator::Schema.new {}
          nested_result = validate(value, nested_schema, strict: strict)
          
          unless nested_result[:valid]
            errors.concat(nested_result[:errors].map do |e|
              e.is_a?(ValidationError) ? ValidationError.new("#{name}.#{e.path}", e.expected, e.actual) : ValidationError.new(name, 'Valid Nested Schema', e)
            end)
          end
          validated_data[name] = nested_result[:data]
        else
          type_error = ValidationError.new(name, type_msg || 'Hash (Nested Schema)', value)
        end
      elsif rules[:type] == Array
        if !value.is_a?(Array)
          type_error = ValidationError.new(name, type_msg || 'Array', value)
        elsif rules[:element_type]
          elem_type_msg = rules[:element_type_message]
          value.each_with_index do |item, idx|
            if item.nil?
              unless rules[:element_optional]
                errors << ValidationError.new("#{name}[#{idx}]", elem_type_msg || rules[:element_type], item)
              end
              next
            end

            item_type = rules[:element_type]
            if item_type == ConfigValidator::Schema
              nested_schema = rules[:schema] || ConfigValidator::Schema.new {}
              nested_result = validate(item, nested_schema, strict: strict)
              unless nested_result[:valid]
                errors.concat(nested_result[:errors].map do |e|
                  e.is_a?(ValidationError) ? ValidationError.new("#{name}[#{idx}].#{e.path}", e.expected, e.actual) : ValidationError.new("#{name}[#{idx}]", 'Valid Nested Schema', e)
                end)
              end
              value[idx] = nested_result[:data]
            elsif item_type.is_a?(Array)
              unless check_type(item, item_type)
                errors << ValidationError.new("#{name}[#{idx}]", elem_type_msg || "One of #{item_type.inspect}", item)
              end
            elsif item_type == :boolean
              unless BOOLEAN_TYPES.any? { |t| item.is_a?(t) }
                errors << ValidationError.new("#{name}[#{idx}]", elem_type_msg || 'Boolean', item)
              end
            elsif item_type.respond_to?(:call)
              unless item_type.call(item)
                errors << ValidationError.new("#{name}[#{idx}]", elem_type_msg || "Custom Type", item)
              end
            elsif !item.is_a?(item_type)
              errors << ValidationError.new("#{name}[#{idx}]", elem_type_msg || item_type, item)
            end

            if rules[:element_allowed_values] && !rules[:element_allowed_values].include?(item)
              errors << ValidationError.new("#{name}[#{idx}]", "One of #{rules[:element_allowed_values].inspect}", item)
            end

            if item.is_a?(Numeric)
              if rules[:element_min] && item < rules[:element_min]
                errors << ValidationError.new("#{name}[#{idx}]", "Minimum element value #{rules[:element_min]}", item)
              end
              if rules[:element_max] && item > rules[:element_max]
                errors << ValidationError.new("#{name}[#{idx}]", "Maximum element value #{rules[:element_max]}", item)
              end
            end
          end
        end
      elsif rules[:type].is_a?(Array)
        unless check_type(value, rules[:type])
          type_error = ValidationError.new(name, type_msg || "One of #{rules[:type].inspect}", value)
        end
      elsif rules[:type] == :boolean
        unless BOOLEAN_TYPES.any? { |t| value.is_a?(t) }
          type_error = ValidationError.new(name, type_msg || 'Boolean', value)
        end
      elsif rules[:type].respond_to?(:call)
        unless rules[:type].call(value)
          type_error = ValidationError.new(name, type_msg || "Custom Type", value)
        end
      elsif !value.is_a?(rules[:type])
        type_error = ValidationError.new(name, type_msg || rules[:type], value)
      end

      if type_error
        errors << type_error
      else
        if rules[:non_nil] && value.nil?
          errors << ValidationError.new(name, 'Cannot be nil', value)
        elsif rules[:allowed_values] && !rules[:allowed_values].include?(value)
          errors << ValidationError.new(name, "One of #{rules[:allowed_values].inspect}", value)
        end

        if rules[:exclusive_with] && !value.nil?
          exclusive_field = rules[:exclusive_with].to_s
          if !validated_data[exclusive_field].nil?
            errors << ValidationError.new(name, "Mutually exclusive with #{exclusive_field}", value)
          end
        end

        if (rules[:min] || rules[:max]) && value.is_a?(Numeric)
          if rules[:min] && value < rules[:min]
            errors << ValidationError.new(name, "Minimum #{rules[:min]}", value)
          end
          if rules[:max] && value > rules[:max]
            errors << ValidationError.new(name, "Maximum #{rules[:max]}", value)
          end
        end

        if rules[:precision] && value.is_a?(Float)
          decimal_part = value.to_s.split('.').last
          if decimal_part && decimal_part.length > rules[:precision]
            errors << ValidationError.new(name, "Maximum precision #{rules[:precision]}", decimal_part.length)
          end
        end

        if (rules[:min_length] || rules[:max_length])
          if value.is_a?(Array)
            if rules[:min_length] && value.length < rules[:min_length]
              errors << ValidationError.new(name, "Minimum length #{rules[:min_length]}", value.length)
            end
            if rules[:max_length] && value.length > rules[:max_length]
              errors << ValidationError.new(name, "Maximum length #{rules[:max_length]}", value.length)
            end
          elsif value.is_a?(String)
            if rules[:min_length] && value.length < rules[:min_length]
              errors << ValidationError.new(name, "Minimum length #{rules[:min_length]}", value.length)
            end
            if rules[:max_length] && value.length > rules[:max_length]
              errors << ValidationError.new(name, "Maximum length #{rules[:max_length]}", value.length)
            end
          end
        end

        if rules[:min_elements] && value.is_a?(Array)
          if value.length < rules[:min_elements]
            errors << ValidationError.new(name, "Minimum elements #{rules[:min_elements]}", value.length)
          end
        end

        if rules[:max_elements] && value.is_a?(Array)
          if value.length > rules[:max_elements]
            errors << ValidationError.new(name, "Maximum elements #{rules[:max_elements]}", value.length)
          end
        end

        if rules[:unique_elements] && value.is_a?(Array)
          unique_field = rules[:unique_elements]
          seen = {}
          value.each_with_index do |item, idx|
            next unless item.is_a?(Hash)
            val = item[unique_field.to_s]
            if seen.key?(val)
              errors << ValidationError.new("#{name}[#{idx}].#{unique_field}", "Unique value", val)
            else
              seen[val] = true
            end
          end
        end

        if rules[:pattern] && value.is_a?(String)
          unless value.match?(rules[:pattern])
            errors << ValidationError.new(name, "Pattern #{rules[:pattern].inspect}", value)
          end
        end

        if rules[:non_empty] && value.is_a?(String)
          if value.strip.empty?
            errors << ValidationError.new(name, 'Non-empty string', value)
          end
        end

        if rules[:validate]
          begin
            validation_result = rules[:validate].arity == 2 ? rules[:validate].call(value, validated_data) : rules[:validate].call(value)
            unless validation_result == true
              msg = validation_result.is_a?(String) ? validation_result : 'Custom Validation'
              errors << ValidationError.new(name, msg, value)
            end
          rescue StandardError => e
            errors << ValidationError.new(name, "Validation Exception: #{e.message}", value)
          end
        end
      end
    end

    { valid: errors.empty?, errors: errors, data: validated_data }
  end

  def self.check_type(value, types)
    types.any? do |type|
      if type == :boolean
        BOOLEAN_TYPES.any? { |t| value.is_a?(t) }
      elsif type.respond_to?(:call)
        type.call(value)
      else
        value.is_a?(type)
      end
    end
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