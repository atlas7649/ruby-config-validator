require 'yaml'
require 'json'
require_relative 'config_validator/errors'
require_relative 'config_validator/schema'

module ConfigValidator
  def self.validate(config_data, schema)
    errors = []
    validated_data = config_data.dup

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

      unless value.is_a?(rules[:type])
        errors << ValidationError.new(name, rules[:type], value)
      end
    end

    { valid: errors.empty?, errors: errors, data: validated_data }
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