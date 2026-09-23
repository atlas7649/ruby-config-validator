require 'rspec'
require_relative '../lib/config_validator'

RSpec.describe ConfigValidator do
  let(:schema) do
    ConfigValidator::Schema.new do
      field :port, Integer
      field :host, String
      field :debug, :boolean, required: false, default: false
    end
  end

  it 'validates a correct configuration' do
    config = { 'port' => 8080, 'host' => 'localhost', 'debug' => true }
    result = ConfigValidator.validate(config, schema)
    expect(result[:valid]).to be true
  end

  it 'detects missing required fields' do
    config = { 'port' => 8080 }
    result = ConfigValidator.validate(config, schema)
    expect(result[:valid]).to be false
    expect(result[:errors]).to include('Missing required field: host')
  end

  it 'detects type mismatches' do
    config = { 'port' => '8080', 'host' => 'localhost' }
    result = ConfigValidator.validate(config, schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first).to be_a(ConfigValidator::ValidationError)
  end

  it 'applies default values for missing optional fields' do
    config = { 'port' => 8080, 'host' => 'localhost' }
    result = ConfigValidator.validate(config, schema)
    expect(result[:valid]).to be true
    expect(result[:data]['debug']).to eq(false)
  end

  it 'validates nested configurations' do
    db_schema = ConfigValidator::Schema.new do
      field :user, String
      field :pass, String
    end

    complex_schema = ConfigValidator::Schema.new do
      field :app_name, String
      field :database, ConfigValidator::Schema, schema: db_schema
    end

    config = {
      'app_name' => 'MyApp',
      'database' => { 'user' => 'admin', 'pass' => 'secret' }
    }
    result = ConfigValidator.validate(config, complex_schema)
    expect(result[:valid]).to be true
  end

  it 'detects errors in nested configurations' do
    db_schema = ConfigValidator::Schema.new do
      field :user, String
      field :pass, String
    end

    complex_schema = ConfigValidator::Schema.new do
      field :app_name, String
      field :database, ConfigValidator::Schema, schema: db_schema
    end

    config = {
      'app_name' => 'MyApp',
      'database' => { 'user' => 'admin' } # missing pass
    }
    result = ConfigValidator.validate(config, complex_schema)
    expect(result[:valid]).to be false
    expect(result[:errors]).to include('database.Missing required field: pass')
  end

  it 'handles optional nested configurations' do
    db_schema = ConfigValidator::Schema.new do
      field :user, String
    end

    complex_schema = ConfigValidator::Schema.new do
      field :app_name, String
      field :database, ConfigValidator::Schema, schema: db_schema, required: false
    end

    config = { 'app_name' => 'MyApp' }
    result = ConfigValidator.validate(config, complex_schema)
    expect(result[:valid]).to be true
  end

  it 'validates array types and elements' do
    arr_schema = ConfigValidator::Schema.new do
      field :tags, Array, element_type: String
    end

    config = { 'tags' => ['ruby', 'validation'] }
    expect(ConfigValidator.validate(config, arr_schema)[:valid]).to be true

    config_invalid = { 'tags' => ['ruby', 123] }
    result = ConfigValidator.validate(config_invalid, arr_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('tags[1]')
  end

  it 'runs custom validation blocks' do
    custom_schema = ConfigValidator::Schema.new do
      field :port, Integer do |val|
        val >= 1024 && val <= 65535
      end
    end

    config_valid = { 'port' => 8080 }
    expect(ConfigValidator.validate(config_valid, custom_schema)[:valid]).to be true

    config_invalid = { 'port' => 80 }
    result = ConfigValidator.validate(config_invalid, custom_schema)
    expect(result[:valid]).to be false
    expect(result[:errors]).to include('Validation failed for field: port')
  end

  it 'validates arrays of nested schemas' do
    node_schema = ConfigValidator::Schema.new do
      field :ip, String
      field :role, String
    end

    cluster_schema = ConfigValidator::Schema.new do
      field :nodes, Array, element_type: ConfigValidator::Schema, schema: node_schema
    end

    config = {
      'nodes' => [
        { 'ip' => '10.0.0.1', 'role' => 'master' },
        { 'ip' => '10.0.0.2', 'role' => 'worker' }
      ]
    }
    expect(ConfigValidator.validate(config, cluster_schema)[:valid]).to be true

    config_invalid = {
      'nodes' => [
        { 'ip' => '10.0.0.1', 'role' => 'master' },
        { 'ip' => '10.0.0.2' } # missing role
      ]
    }
    result = ConfigValidator.validate(config_invalid, cluster_schema)
    expect(result[:valid]).to be false
    expect(result[:errors]).to include('nodes[1].Missing required field: role')
  end

  it 'detects unexpected keys in strict mode' do
    config = { 'port' => 8080, 'host' => 'localhost', 'unknown_key' => 'value' }
    result = ConfigValidator.validate(config, schema, strict: true)
    expect(result[:valid]).to be false
    expect(result[:errors]).to include('Unexpected configuration key: unknown_key')
  end

  it 'detects unexpected keys in nested schemas in strict mode' do
    db_schema = ConfigValidator::Schema.new do
      field :user, String
    end

    complex_schema = ConfigValidator::Schema.new do
      field :database, ConfigValidator::Schema, schema: db_schema
    end

    config = {
      'database' => { 'user' => 'admin', 'extra' => 'something' }
    }
    result = ConfigValidator.validate(config, complex_schema, strict: true)
    expect(result[:valid]).to be false
    expect(result[:errors]).to include('database.Unexpected configuration key: extra')
  end

  it 'validates boolean types' do
    bool_schema = ConfigValidator::Schema.new do
      field :enabled, :boolean
    end

    expect(ConfigValidator.validate({ 'enabled' => true }, bool_schema)[:valid]).to be true
    expect(ConfigValidator.validate({ 'enabled' => false }, bool_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'enabled' => 'true' }, bool_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to eq('Boolean')
  end

  it 'validates arrays of booleans' do
    bool_arr_schema = ConfigValidator::Schema.new do
      field :flags, Array, element_type: :boolean
    end

    expect(ConfigValidator.validate({ 'flags' => [true, false, true] }, bool_arr_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'flags' => [true, 1] }, bool_arr_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('flags[1]')
  end

  it 'handles optional arrays' do
    opt_arr_schema = ConfigValidator::Schema.new do
      field :tags, Array, element_type: String, required: false
    end

    config = {}
    expect(ConfigValidator.validate(config, opt_arr_schema)[:valid]).to be true
  end
end