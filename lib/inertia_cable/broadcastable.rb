module InertiaCable
  module Broadcastable
    extend ActiveSupport::Concern

    included do
      thread_mattr_accessor :suppressed_inertia_cable_broadcasts, instance_accessor: false, default: false
    end

    class_methods do
      def suppressed_inertia_cable_broadcasts?
        suppressed_inertia_cable_broadcasts
      end

      # Broadcast refresh signal to a named stream on commit.
      #
      #   broadcasts_to :board
      #   broadcasts_to :board, on: [:create, :destroy]
      #   broadcasts_to :board, if: :published?
      #   broadcasts_to :board, unless: -> { draft? }
      #   broadcasts_to ->(post) { [post.board, :posts] }
      #   broadcasts_to :board, extra: { priority: "high" }
      #   broadcasts_to :board, extra: ->(post) { { category: post.category } }
      #   broadcasts_to :board, debounce: true
      #   broadcasts_to :board, debounce: 1.0
      #
      def broadcasts_to(stream, on: %i[create update destroy], if: nil, unless: nil, extra: nil, debounce: nil)
        callback_condition = binding.local_variable_get(:if)
        callback_unless    = binding.local_variable_get(:unless)
        events = Array(on)

        callback_options = {}
        callback_options[:if]     = callback_condition if callback_condition
        callback_options[:unless] = callback_unless    if callback_unless

        if events.sort == %i[create destroy update].sort
          after_commit(**callback_options) do
            broadcast_refresh_later_to(resolve_stream(stream), extra: resolve_extra(extra), debounce: debounce)
          end
        else
          if events.include?(:create)
            after_create_commit(**callback_options) do
              broadcast_refresh_later_to(resolve_stream(stream), extra: resolve_extra(extra), debounce: debounce)
            end
          end

          if events.include?(:update)
            after_update_commit(**callback_options) do
              broadcast_refresh_later_to(resolve_stream(stream), extra: resolve_extra(extra), debounce: debounce)
            end
          end

          if events.include?(:destroy)
            after_destroy_commit(**callback_options) do
              broadcast_refresh_later_to(resolve_stream(stream), extra: resolve_extra(extra), debounce: debounce)
            end
          end
        end
      end

      # Legacy alias — kept for compatibility with Turbo-style naming.
      alias_method :broadcasts_refreshes_to, :broadcasts_to

      # Convention-based: broadcasts to model_name.plural stream.
      #
      #   broadcasts
      #   broadcasts on: [:create, :destroy]
      #
      def broadcasts(**options)
        broadcasts_to(model_name.plural, **options)
      end

      # Legacy alias — kept for compatibility with Turbo-style naming.
      alias_method :broadcasts_refreshes, :broadcasts

      def suppressing_broadcasts(&block)
        original = suppressed_inertia_cable_broadcasts
        self.suppressed_inertia_cable_broadcasts = true
        yield
      ensure
        self.suppressed_inertia_cable_broadcasts = original
      end
    end

    # Broadcast refresh synchronously to explicit stream(s).
    #
    #   post.broadcast_refresh_to(board)
    #   post.broadcast_refresh_to(board, :posts)
    #   post.broadcast_refresh_to(board, extra: { priority: "high" })
    #   post.broadcast_refresh_to(board) { published? }
    #
    def broadcast_refresh_to(*streamables, extra: nil, &block)
      return if self.class.suppressed_inertia_cable_broadcasts?
      return if block && !instance_exec(&block)

      InertiaCable.broadcast(streamables, refresh_payload(extra: extra))
    end

    # Broadcast refresh asynchronously to explicit stream(s).
    #
    #   post.broadcast_refresh_later_to(board)
    #   post.broadcast_refresh_later_to(board, :posts)
    #   post.broadcast_refresh_later_to(board, extra: { priority: "high" })
    #   post.broadcast_refresh_later_to(board, debounce: true)
    #   post.broadcast_refresh_later_to(board) { published? }
    #
    def broadcast_refresh_later_to(*streamables, extra: nil, debounce: nil, &block)
      return if self.class.suppressed_inertia_cable_broadcasts?
      return if block && !instance_exec(&block)

      resolved = InertiaCable::Streams::StreamName.stream_name_from(streamables)
      payload = refresh_payload(extra: extra)

      if debounce
        delay = debounce == true ? nil : debounce
        InertiaCable::Debounce.broadcast(resolved, payload, delay: delay)
      else
        InertiaCable::BroadcastJob.perform_later(resolved, payload)
      end
    end

    # Broadcast refresh synchronously to model_name.plural.
    def broadcast_refresh(&block)
      broadcast_refresh_to(self.class.model_name.plural, &block)
    end

    # Broadcast refresh asynchronously to model_name.plural.
    def broadcast_refresh_later(&block)
      broadcast_refresh_later_to(self.class.model_name.plural, &block)
    end

    # Broadcast a direct message synchronously to explicit stream(s).
    #
    #   post.broadcast_message_to(board, data: { progress: 50 })
    #   post.broadcast_message_to(board, :posts, data: { progress: 50 })
    #   post.broadcast_message_to(board, data: { progress: 50 }) { running? }
    #
    def broadcast_message_to(*streamables, data:, &block)
      return if self.class.suppressed_inertia_cable_broadcasts?
      return if block && !instance_exec(&block)

      InertiaCable.broadcast(streamables, message_payload(data: data))
    end

    # Broadcast a direct message asynchronously to explicit stream(s).
    #
    #   post.broadcast_message_later_to(board, data: { progress: 50 })
    #   post.broadcast_message_later_to(board, :posts, data: { progress: 50 })
    #   post.broadcast_message_later_to(board, data: { progress: 50 }) { running? }
    #
    def broadcast_message_later_to(*streamables, data:, &block)
      return if self.class.suppressed_inertia_cable_broadcasts?
      return if block && !instance_exec(&block)

      resolved = InertiaCable::Streams::StreamName.stream_name_from(streamables)
      InertiaCable::BroadcastJob.perform_later(resolved, message_payload(data: data))
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

    def resolve_extra(extra)
      case extra
      when Proc then extra.call(self)
      when Hash then extra
      else nil
      end
    end

    def inferred_action
      if destroyed?
        "destroy"
      elsif previously_new_record?
        "create"
      else
        "update"
      end
    end

    def refresh_payload(extra: nil)
      payload = {
        type: "refresh",
        model: self.class.name,
        id: try(:id),
        action: inferred_action,
        timestamp: Time.current.iso8601
      }
      payload[:extra] = extra if extra.present?
      payload
    end

    def message_payload(data:)
      { type: "message", data: data }
    end
  end
end
