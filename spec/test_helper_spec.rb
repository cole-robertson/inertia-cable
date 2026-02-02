require "spec_helper"

# Minimal test class that includes the helper, using Minitest-style assertions
# adapted for RSpec
class TestHarness
  include InertiaCable::TestHelper

  # Minitest assertion shims for RSpec context
  def assert_not(value, msg = nil)
    raise msg || "Expected falsy, got #{value.inspect}" if value
  end

  def assert(value, msg = nil)
    raise msg || "Expected truthy, got #{value.inspect}" unless value
  end

  def assert_equal(expected, actual, msg = nil)
    raise msg || "Expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
  end

  def assert_not_empty(collection, msg = nil)
    raise msg || "Expected non-empty collection" if collection.empty?
  end
end

RSpec.describe InertiaCable::TestHelper do
  let(:harness) { TestHarness.new }
  let(:board) { Board.create!(name: "Test Board") }

  describe "#capture_broadcasts_on" do
    it "captures broadcasts to the given stream" do
      post = Post.create!(title: "Existing", board: board)
      payloads = harness.capture_broadcasts_on("my_stream") do
        post.broadcast_refresh_to("my_stream")
      end

      expect(payloads.size).to eq(1)
      expect(payloads.first[:type]).to eq("refresh")
      expect(payloads.first[:model]).to eq("Post")
    end

    it "captures nothing when broadcasting to a different stream" do
      post = Post.create!(title: "Existing", board: board)
      payloads = harness.capture_broadcasts_on("other_stream") do
        post.broadcast_refresh_to("my_stream")
      end

      expect(payloads).to be_empty
    end

    it "works with splat streamables" do
      post = Post.create!(title: "Existing", board: board)
      payloads = harness.capture_broadcasts_on("boards", "posts") do
        post.broadcast_refresh_to("boards", "posts")
      end

      expect(payloads.size).to eq(1)
    end

    it "captures multiple broadcasts" do
      post = Post.create!(title: "Existing", board: board)
      payloads = harness.capture_broadcasts_on("my_stream") do
        post.broadcast_refresh_to("my_stream")
        post.broadcast_refresh_to("my_stream")
      end

      expect(payloads.size).to eq(2)
    end
  end

  describe "#assert_broadcasts_on" do
    it "passes when broadcasts exist" do
      post = Post.create!(title: "Existing", board: board)
      expect {
        harness.assert_broadcasts_on("my_stream") do
          post.broadcast_refresh_to("my_stream")
        end
      }.not_to raise_error
    end

    it "fails when no broadcasts exist" do
      expect {
        harness.assert_broadcasts_on("my_stream") do
          # nothing
        end
      }.to raise_error(/Expected at least one broadcast/)
    end

    it "passes with exact count" do
      post = Post.create!(title: "Existing", board: board)
      expect {
        harness.assert_broadcasts_on("my_stream", count: 2) do
          post.broadcast_refresh_to("my_stream")
          post.broadcast_refresh_to("my_stream")
        end
      }.not_to raise_error
    end

    it "fails with wrong count" do
      post = Post.create!(title: "Existing", board: board)
      expect {
        harness.assert_broadcasts_on("my_stream", count: 3) do
          post.broadcast_refresh_to("my_stream")
        end
      }.to raise_error(/Expected 3 broadcast/)
    end
  end

  describe "#assert_no_broadcasts_on" do
    it "passes when no broadcasts exist" do
      expect {
        harness.assert_no_broadcasts_on("my_stream") do
          # nothing
        end
      }.not_to raise_error
    end

    it "fails when broadcasts exist" do
      post = Post.create!(title: "Existing", board: board)
      expect {
        harness.assert_no_broadcasts_on("my_stream") do
          post.broadcast_refresh_to("my_stream")
        end
      }.to raise_error(/Expected no broadcasts/)
    end
  end
end
