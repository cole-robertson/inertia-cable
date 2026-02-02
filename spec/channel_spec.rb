require "spec_helper"

RSpec.describe InertiaCable::StreamChannel do
  let(:signed_name) { InertiaCable::Streams::StreamName.signed_stream_name("test_stream") }

  describe "#subscribed" do
    it "verifies and streams from a valid signed stream name" do
      verified = InertiaCable.signed_stream_verifier.verified(signed_name)
      expect(verified).to eq("test_stream")
    end

    it "rejects invalid signed stream names" do
      verified = InertiaCable.signed_stream_verifier.verified("invalid_token")
      expect(verified).to be_nil
    end

    it "handles array stream names" do
      signed = InertiaCable::Streams::StreamName.signed_stream_name(["boards", "posts"])
      verified = InertiaCable.signed_stream_verifier.verified(signed)
      expect(verified).to eq("boards:posts")
    end
  end
end
