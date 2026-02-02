require "active_support"
require "active_support/core_ext"
require "active_record"
require "active_job"
require "action_cable"

# Set up in-memory database
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

# Minimal Rails app stub for secret_key_base
module Rails
  def self.application
    @application ||= Struct.new(:secret_key_base).new("test_secret_key_base_for_inertia_cable_specs")
  end

  def self.cache
    @cache ||= ActiveSupport::Cache::MemoryStore.new
  end
end

require "inertia_cable"

# Include Broadcastable in ActiveRecord for specs
ActiveRecord::Base.include InertiaCable::Broadcastable

# Use test adapter for ActiveJob
ActiveJob::Base.queue_adapter = :test

RSpec.configure do |config|
  config.include ActiveJob::TestHelper

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_when_matching :focus
  config.order = :random

  config.before(:each) do
    InertiaCable.reset_signed_stream_verifier!
    InertiaCable::Suppressor.suppressed = false
    queue_adapter.enqueued_jobs.clear if respond_to?(:queue_adapter)
  end
end
