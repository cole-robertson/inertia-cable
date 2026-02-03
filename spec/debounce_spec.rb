require "spec_helper"

RSpec.describe InertiaCable::Debounce do
  let(:stream_name) { "test_stream" }
  let(:payload) { { type: "refresh", model: "Post", id: 1, action: "create", timestamp: Time.current.iso8601 } }

  before(:each) do
    Rails.cache.clear
  end

  describe ".broadcast" do
    it "broadcasts and writes cache key" do
      expect(ActionCable.server).to receive(:broadcast).with(stream_name, payload)

      InertiaCable::Debounce.broadcast(stream_name, payload)
    end

    it "skips broadcast when cache key exists" do
      Rails.cache.write("inertia_cable:debounce:#{stream_name}", true, expires_in: 1)

      expect(ActionCable.server).not_to receive(:broadcast)

      InertiaCable::Debounce.broadcast(stream_name, payload)
    end

    it "uses global debounce_delay by default" do
      InertiaCable.debounce_delay = 0.5

      expect(Rails.cache).to receive(:write)
        .with("inertia_cable:debounce:#{stream_name}", true, expires_in: 0.5)

      InertiaCable::Debounce.broadcast(stream_name, payload)
    end

    it "uses custom delay when provided" do
      expect(Rails.cache).to receive(:write)
        .with("inertia_cable:debounce:#{stream_name}", true, expires_in: 2.0)

      InertiaCable::Debounce.broadcast(stream_name, payload, delay: 2.0)
    end

    it "falls back to global delay when delay: nil" do
      InertiaCable.debounce_delay = 0.75

      expect(Rails.cache).to receive(:write)
        .with("inertia_cable:debounce:#{stream_name}", true, expires_in: 0.75)

      InertiaCable::Debounce.broadcast(stream_name, payload, delay: nil)
    end
  end
end
