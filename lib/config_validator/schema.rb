module ConfigValidator
  class Schema
    attr_reader :definitions

    def initialize(&block)
      @definitions = {}
      instance_eval(&block) if block_given?
    end

    def field(name, type, required: true, default: nil, schema: nil, element_type: nil, element_optional: false, allowed_values: nil, &block)
      @definitions[name.to_s] = {
        type: type,
        required: required,
        default: default,
        schema: schema,
        element_type: element_type,
        element_optional: element_optional,
        allowed_values: allowed_values,
        validate: block
      }
    end
  end
end