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
    expect(result[:errors].first).to be_a(ConfigValidator::ValidationError)
    expect(result[:errors].first.path).to eq('host')
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
    expect(result[:errors].first.path).to eq('database.pass')
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
    expect(result[:errors].first).to be_a(ConfigValidator::ValidationError)
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
    expect(result[:valid]). to be false
    expect(result[:errors].first.path).to eq('nodes[1].role')
  end

  it 'detects unexpected keys in strict mode' do
    config = { 'port' => 8080, 'host' => 'localhost', 'unknown_key' => 'value' }
    result = ConfigValidator.validate(config, schema, strict: true)
    expect(result[:valid]).to be false
    expect(result[:errors].first).to be_a(ConfigValidator::ValidationError)
    expect(result[:errors].first.path).to eq('unknown_key')
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
    expect(result[:errors].first.path).to eq('database.extra')
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

  it 'handles optional array elements' do
    opt_elem_schema = ConfigValidator::Schema.new do
      field :tags, Array, element_type: String, element_optional: true
    end

    config = { 'tags' => ['ruby', nil, 'validation'] }
    expect(ConfigValidator.validate(config, opt_elem_schema)[:valid]).to be true

    strict_elem_schema = ConfigValidator::Schema.new do
      field :tags, Array, element_type: String, element_optional: false
    end
    result = ConfigValidator.validate(config, strict_elem_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('tags[1]')
  end

  it 'validates float types' do
    float_schema = ConfigValidator::Schema.new do
      field :threshold, Float
    end

    expect(ConfigValidator.validate({ 'threshold' => 0.5 }, float_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'threshold' => '0.5' }, float_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to eq(Float)
  end

  it 'validates arrays of floats' do
    float_arr_schema = ConfigValidator::Schema.new do
      field :weights, Array, element_type: Float
    end

    expect(ConfigValidator.validate({ 'weights' => [0.1, 0.2, 0.7] }, float_arr_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'weights' => [0.1, '0.2'] }, float_arr_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('weights[1]')
  end

  it 'handles optional array elements for nested schemas' do
    node_schema = ConfigValidator::Schema.new do
      field :ip, String
    end

    cluster_schema = ConfigValidator::Schema.new do
      field :nodes, Array, element_type: ConfigValidator::Schema, schema: node_schema, element_optional: true
    end

    config = {
      'nodes' => [
        { 'ip' => '10.0.0.1' },
        nil,
        { 'ip' => '10.0.0.2' }
      ]
    }
    expect(ConfigValidator.validate(config, cluster_schema)[:valid]).to be true
  end

  it 'validates allowed values' do
    env_schema = ConfigValidator::Schema.new do
      field :environment, String, allowed_values: ['development', 'staging', 'production']
    end

    expect(ConfigValidator.validate({ 'environment' => 'production' }, env_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'environment' => 'test' }, env_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('environment')
    expect(result[:errors].first.expected).to include('development', 'staging', 'production')
  end

  it 'validates numeric ranges' do
    range_schema = ConfigValidator::Schema.new do
      field :port, Integer, min: 1024, max: 65535
      field :ratio, Float, min: 0.0, max: 1.0
    end

    expect(ConfigValidator.validate({ 'port' => 8080, 'ratio' => 0.5 }, range_schema)[:valid]).to be true

    result_low = ConfigValidator.validate({ 'port' => 80, 'ratio' => 0.5 }, range_schema)
    expect(result_low[:valid]).to be false
    expect(result_low[:errors].first.expected).to eq('Minimum 1024')

    result_high = ConfigValidator.validate({ 'port' => 8080, 'ratio' => 1.1 }, range_schema)
    expect(result_high[:valid]).to be false
    expect(result_high[:errors].first.expected).to eq('Maximum 1.0')
  end

  it 'validates string patterns' do
    pattern_schema = ConfigValidator::Schema.new do
      field :email, String, pattern: /\A[^@\s]+@[^@\s]+\z/
      field :version, String, pattern: /\A\d+\.\d+\.\d+\z/
    end

    expect(ConfigValidator.validate({ 'email' => 'test@example.com', 'version' => '1.0.0' }, pattern_schema)[:valid]).to be true

    result_email = ConfigValidator.validate({ 'email' => 'invalid-email', 'version' => '1.0.0' }, pattern_schema)
    expect(result_email[:valid]).to be false
    expect(result_email[:errors].first.path).to eq('email')

    result_version = ConfigValidator.validate({ 'email' => 'test@example.com', 'version' => '1.0' }, pattern_schema)
    expect(result_version[:valid]).to be false
    expect(result_version[:errors].first.path).to eq('version')
  end

  it 'validates array lengths' do
    len_schema = ConfigValidator::Schema.new do
      field :servers, Array, min_length: 1, max_length: 3
    end

    expect(ConfigValidator.validate({ 'servers' => ['s1'] }, len_schema)[:valid]).to be true
    expect(ConfigValidator.validate({ 'servers' => ['s1', 's2', 's3'] }, len_schema)[:valid]).to be true

    result_too_short = ConfigValidator.validate({ 'servers' => [] }, len_schema)
    expect(result_too_short[:valid]).to be false
    expect(result_too_short[:errors].first.expected).to eq('Minimum length 1')

    result_too_long = ConfigValidator.validate({ 'servers' => ['s1', 's2', 's3', 's4'] }, len_schema)
    expect(result_too_long[:valid]).to be false
    expect(result_too_long[:errors].first.expected).to eq('Maximum length 3')
  end

  it 'validates non-empty strings' do
    non_empty_schema = ConfigValidator::Schema.new do
      field :api_token, String, non_empty: true
    end

    expect(ConfigValidator.validate({ 'api_token' => 'xyz123' }, non_empty_schema)[:valid]).to be true
    
    result_empty = ConfigValidator.validate({ 'api_token' => '' }, non_empty_schema)
    expect(result_empty[:valid]).to be false
    expect(result_empty[:errors].first.expected).to eq('Non-empty string')

    result_blank = ConfigValidator.validate({ 'api_token' => '   ' }, non_empty_schema)
    expect(result_blank[:valid]).to be false
    expect(result_blank[:errors].first.expected).to eq('Non-empty string')
  end

  it 'allows custom error messages in validation blocks' do
    custom_msg_schema = ConfigValidator::Schema.new do
      field :port, Integer do |val|
        val >= 1024 ? true : 'Port must be in the non-privileged range (>= 1024)'
      end
    end

    result = ConfigValidator.validate({ 'port' => 80 }, custom_msg_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to eq('Port must be in the non-privileged range (>= 1024)')
  end

  it 'allows omitting optional fields without default' do
    opt_schema = ConfigValidator::Schema.new do
      field :optional_field, String, required: false
    end
    expect(ConfigValidator.validate({}, opt_schema)[:valid]).to be true
  end

  it 'validates union types for fields' do
    union_schema = ConfigValidator::Schema.new do
      field :timeout, [Integer, String]
    end

    expect(ConfigValidator.validate({ 'timeout' => 30 }, union_schema)[:valid]).to be true
    expect(ConfigValidator.validate({ 'timeout' => '30s' }, union_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'timeout' => true }, union_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to include('Integer', 'String')
  end

  it 'validates union types for array elements' do
    union_arr_schema = ConfigValidator::Schema.new do
      field :values, Array, element_type: [Integer, Float]
    end

    expect(ConfigValidator.validate({ 'values' => [1, 2.5, 3] }, union_arr_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'values' => [1, '2.5'] }, union_arr_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('values[1]')
  end

  it 'provides a valid? convenience method' do
    config = { 'port' => 8080, 'host' => 'localhost' }
    expect(ConfigValidator.valid?(config, schema)).to be true
    
    config_invalid = { 'port' => 'invalid' }
    expect(ConfigValidator.valid?(config_invalid, schema)).to be false
  end
end