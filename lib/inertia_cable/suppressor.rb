module InertiaCable
  module Suppressor
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
