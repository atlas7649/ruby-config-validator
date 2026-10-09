module ConfigValidator
  class Schema
    attr_reader :definitions

    def initialize(definitions = nil, parent = nil, &block)
      @definitions = definitions || {}
      @parent = parent
      instance_eval(&block) if block_given?
    end

    def field(name, type, required: true, default: nil, schema: nil, element_type: nil, element_optional: false, element_allowed_values: nil, element_type_message: nil, allowed_values: nil, min: nil, max: nil, precision: nil, pattern: nil, regex_match: nil, min_length: nil, max_length: nil, min_elements: nil, max_elements: nil, non_empty: false, description: nil, unique_elements: nil, required_if: nil, required_if_value: nil, required_message: nil, allow_nil: false, non_nil: false, type_message: nil, exclusive_with: nil, element_min: nil, element_max: nil, strict_types: false, element_default: nil, forbidden: false, min_message: nil, max_message: nil, min_length_message: nil, max_length_message: nil, min_elements_message: nil, max_elements_message: nil, constraint: nil, required_if_schema: nil, optional_if_schema: nil, depends_on: nil, depends_on_value: nil, type_cast: nil, min_between: nil, max_between: nil, &block)
      
      actual_schema = schema
      if block_given? && type == ConfigValidator::Schema
        actual_schema = ConfigValidator::Schema.new do
          instance_eval(&block)
        end
      end

      @definitions[name.to_s] = {
        type: type,
        required: required,
        default: default,
        schema: actual_schema,
        element_type: element_type,
        element_optional: element_optional,
        element_allowed_values: element_allowed_values,
        element_type_message: element_type_message,
        allowed_values: allowed_values,
        min: min,
        max: max,
        precision: precision,
        pattern: pattern,
        regex_match: regex_match,
        min_length: min_length,
        max_length: max_length,
        min_elements: min_elements,
        max_elements: max_elements,
        non_empty: non_empty,
        description: description,
        unique_elements: unique_elements,
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
        validate: (type == ConfigValidator::Schema && block_given?) ? nil : block
      }
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
  end
end