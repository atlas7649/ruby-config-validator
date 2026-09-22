require 'yaml'
require 'json'
require_relative 'config_validator/errors'
require_relative 'config_validator/schema'

module ConfigValidator
  def self.validate(config_data, schema)
    errors = []

    schema.definitions.each do |name, rules|
      value = config_data[name]

      if value.nil?
        errors << "Missing required field: #{name}" if rules[:required]
        next
      end

      unless value.is_a?(rules[:type])
        errors << ValidationError.new(name, rules[:type], value)
      end
    end

    { valid: errors.empty?, errors: errors }
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