module InertiaCable
  module Debounce
    def self.broadcast(stream_name, payload, delay: nil)
      delay = delay || InertiaCable.debounce_delay
      cache_key = "inertia_cable:debounce:#{stream_name}"
      return if Rails.cache.exist?(cache_key)

      Rails.cache.write(cache_key, true, expires_in: delay)
      InertiaCable.broadcast_callbacks.each { |cb| cb.call(stream_name, payload) }
      ActionCable.server.broadcast(stream_name, payload)
    end
  end
end
