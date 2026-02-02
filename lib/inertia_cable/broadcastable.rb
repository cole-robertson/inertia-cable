module InertiaCable
  module Broadcastable
    extend ActiveSupport::Concern

    class_methods do
      def broadcasts_refreshes_to(stream)
        after_create_commit  -> { broadcast_refresh_later_to(stream) }
        after_update_commit  -> { broadcast_refresh_later_to(stream) }
        after_destroy_commit -> { broadcast_refresh_to(stream) }
      end

      def broadcasts_refreshes(stream_name = model_name.plural)
        after_create_commit  -> { broadcast_refresh_later_to(stream_name) }
        after_update_commit  -> { broadcast_refresh_later_to(stream_name) }
        after_destroy_commit -> { broadcast_refresh_to(stream_name) }
      end
    end

    def broadcast_refresh_to(stream)
      return if InertiaCable::Suppressor.suppressed?

      resolved = resolve_stream(stream)
      InertiaCable.broadcast(resolved, refresh_payload(:commit))
    end

    def broadcast_refresh_later_to(stream)
      return if InertiaCable::Suppressor.suppressed?

      resolved = resolve_stream(stream)
      InertiaCable::BroadcastJob.perform_later(
        InertiaCable::Streams::StreamName.stream_name_from(resolved),
        refresh_payload(:commit)
      )
    end

    def broadcast_refresh
      broadcast_refresh_to(self.class.model_name.plural)
    end

    private

    def resolve_stream(stream)
      case stream
      when Symbol then send(stream)
      when Proc   then stream.call(self)
      when String then stream
      else stream
      end
    end

    def refresh_payload(action)
      {
        type: "refresh",
        model: self.class.name,
        id: try(:id),
        action: action,
        timestamp: Time.current.iso8601
      }
    end
  end
end
