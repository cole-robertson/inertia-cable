module InertiaCable
  module Debounce
    def self.broadcast(stream_name, payload)
      cache_key = "inertia_cable:debounce:#{stream_name}"
      return if Rails.cache.exist?(cache_key)

      Rails.cache.write(cache_key, true, expires_in: InertiaCable.debounce_delay)
      ActionCable.server.broadcast(stream_name, payload)
    end
  end
end
