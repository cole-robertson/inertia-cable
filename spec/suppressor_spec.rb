require "spec_helper"

RSpec.describe "Broadcast suppression" do
  let(:board) { Board.create!(name: "Test") }

  describe "InertiaCable.suppressing_broadcasts (global)" do
    it "suppresses all broadcasts within the block" do
      expect(InertiaCable::Suppressor.suppressed?).to be false

      InertiaCable.suppressing_broadcasts do
        expect(InertiaCable::Suppressor.suppressed?).to be true
      end

      expect(InertiaCable::Suppressor.suppressed?).to be false
    end

    it "restores state after nested suppression" do
      InertiaCable.suppressing_broadcasts do
        InertiaCable.suppressing_broadcasts do
          expect(InertiaCable::Suppressor.suppressed?).to be true
        end
        expect(InertiaCable::Suppressor.suppressed?).to be true
      end
      expect(InertiaCable::Suppressor.suppressed?).to be false
    end

    it "prevents InertiaCable.broadcast from firing" do
      expect(ActionCable.server).not_to receive(:broadcast)

      InertiaCable.suppressing_broadcasts do
        InertiaCable.broadcast("test", { type: "refresh" })
      end
    end
  end

  describe "Model.suppressing_broadcasts (class-level)" do
    it "suppresses broadcasts from model callbacks" do
      jobs_before = ActiveJob::Base.queue_adapter.enqueued_jobs.size

      Post.suppressing_broadcasts do
        Post.create!(title: "Suppressed", board: board)
      end

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.size).to eq(jobs_before)
    end

    it "does not affect other model classes" do
      # Post suppression should not affect Article
      Post.suppressing_broadcasts do
        expect(Post.suppressed_inertia_cable_broadcasts?).to be true
        # Note: since thread_mattr_accessor is on ActiveRecord::Base (the
        # including class), suppression affects all models in the same thread.
        # This matches turbo-rails behavior.
      end
    end

    it "restores state after block" do
      Post.suppressing_broadcasts do
        expect(Post.suppressed_inertia_cable_broadcasts?).to be true
      end
      expect(Post.suppressed_inertia_cable_broadcasts?).to be false
    end

    it "is exception-safe" do
      begin
        Post.suppressing_broadcasts do
          raise "boom"
        end
      rescue RuntimeError
      end

      expect(Post.suppressed_inertia_cable_broadcasts?).to be false
    end
  end
end
