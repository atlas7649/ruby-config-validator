module ConfigValidator
  class Schema
    attr_reader :definitions, :cross_validators

    def initialize(definitions = nil, parent = nil, &block)
      @definitions = definitions || {}
      @cross_validators = []
      @parent = parent
      instance_eval(&block) if block_given?
    end

    def cross_validate(&block)
      @cross_validators << block
    end

    def rule(name = nil, &block)
      # Custom rule that can be registered and called during cross-validation
      # If a name is provided, it helps in error reporting
      validator = block
      @cross_validators << lambda do |data|
        result = validator.call(data)
        unless result == true
          msg = result.is_a?(String) ? result : "Rule '#{name || 'custom'}' validation failed"
          # We return a special structure that the main validator can use to assign a path
          { path: name ? "schema.#{name}" : 'schema', message: msg }
        end
        result == true
      end
    end

    def group(name, options = {}, &block)
      # Groups allow applying the same options to multiple fields
      # We create a temporary schema to capture the fields defined in the block
      group_schema = ConfigValidator::Schema.new do
        instance_eval(&block)
      end
      
      group_schema.definitions.each do |field_name, rules|
        # Merge group options into field rules
        merged_rules = options.merge(rules)
        
        # By default, we prefix the field name with the group name to avoid collisions
        # and maintain the logical hierarchy of the group
        full_name = "#{name}.#{field_name}"
        apply_field_definition(full_name, merged_rules)
      end
    end

    def required_fields(*names, type: String)
      names.each do |name|
        field(name, type, required: true)
      end
    end

    def required_one_of(*names, message: nil)
      required_at_least(1, *names, message: message)
    end

    def required_at_least(count, *names, message: nil)
      @cross_validators << lambda do |data|
        present_count = names.count { |name| data.key?(name.to_s) }
        if present_count < count
          msg = message || "At least #{count} of #{names.join(', ')} must be provided"
          { path: 'schema', message: msg }
        else
          true
        end
      end
    end

    def required_none_of(*names, message: nil)
      @cross_validators << lambda do |data|
        if names.any? { |name| data.key?(name.to_s) }
          msg = message || "None of #{names.join(', ')} should be provided together"
          { path: 'schema', message: msg }
        else
          true
        end
      end
    end

    def range(name, min: nil, max: nil, required: true, type: Integer, **extra)
      field(name, type, required: required, min: min, max: max, **extra)
    end

    def unique_array(name, type: String, required: true, **extra)
      field(name, Array, required: required, element_type: type, unique_values: true, **extra)
    end

    def optional(name, type, **extra)
      field(name, type, required: false, **extra)
    end

    def required_if_schema(field, value: nil, &block)
      # Creates a schema that is validated if 'field' equals 'value'
      schema = ConfigValidator::Schema.new do
        instance_eval(&block)
      end
      # We use a dummy field name for the definition since the actual validation happens on the whole config
      # The main validator looks for these special keys in all definitions
      field("__cond_schema_#{field}", ConfigValidator::Schema, required: false, 
             required_if_schema: schema, 
             required_if: field, 
             required_if_value: value)
    end

    def field(name, type, required: true, default: nil, schema: nil, element_type: nil, element_optional: false, element_allowed_values: nil, element_type_message: nil, allowed_values: nil, enum: nil, min: nil, max: nil, precision: nil, pattern: nil, regex_match: nil, min_length: nil, max_length: nil, min_elements: nil, max_elements: nil, exact_elements: nil, non_empty: false, description: nil, unique_elements: nil, unique_values: false, required_if: nil, required_if_value: nil, required_message: nil, allow_nil: false, non_nil: false, type_message: nil, exclusive_with: nil, element_min: nil, element_max: nil, strict_types: false, element_default: nil, forbidden: false, min_message: nil, max_message: nil, min_length_message: nil, max_length_message: nil, min_elements_message: nil, max_elements_message: nil, constraint: nil, required_if_schema: nil, optional_if_schema: nil, depends_on: nil, depends_on_value: nil, type_cast: nil, min_between: nil, max_between: nil, email: false, ip_address: false, whitelist: nil, forbidden_if: nil, forbidden_if_value: nil, forbidden_range: nil, required_any: nil, required_if_any: nil, required_if_any_value: nil, forbidden_if_any: nil, forbidden_if_any_value: nil, required_all: nil, required_if_all: nil, required_if_all_value: nil, type_if: nil, type_if_value: nil, type_if_type: nil, precision_message: nil, excluded_from: nil, excluded_from_message: nil, **extra_options)
      
      actual_schema = schema
      if block_given? && type == ConfigValidator::Schema
        actual_schema = ConfigValidator::Schema.new do
          instance_eval(&block)
        end
      end

      # Apply built-in patterns
      pattern_override = nil
      if extra_options[:email]
        pattern_override = /\A[\w+\-.]+@[\a-zA-Z0-9\-.]+\.[a-zA-Z]{2,}\z/
      elsif extra_options[:ip_address]
        pattern_override = /\A(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/
      elsif extra_options[:uuid]
        pattern_override = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
      elsif extra_options[:url]
        pattern_override = /\A(http|https):\/\/[^\s\/$.?#].[^\s]*\z/i
      end

      rules = {
        type: type,
        required: required,
        default: default,
        schema: actual_schema,
        element_type: element_type,
        element_optional: element_optional,
        element_allowed_values: element_allowed_values,
        element_type_message: element_type_message,
        allowed_values: allowed_values,
        enum: enum,
        min: min,
        max: max,
        precision: precision,
        pattern: pattern_override || pattern,
        regex_match: regex_match,
        min_length: min_length,
        max_length: max_length,
        min_elements: min_elements,
        max_elements: max_elements,
        exact_elements: exact_elements,
        non_empty: non_empty,
        description: description,
        unique_elements: unique_elements,
        unique_values: unique_values,
        required_if: required_if,
        required_if_value: required_if_value,
        required_message: required_message,
        allow_nil: allow_nil,
        non_nil: non_nil,
        type_message: type_message,
        exclusive_with: exclusive_with,
        element_min: element_min,
        element_max: element_max,
        strict_types: strict_types,
        element_default: element_default,
        forbidden: forbidden,
        min_message: min_message,
        max_message: max_message,
        min_length_message: min_length_message,
        max_length_message: max_length_message,
        min_elements_message: min_elements_message,
        max_elements_message: max_elements_message,
        constraint: constraint,
        required_if_schema: required_if_schema,
        optional_if_schema: optional_if_schema,
        depends_on: depends_on,
        depends_on_value: depends_on_value,
        type_cast: type_cast,
        min_between: min_between,
        max_between: max_between,
        whitelist: whitelist,
        forbidden_if: forbidden_if,
        forbidden_if_value: forbidden_if_value,
        forbidden_range: forbidden_range,
        required_any: required_any,
        required_if_any: required_if_any,
        required_if_any_value: required_if_any_value,
        forbidden_if_any: forbidden_if_any,
        forbidden_if_any_value: forbidden_if_any_value,
        required_all: required_all,
        required_if_all: required_if_all,
        required_if_all_value: required_if_all_value,
        type_if: type_if,
        type_if_value: type_if_value,
        type_if_type: type_if_type,
        precision_message: precision_message,
        excluded_from: excluded_from,
        excluded_from_message: excluded_from_message,
        validate: (type == ConfigValidator::Schema && block_given?) ? nil : block
      }.merge(extra_options)

      apply_field_definition(name.to_s, rules)
    end

    def fields
      all_definitions.keys
    end

    def defined?(name)
      all_definitions.key?(name.to_s)
    end

    def all_definitions
      return @definitions if @parent.nil?
      @parent.all_definitions.merge(@definitions)
    end

    def to_h
      all_definitions.each_with_object({}) do |(name, rules), hash|
        processed_rules = rules.dup
        if processed_rules[:schema].is_a?(ConfigValidator::Schema)
          processed_rules[:schema] = processed_rules[:schema].to_h
        end
        if processed_rules[:required_if_schema].is_a?(ConfigValidator::Schema)
          processed_rules[:required_if_schema] = processed_rules[:required_if_schema].to_h
        end
        if processed_rules[:optional_if_schema].is_a?(ConfigValidator::Schema)
          processed_rules[:optional_if_schema] = processed_rules[:optional_if_schema].to_h
        end
        hash[name] = processed_rules
      end
    end

    private

    def apply_field_definition(name, rules)
      @definitions[name] = rules
    end
  end
end