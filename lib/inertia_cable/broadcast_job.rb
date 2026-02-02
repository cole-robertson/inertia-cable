module InertiaCable
  class BroadcastJob < ActiveJob::Base
    queue_as :default
    discard_on ActiveJob::DeserializationError

    def perform(stream_name, payload)
      InertiaCable.broadcast(stream_name, payload)
    end
  end
end
