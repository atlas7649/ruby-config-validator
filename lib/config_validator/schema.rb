module ConfigValidator
  class Schema
    attr_reader :definitions

    def initialize(&block)
      @definitions = {}
      instance_eval(&block) if block_given?
    end

    def field(name, type, required: true, default: nil)
      @definitions[name.to_s] = { type: type, required: required, default: default }
    end
  end
end