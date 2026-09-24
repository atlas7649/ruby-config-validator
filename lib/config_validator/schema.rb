module ConfigValidator
  class Schema
    attr_reader :definitions

    def initialize(&block)
      @definitions = {}
      instance_eval(&block) if block_given?
    end

    def field(name, type, required: true, default: nil, schema: nil, element_type: nil, element_optional: false, allowed_values: nil, min: nil, max: nil, pattern: nil, min_length: nil, max_length: nil, non_empty: false, &block)
      @definitions[name.to_s] = {
        type: type,
        required: required,
        default: default,
        schema: schema,
        element_type: element_type,
        element_optional: element_optional,
        allowed_values: allowed_values,
        min: min,
        max: max,
        pattern: pattern,
        min_length: min_length,
        max_length: max_length,
        non_empty: non_empty,
        validate: block
      }
    end
  end
end