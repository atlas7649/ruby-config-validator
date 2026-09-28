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

  it 'validates nested configurations with blocks' do
    complex_schema = ConfigValidator::Schema.new do
      field :app_name, String
      field :database, ConfigValidator::Schema do
        field :user, String
        field :pass, String
      end
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
    expect(result[:valid]).to be false
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

  it 'validates max_elements for arrays' do
    max_elem_schema = ConfigValidator::Schema.new do
      field :items, Array, max_elements: 2
    end

    expect(ConfigValidator.validate({ 'items' => [1, 2] }, max_elem_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'items' => [1, 2, 3] }, max_elem_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to eq('Maximum elements 2')
    expect(result[:errors].first.actual).to eq(3)
  end

  it 'validates min_elements for arrays' do
    min_elem_schema = ConfigValidator::Schema.new do
      field :items, Array, min_elements: 2
    end

    expect(ConfigValidator.validate({ 'items' => [1, 2] }, min_elem_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'items' => [1] }, min_elem_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to eq('Minimum elements 2')
    expect(result[:errors].first.actual).to eq(1)
  end

  it 'validates element_allowed_values for arrays' do
    allowed_elem_schema = ConfigValidator::Schema.new do
      field :roles, Array, element_type: String, element_allowed_values: ['admin', 'user', 'guest']
    end

    expect(ConfigValidator.validate({ 'roles' => ['admin', 'user'] }, allowed_elem_schema)[:valid]).to be true

    result = ConfigValidator.validate({ 'roles' => ['admin', 'superuser'] }, allowed_elem_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('roles[1]')
    expect(result[:errors].first.expected).to include('admin', 'user', 'guest')
  end

  it 'supports description in schema fields' do
    desc_schema = ConfigValidator::Schema.new do
      field :port, Integer, description: 'The port to listen on'
    end
    expect(desc_schema.definitions['port'][:description]).to eq('The port to listen on')
  end

  it 'supports cross-field validation' do
    cross_schema = ConfigValidator::Schema.new do
      field :ssl_enabled, :boolean
      field :cert_path, String, required: false do |val, config|
        if config['ssl_enabled'] && (val.nil? || val.strip.empty?)
          'cert_path is required when ssl_enabled is true'
        else
          true
        end
      end
    end

    # Valid: SSL off, no cert
    expect(ConfigValidator.validate({ 'ssl_enabled' => false }, cross_schema)[:valid]).to be true
    # Valid: SSL on, has cert
    expect(ConfigValidator.validate({ 'ssl_enabled' => true, 'cert_path' => '/etc/ssl/cert.pem' }, cross_schema)[:valid]).to be true
    # Invalid: SSL on, no cert
    result = ConfigValidator.validate({ 'ssl_enabled' => true }, cross_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to eq('cert_path is required when ssl_enabled is true')
  end

  it 'validates uniqueness of elements in an array of hashes' do
    unique_schema = ConfigValidator::Schema.new do
      field :nodes, Array, unique_elements: :ip
    end

    config_valid = {
      'nodes' => [
        { 'ip' => '10.0.0.1', 'id' => 1 },
        { 'ip' => '10.0.0.2', 'id' => 2 }
      ]
    }
    expect(ConfigValidator.validate(config_valid, unique_schema)[:valid]).to be true

    config_invalid = {
      'nodes' => [
        { 'ip' => '10.0.0.1', 'id' => 1 },
        { 'ip' => '10.0.0.1', 'id' => 2 }
      ]
    }
    result = ConfigValidator.validate(config_invalid, unique_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('nodes[1].ip')
    expect(result[:errors].first.expected).to eq('Unique value')
  end

  it 'validates conditional requirements' do
    cond_schema = ConfigValidator::Schema.new do
      field :use_auth, :boolean, default: false
      field :auth_token, String, required: false, required_if: :use_auth
    end

    # Valid: auth off, no token
    expect(ConfigValidator.validate({ 'use_auth' => false }, cond_schema)[:valid]).to be true
    # Valid: auth on, has token
    expect(ConfigValidator.validate({ 'use_auth' => true, 'auth_token' => 'secret' }, cond_schema)[:valid]).to be true
    # Invalid: auth on, no token
    result = ConfigValidator.validate({ 'use_auth' => true }, cond_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('auth_token')
  end

  it 'handles exceptions in custom validation blocks' do
    crash_schema = ConfigValidator::Schema.new do
      field :port, Integer do |val|
        raise "Unexpected error"
      end
    end

    result = ConfigValidator.validate({ 'port' => 8080 }, crash_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to include('Validation Exception')
  end

  it 'supports custom required messages' do
    custom_req_schema = ConfigValidator::Schema.new do
      field :api_key, String, required_message: 'API key is missing from configuration'
    end

    result = ConfigValidator.validate({}, custom_req_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to eq('API key is missing from configuration')
  end

  it 'handles allow_nil option' do
    nil_schema = ConfigValidator::Schema.new do
      field :optional_nil, String, required: false, allow_nil: true
      field :no_nil, String, required: false, allow_nil: false
    end

    # allow_nil: true -> valid
    expect(ConfigValidator.validate({ 'optional_nil' => nil }, nil_schema)[:valid]).to be true
    # allow_nil: false -> invalid (type mismatch String vs NilClass)
    result = ConfigValidator.validate({ 'no_nil' => nil }, nil_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('no_nil')
  end

  it 'does not apply default when allow_nil is true and value is nil' do
    def_nil_schema = ConfigValidator::Schema.new do
      field :val, String, required: false, default: 'default', allow_nil: true
    end

    result = ConfigValidator.validate({ 'val' => nil }, def_nil_schema)
    expect(result[:valid]).to be true
    expect(result[:data]['val']).to be_nil
  end

  it 'validates string length' do
    str_len_schema = ConfigValidator::Schema.new do
      field :username, String, min_length: 3, max_length: 10
    end

    expect(ConfigValidator.validate({ 'username' => 'bob' }, str_len_schema)[:valid]).to be true
    expect(ConfigValidator.validate({ 'username' => 'bobsmith' }, str_len_schema)[:valid]).to be true

    result_short = ConfigValidator.validate({ 'username' => 'bo' }, str_len_schema)
    expect(result_short[:valid]).to be false
    expect(result_short[:errors].first.expected).to eq('Minimum length 3')

    result_long = ConfigValidator.validate({ 'username' => 'bobsmithson' }, str_len_schema)
    expect(result_long[:valid]).to be false
    expect(result_long[:errors].first.expected).to eq('Maximum length 10')
  end

  it 'returns a list of defined fields' do
    s = ConfigValidator::Schema.new do
      field :a, String
      field :b, Integer
    end
    expect(s.fields).to contain_exactly('a', 'b')
  end

  it 'supports required_if_value for specific values' do
    cond_val_schema = ConfigValidator::Schema.new do
      field :mode, String
      field :mode_config, String, required: false, required_if: :mode, required_if_value: 'advanced'
    end

    # Valid: mode is basic
    expect(ConfigValidator.validate({ 'mode' => 'basic' }, cond_val_schema)[:valid]).to be true
    # Valid: mode is advanced, config provided
    expect(ConfigValidator.validate({ 'mode' => 'advanced', 'mode_config' => 'val' }, cond_val_schema)[:valid]).to be true
    # Invalid: mode is advanced, config missing
    result = ConfigValidator.validate({ 'mode' => 'advanced' }, cond_val_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('mode_config')
  end

  it 'validates custom callable types' do
    is_even = ->(val) { val.is_a?(Integer) && val.even? }
    custom_type_schema = ConfigValidator::Schema.new do
      field :even_number, is_even
    end

    expect(ConfigValidator.validate({ 'even_number' => 2 }, custom_type_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'even_number' => 3 }, custom_type_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to eq('Custom Type')
  end

  it 'validates custom callable types in arrays' do
    is_even = ->(val) { val.is_a?(Integer) && val.even? }
    custom_type_schema = ConfigValidator::Schema.new do
      field :even_numbers, Array, element_type: is_even
    end

    expect(ConfigValidator.validate({ 'even_numbers' => [2, 4, 6] }, custom_type_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'even_numbers' => [2, 3, 4] }, custom_type_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('even_numbers[1]')
    expect(result[:errors].first.expected).to eq('Custom Type')
  end

  it 'validates custom callable types in union types' do
    is_even = ->(val) { val.is_a?(Integer) && val.even? }
    union_custom_schema = ConfigValidator::Schema.new do
      field :val, [is_even, String]
    end

    expect(ConfigValidator.validate({ 'val' => 2 }, union_custom_schema)[:valid]).to be true
    expect(ConfigValidator.validate({ 'val' => 'hello' }, union_custom_schema)[:valid]).to be true
    
    result = ConfigValidator.validate({ 'val' => 3 }, union_custom_schema)
    expect(result[:valid]).to be false
  end

  it 'supports custom type messages' do
    custom_type_msg_schema = ConfigValidator::Schema.new do
      field :port, Integer, type_message: 'Port must be a valid number'
    end

    result = ConfigValidator.validate({ 'port' => 'invalid' }, custom_type_msg_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to eq('Port must be a valid number')
  end

  it 'exports schema to hash via to_h' do
    s = ConfigValidator::Schema.new do
      field :port, Integer, default: 80
      field :db, ConfigValidator::Schema do
        field :host, String
      end
    end
    hash = s.to_h
    expect(hash).to have_key('port')
    expect(hash['port'][:default]).to eq(80)
    expect(hash['db']).to be_a(Hash)
    expect(hash['db']).to have_key('host')
  end

  it 'validates non_nil constraint' do
    non_nil_schema = ConfigValidator::Schema.new do
      field :optional_but_not_nil, String, required: false, non_nil: true
    end

    # Field missing entirely -> valid (required: false)
    expect(ConfigValidator.validate({}, non_nil_schema)[:valid]).to be true
    # Field present and valid -> valid
    expect(ConfigValidator.validate({ 'optional_but_not_nil' => 'val' }, non_nil_schema)[:valid]).to be true
    # Field present but nil -> invalid
    result = ConfigValidator.validate({ 'optional_but_not_nil' => nil }, non_nil_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to eq('Cannot be nil')
  end

  it 'supports custom element type messages for arrays' do
    arr_schema = ConfigValidator::Schema.new do
      field :ids, Array, element_type: Integer, element_type_message: 'IDs must be integers'
    end

    result = ConfigValidator.validate({ 'ids' => [1, '2'] }, arr_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.expected).to eq('IDs must be integers')
  end

  it 'validates mutually exclusive fields' do
    exclusive_schema = ConfigValidator::Schema.new do
      field :api_key, String, required: false, exclusive_with: :oauth_token
      field :oauth_token, String, required: false
    end

    # Valid: only api_key
    expect(ConfigValidator.validate({ 'api_key' => 'key' }, exclusive_schema)[:valid]).to be true
    # Valid: only oauth_token
    expect(ConfigValidator.validate({ 'oauth_token' => 'token' }, exclusive_schema)[:valid]).to be true
    # Invalid: both provided
    result = ConfigValidator.validate({ 'api_key' => 'key', 'oauth_token' => 'token' }, exclusive_schema)
    expect(result[:valid]).to be false
    expect(result[:errors].first.path).to eq('api_key')
    expect(result[:errors].first.expected).to eq('Mutually exclusive with oauth_token')
  end

  it 'validates min_elements and max_elements for arrays of nested schemas' do
    node_schema = ConfigValidator::Schema.new do
      field :ip, String
    end

    cluster_schema = ConfigValidator::Schema.new do
      field :nodes, Array, element_type: ConfigValidator::Schema, schema: node_schema, min_elements: 1, max_elements: 2
    end

    # Valid: 1 node
    expect(ConfigValidator.validate({ 'nodes' => [{ 'ip' => '1.1.1.1' }] }, cluster_schema)[:valid]).to be true
    # Valid: 2 nodes
    expect(ConfigValidator.validate({ 'nodes' => [{ 'ip' => '1.1.1.1' }, { 'ip' => '1.1.1.2' }] }, cluster_schema)[:valid]).to be true
    # Invalid: 0 nodes
    result_empty = ConfigValidator.validate({ 'nodes' => [] }, cluster_schema)
    expect(result_empty[:valid]).to be false
    expect(result_empty[:errors].first.expected).to eq('Minimum elements 1')
    # Invalid: 3 nodes
    result_too_many = ConfigValidator.validate({ 'nodes' => [{ 'ip' => '1.1.1.1' }, { 'ip' => '1.1.1.2' }, { 'ip' => '1.1.1.3' }] }, cluster_schema)
    expect(result_too_many[:valid]).to be false
    expect(result_too_many[:errors].first.expected).to eq('Maximum elements 2')
  end
end