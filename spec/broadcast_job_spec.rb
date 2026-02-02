require "spec_helper"

RSpec.describe InertiaCable::BroadcastJob do
  describe "#perform" do
    it "broadcasts to the stream" do
      payload = { type: "refresh", model: "Post", id: 1, action: :commit, timestamp: Time.current.iso8601 }

      expect(InertiaCable).to receive(:broadcast).with("test_stream", payload)

      described_class.new.perform("test_stream", payload)
    end
  end
end
