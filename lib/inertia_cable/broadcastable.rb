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
      #   broadcasts_refreshes_to :board
      #   broadcasts_refreshes_to :board, on: [:create, :destroy]
      #   broadcasts_refreshes_to :board, if: :published?
      #   broadcasts_refreshes_to :board, unless: -> { draft? }
      #   broadcasts_refreshes_to ->(post) { [post.board, :posts] }
      #
      def broadcasts_refreshes_to(stream, on: %i[create update destroy], if: nil, unless: nil)
        callback_condition = binding.local_variable_get(:if)
        callback_unless    = binding.local_variable_get(:unless)
        events = Array(on)

        callback_options = {}
        callback_options[:if]     = callback_condition if callback_condition
        callback_options[:unless] = callback_unless    if callback_unless

        if events.sort == %i[create destroy update].sort
          after_commit(**callback_options) do
            broadcast_refresh_later_to(resolve_stream(stream))
          end
        else
          if events.include?(:create)
            after_create_commit(**callback_options) do
              broadcast_refresh_later_to(resolve_stream(stream))
            end
          end

          if events.include?(:update)
            after_update_commit(**callback_options) do
              broadcast_refresh_later_to(resolve_stream(stream))
            end
          end

          if events.include?(:destroy)
            after_destroy_commit(**callback_options) do
              broadcast_refresh_later_to(resolve_stream(stream))
            end
          end
        end
      end

      # Convention-based: broadcasts to model_name.plural stream.
      #
      #   broadcasts_refreshes
      #   broadcasts_refreshes on: [:create, :destroy]
      #
      def broadcasts_refreshes(**options)
        broadcasts_refreshes_to(model_name.plural, **options)
      end

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
    #
    def broadcast_refresh_to(*streamables)
      return if self.class.suppressed_inertia_cable_broadcasts?

      InertiaCable.broadcast(streamables, refresh_payload)
    end

    # Broadcast refresh asynchronously to explicit stream(s).
    #
    #   post.broadcast_refresh_later_to(board)
    #   post.broadcast_refresh_later_to(board, :posts)
    #
    def broadcast_refresh_later_to(*streamables)
      return if self.class.suppressed_inertia_cable_broadcasts?

      resolved = InertiaCable::Streams::StreamName.stream_name_from(streamables)
      InertiaCable::BroadcastJob.perform_later(resolved, refresh_payload)
    end

    # Broadcast refresh synchronously to model_name.plural.
    def broadcast_refresh
      broadcast_refresh_to(self.class.model_name.plural)
    end

    # Broadcast refresh asynchronously to model_name.plural.
    def broadcast_refresh_later
      broadcast_refresh_later_to(self.class.model_name.plural)
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

    def inferred_action
      if destroyed?
        "destroy"
      elsif previously_new_record?
        "create"
      else
        "update"
      end
    end

    def refresh_payload
      {
        type: "refresh",
        model: self.class.name,
        id: try(:id),
        action: inferred_action,
        timestamp: Time.current.iso8601
      }
    end
  end
end
