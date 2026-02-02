require "spec_helper"

ActiveRecord::Schema.define do
  create_table :boards, force: true do |t|
    t.string :name
    t.timestamps
  end

  create_table :posts, force: true do |t|
    t.integer :board_id
    t.string :title
    t.timestamps
  end
end

class Board < ActiveRecord::Base
  has_many :posts
end

class Post < ActiveRecord::Base
  belongs_to :board
  broadcasts_refreshes_to :board
end

class Article < ActiveRecord::Base
  self.table_name = "posts"
  broadcasts_refreshes
end

RSpec.describe InertiaCable::Broadcastable do
  let(:board) { Board.create!(name: "Test Board") }

  def enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  before(:each) do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  describe ".broadcasts_refreshes_to" do
    it "enqueues a broadcast job on create" do
      expect { Post.create!(title: "Hello", board: board) }
        .to change { enqueued_jobs.size }.by(1)

      job = enqueued_jobs.last
      expect(job["job_class"]).to eq("InertiaCable::BroadcastJob")
    end

    it "enqueues a broadcast job on update" do
      post = Post.create!(title: "Hello", board: board)
      enqueued_jobs.clear

      expect { post.update!(title: "Updated") }
        .to change { enqueued_jobs.size }.by(1)

      job = enqueued_jobs.last
      expect(job["job_class"]).to eq("InertiaCable::BroadcastJob")
    end

    it "broadcasts synchronously on destroy" do
      post = Post.create!(title: "Hello", board: board)

      expect(InertiaCable).to receive(:broadcast).with(anything, hash_including(type: "refresh", action: :commit))
      post.destroy!
    end
  end

  describe ".broadcasts_refreshes" do
    it "enqueues a broadcast job using model_name.plural" do
      expect { Article.create!(title: "News", board_id: board.id) }
        .to change { enqueued_jobs.size }.by(1)

      job = enqueued_jobs.last
      expect(job["job_class"]).to eq("InertiaCable::BroadcastJob")
    end
  end

  describe "#broadcast_refresh_to" do
    it "sends correct payload format" do
      post = Post.create!(title: "Hello", board: board)

      expect(InertiaCable).to receive(:broadcast) do |_stream, payload|
        expect(payload[:type]).to eq("refresh")
        expect(payload[:model]).to eq("Post")
        expect(payload[:id]).to eq(post.id)
        expect(payload[:action]).to eq(:commit)
        expect(payload[:timestamp]).to be_a(String)
      end

      post.broadcast_refresh_to("test")
    end
  end

  describe "stream resolution" do
    it "resolves symbol streams by calling the method" do
      post = Post.create!(title: "Hello", board: board)

      expect(InertiaCable).to receive(:broadcast).with(anything, hash_including(type: "refresh"))
      post.broadcast_refresh_to(:board)
    end

    it "resolves proc streams by calling with self" do
      post = Post.create!(title: "Hello", board: board)
      stream_proc = ->(p) { "custom:#{p.title}" }

      expect(InertiaCable).to receive(:broadcast).with(anything, hash_including(type: "refresh"))
      post.broadcast_refresh_to(stream_proc)
    end

    it "passes string streams through directly" do
      post = Post.create!(title: "Hello", board: board)

      expect(InertiaCable).to receive(:broadcast).with(anything, hash_including(type: "refresh"))
      post.broadcast_refresh_to("my_stream")
    end
  end
end
