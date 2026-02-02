require "spec_helper"

RSpec.describe InertiaCable::StreamChannel do
  describe "stream verification" do
    it "verifies a valid signed stream name" do
      signed = InertiaCable::Streams::StreamName.signed_stream_name("test_stream")
      verified = InertiaCable.signed_stream_verifier.verified(signed)
      expect(verified).to eq("test_stream")
    end

    it "rejects an invalid signed stream name" do
      verified = InertiaCable.signed_stream_verifier.verified("tampered_token")
      expect(verified).to be_nil
    end

    it "verifies compound stream names" do
      signed = InertiaCable::Streams::StreamName.signed_stream_name("boards", "posts")
      verified = InertiaCable.signed_stream_verifier.verified(signed)
      expect(verified).to eq("boards:posts")
    end

    it "rejects empty string" do
      verified = InertiaCable.signed_stream_verifier.verified("")
      expect(verified).to be_nil
    end
  end
end
