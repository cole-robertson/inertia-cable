require "spec_helper"

RSpec.describe InertiaCable::Suppressor do
  describe ".suppressing" do
    it "suppresses broadcasts within the block" do
      expect(described_class.suppressed?).to be false

      described_class.suppressing do
        expect(described_class.suppressed?).to be true
      end

      expect(described_class.suppressed?).to be false
    end

    it "restores previous state after block" do
      described_class.suppressing do
        described_class.suppressing do
          expect(described_class.suppressed?).to be true
        end
        expect(described_class.suppressed?).to be true
      end
      expect(described_class.suppressed?).to be false
    end

    it "prevents broadcasts from being sent" do
      board = Board.create!(name: "Test")

      expect(InertiaCable::BroadcastJob).not_to receive(:perform_later)
      expect(InertiaCable).not_to receive(:broadcast)

      InertiaCable.suppressing_broadcasts do
        Post.create!(title: "Suppressed", board: board)
      end
    end
  end
end
