require "active_support"
require "active_support/core_ext/module/attribute_accessors"

module InertiaCable
  mattr_accessor :signed_stream_verifier_key
  mattr_accessor :debounce_delay, default: 0.5

  def self.signed_stream_verifier
    @signed_stream_verifier ||= ActiveSupport::MessageVerifier.new(
      signed_stream_verifier_key || Rails.application.secret_key_base + "inertia_cable",
      digest: "SHA256",
      serializer: JSON
    )
  end

  def self.reset_signed_stream_verifier!
    @signed_stream_verifier = nil
  end

  def self.broadcast(stream_name, payload)
    resolved = Streams::StreamName.stream_name_from(stream_name)
    ActionCable.server.broadcast(resolved, payload)
  end

  def self.suppressing_broadcasts(&block)
    InertiaCable::Suppressor.suppressing(&block)
  end
end

require "inertia_cable/streams/stream_name"
require "inertia_cable/broadcastable"
require "inertia_cable/channel"
require "inertia_cable/broadcast_job"
require "inertia_cable/debounce"
require "inertia_cable/suppressor"
require "inertia_cable/controller_helpers"
require "inertia_cable/engine" if defined?(Rails::Engine)
