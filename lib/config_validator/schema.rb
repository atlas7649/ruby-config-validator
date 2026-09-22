module ConfigValidator
  class Schema
    attr_reader :definitions

    def initialize(&block)
      @definitions = {}
      instance_eval(&block) if block_given?
    end

    def field(name, type, required: true)
      @definitions[name.to_s] = { type: type, required: required }
    end
  end
end