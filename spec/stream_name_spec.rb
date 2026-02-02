require "spec_helper"

RSpec.describe InertiaCable::Streams::StreamName do
  describe ".stream_name_from" do
    it "converts a string to itself" do
      expect(described_class.stream_name_from("posts")).to eq("posts")
    end

    it "converts a symbol to a string" do
      expect(described_class.stream_name_from(:posts)).to eq("posts")
    end

    it "joins array elements with colons" do
      expect(described_class.stream_name_from(["boards", "posts"])).to eq("boards:posts")
    end

    it "uses to_gid_param for GlobalID-capable objects" do
      obj = double("record", to_gid_param: "gid://app/Chat/1")
      expect(described_class.stream_name_from(obj)).to eq("gid://app/Chat/1")
    end

    it "handles mixed arrays with GlobalID objects and strings" do
      obj = double("record", to_gid_param: "gid://app/Chat/1")
      expect(described_class.stream_name_from([obj, "messages"])).to eq("gid://app/Chat/1:messages")
    end
  end

  describe ".signed_stream_name" do
    it "generates a verifiable signed string" do
      signed = described_class.signed_stream_name("posts")
      verified = InertiaCable.signed_stream_verifier.verified(signed)
      expect(verified).to eq("posts")
    end

    it "generates different signatures for different streams" do
      signed1 = described_class.signed_stream_name("posts")
      signed2 = described_class.signed_stream_name("comments")
      expect(signed1).not_to eq(signed2)
    end
  end
end
