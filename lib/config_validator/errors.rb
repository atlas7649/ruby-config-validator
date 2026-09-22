module ConfigValidator
  class ValidationError < StandardError
    attr_reader :path, :expected, :actual

    def initialize(path, expected, actual)
      @path = path
      @expected = expected
      @actual = actual
      super("Invalid value at '#{path}': expected #{expected}, got #{actual.inspect}")
    end
  end
end