require "active_support/core_ext/module/attribute_accessors_per_thread"

module InertiaCable
  module Suppressor
    # Global suppression (across all models).
    #
    #   InertiaCable.suppressing_broadcasts { ... }
    #
    thread_mattr_accessor :suppressed, default: false

    def self.suppressing(&block)
      previous = suppressed
      self.suppressed = true
      yield
    ensure
      self.suppressed = previous
    end

    def self.suppressed?
      suppressed
    end
  end
end
