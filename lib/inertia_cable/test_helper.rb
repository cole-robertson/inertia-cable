module InertiaCable
  module TestHelper
    # Assert that broadcasts were made to the given stream.
    #
    #   assert_broadcasts_on(chat) { Message.create!(chat: chat) }
    #   assert_broadcasts_on(chat, count: 2) { ... }
    #   assert_broadcasts_on("posts") { post.broadcast_refresh }
    #
    def assert_broadcasts_on(*streamables, count: nil, &block)
      payloads = capture_broadcasts_on(*streamables, &block)
      stream = InertiaCable::Streams::StreamName.stream_name_from(streamables)

      if count
        _ic_assert_equal count, payloads.size,
          "Expected #{count} broadcast(s) on #{stream.inspect}, but got #{payloads.size}"
      else
        _ic_assert !payloads.empty?,
          "Expected at least one broadcast on #{stream.inspect}, but there were none"
      end

      payloads
    end

    # Assert that no broadcasts were made to the given stream.
    #
    #   assert_no_broadcasts_on(chat) { Message.create!(chat: other_chat) }
    #
    def assert_no_broadcasts_on(*streamables, &block)
      payloads = capture_broadcasts_on(*streamables, &block)
      stream = InertiaCable::Streams::StreamName.stream_name_from(streamables)

      _ic_assert payloads.empty?,
        "Expected no broadcasts on #{stream.inspect}, but got #{payloads.size}"
    end

    # Capture all broadcasts to a stream within a block. Returns an array of payload hashes.
    #
    # Automatically performs enqueued BroadcastJobs inline so that both sync
    # and async broadcasts are captured.
    #
    #   payloads = capture_broadcasts_on(chat) { Message.create!(chat: chat) }
    #   payloads.first[:action] # => "create"
    #
    def capture_broadcasts_on(*streamables, &block)
      stream = InertiaCable::Streams::StreamName.stream_name_from(streamables)
      collected = []

      callback = ->(name, payload) {
        collected << payload if name == stream
      }

      InertiaCable.on_broadcast(&callback)

      if defined?(ActiveJob::Base) && ActiveJob::Base.queue_adapter.respond_to?(:enqueued_jobs)
        # Perform broadcast jobs inline to capture their broadcasts
        original_adapter = ActiveJob::Base.queue_adapter
        ActiveJob::Base.queue_adapter = :inline
        begin
          yield
        ensure
          ActiveJob::Base.queue_adapter = original_adapter
        end
      else
        yield
      end

      InertiaCable.off_broadcast(&callback)

      collected
    end

    private

    # Framework-agnostic assertion — works in both Minitest and RSpec
    def _ic_assert(condition, message = "Assertion failed")
      if respond_to?(:assert)
        assert(condition, message)
      elsif condition
        true
      else
        raise message
      end
    end

    def _ic_assert_equal(expected, actual, message = nil)
      if respond_to?(:assert_equal)
        assert_equal(expected, actual, message)
      elsif expected == actual
        true
      else
        raise message || "Expected #{expected.inspect}, got #{actual.inspect}"
      end
    end
  end
end
