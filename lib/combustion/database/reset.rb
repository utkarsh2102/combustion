# frozen_string_literal: true

class Combustion::Database::Reset
  UnsupportedDatabase = Class.new StandardError

  OPERATOR_PATTERNS = {
    Combustion::Databases::MySQL      => [/mysql/],
    Combustion::Databases::PostgreSQL => [/postgres/, /postgis/],
    Combustion::Databases::SQLite     => [/sqlite/],
    Combustion::Databases::SQLServer  => [/sqlserver/],
    Combustion::Databases::Oracle     => %w[ oci oracle ],
    Combustion::Databases::Firebird   => %w[ firebird ]
  }.freeze

  RAILS_DEFAULT_ENVIRONMENTS = %w[ development production test ].freeze

  def self.call
    new.call
  end

  def initialize
    ActiveRecord::Base.configurations = YAML.safe_load(
      ERB.new(database_yaml).result, [], [], true
    )
  end

  def call
    resettable_db_configs.each do |configuration|
      adapter = configuration[:adapter] ||
                configuration[:url].split("://").first

      operator_class(adapter).new(configuration).reset
    end
  end

  private

  def database_yaml
    File.read "#{Rails.root}/config/database.yml"
  end

  def operator_class(adapter)
    klass = nil
    OPERATOR_PATTERNS.each do |operator, keys|
      klass = operator if keys.any? { |key| adapter[key] }
    end
    return klass if klass

    raise UnsupportedDatabase, "Unsupported database type: #{adapter}"
  end

  # All database configs except Rails default environments
  # that are not currently in use
  def resettable_db_configs
    if ActiveRecord::VERSION::STRING.to_f > 6.0
      return resettable_db_configs_for_6_1
    end

    all_configurations      = ActiveRecord::Base.configurations.to_h
    unused_environments     = RAILS_DEFAULT_ENVIRONMENTS - [Rails.env.to_s]
    resettable_environments = all_configurations.keys - unused_environments

    all_configurations.
      select { |name| resettable_environments.include?(name) }.
      values.
      collect(&:with_indifferent_access)
  end

  def resettable_db_configs_for_6_1
    all_configurations      = ActiveRecord::Base.configurations.configurations
    unused_environments     = RAILS_DEFAULT_ENVIRONMENTS - [Rails.env.to_s]
    resettable_environments = all_configurations.collect(&:env_name).uniq -
                              unused_environments

    all_configurations.
      select { |config| resettable_environments.include?(config.env_name) }.
      collect(&:configuration_hash)
  end
end
