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
        assert_equal count, payloads.size,
          "Expected #{count} broadcast(s) on #{stream.inspect}, but got #{payloads.size}"
      else
        assert_not payloads.empty?,
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

      assert payloads.empty?,
        "Expected no broadcasts on #{stream.inspect}, but got #{payloads.size}"
    end

    # Capture all broadcasts to a stream within a block. Returns an array of payload hashes.
    #
    #   payloads = capture_broadcasts_on(chat) { Message.create!(chat: chat) }
    #   payloads.first[:action] # => :create
    #
    def capture_broadcasts_on(*streamables, &block)
      stream = InertiaCable::Streams::StreamName.stream_name_from(streamables)
      collected = []

      callback = ->(name, payload) {
        collected << payload if name == stream
      }

      InertiaCable.on_broadcast(&callback)
      yield
      InertiaCable.off_broadcast(&callback)

      collected
    end
  end
end
