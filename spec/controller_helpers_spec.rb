require "spec_helper"

RSpec.describe InertiaCable::ControllerHelpers do
  let(:controller) { Class.new { include InertiaCable::ControllerHelpers }.new }

  describe "#inertia_cable_stream" do
    it "returns a signed stream name for a string" do
      signed = controller.inertia_cable_stream("posts")
      verified = InertiaCable.signed_stream_verifier.verified(signed)
      expect(verified).to eq("posts")
    end

    it "returns a signed stream name for an array" do
      signed = controller.inertia_cable_stream(["boards", "posts"])
      verified = InertiaCable.signed_stream_verifier.verified(signed)
      expect(verified).to eq("boards:posts")
    end

    it "returns a signed stream name for a GlobalID object" do
      obj = double("record", to_gid_param: "gid://app/Chat/1")
      signed = controller.inertia_cable_stream(obj)
      verified = InertiaCable.signed_stream_verifier.verified(signed)
      expect(verified).to eq("gid://app/Chat/1")
    end
  end
end
