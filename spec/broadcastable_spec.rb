require "spec_helper"

ActiveRecord::Schema.define do
  create_table :boards, force: true do |t|
    t.string :name
    t.timestamps
  end

  create_table :posts, force: true do |t|
    t.integer :board_id
    t.string :title
    t.boolean :published, default: false
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
  belongs_to :board, foreign_key: :board_id
  broadcasts_refreshes
end

class SelectivePost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_refreshes_to :board, on: %i[create destroy]
end

class ConditionalPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_refreshes_to :board, if: :published?

  def published?
    published
  end
end

class UnlessPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_refreshes_to :board, unless: -> { title == "draft" }
end

class LambdaStreamPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_refreshes_to ->(post) { [post.board, :posts] }
end

RSpec.describe InertiaCable::Broadcastable do
  let(:board) { Board.create!(name: "Test Board") }

  def enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  before(:each) { enqueued_jobs.clear }

  # ---------------------------------------------------------------------------
  # broadcasts_refreshes_to (basic)
  # ---------------------------------------------------------------------------
  describe ".broadcasts_refreshes_to" do
    it "enqueues a broadcast job on create" do
      expect { Post.create!(title: "Hello", board: board) }
        .to change { enqueued_jobs.size }.by(1)

      expect(enqueued_jobs.last["job_class"]).to eq("InertiaCable::BroadcastJob")
    end

    it "enqueues a broadcast job on update" do
      post = Post.create!(title: "Hello", board: board)
      enqueued_jobs.clear

      expect { post.update!(title: "Updated") }
        .to change { enqueued_jobs.size }.by(1)
    end

    it "enqueues a broadcast job on destroy" do
      post = Post.create!(title: "Hello", board: board)
      enqueued_jobs.clear

      expect { post.destroy! }
        .to change { enqueued_jobs.size }.by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # broadcasts_refreshes (convention-based)
  # ---------------------------------------------------------------------------
  describe ".broadcasts_refreshes" do
    it "enqueues a broadcast job using model_name.plural" do
      expect { Article.create!(title: "News", board_id: board.id) }
        .to change { enqueued_jobs.size }.by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # on: option (selective events)
  # ---------------------------------------------------------------------------
  describe "on: option" do
    it "broadcasts on specified events only" do
      post = SelectivePost.create!(title: "Hello", board: board)
      expect(enqueued_jobs.size).to eq(1) # create fires

      enqueued_jobs.clear
      post.update!(title: "Updated")
      expect(enqueued_jobs.size).to eq(0) # update does NOT fire

      post.destroy!
      expect(enqueued_jobs.size).to eq(1) # destroy fires
    end
  end

  # ---------------------------------------------------------------------------
  # if: option (conditional)
  # ---------------------------------------------------------------------------
  describe "if: option" do
    it "broadcasts when condition is true" do
      ConditionalPost.create!(title: "Public", board: board, published: true)
      expect(enqueued_jobs.size).to eq(1)
    end

    it "does not broadcast when condition is false" do
      ConditionalPost.create!(title: "Private", board: board, published: false)
      expect(enqueued_jobs.size).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # unless: option
  # ---------------------------------------------------------------------------
  describe "unless: option" do
    it "broadcasts when unless condition is false" do
      UnlessPost.create!(title: "real", board: board)
      expect(enqueued_jobs.size).to eq(1)
    end

    it "does not broadcast when unless condition is true" do
      UnlessPost.create!(title: "draft", board: board)
      expect(enqueued_jobs.size).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Lambda stream resolution
  # ---------------------------------------------------------------------------
  describe "lambda stream" do
    it "resolves stream from lambda" do
      expect { LambdaStreamPost.create!(title: "Hello", board: board) }
        .to change { enqueued_jobs.size }.by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Payload format
  # ---------------------------------------------------------------------------
  describe "payload" do
    it "includes correct fields on create" do
      post = Post.create!(title: "Hello", board: board)
      job_args = enqueued_jobs.last["arguments"]
      payload = job_args.last

      expect(payload["type"]).to eq("refresh")
      expect(payload["model"]).to eq("Post")
      expect(payload["id"]).to eq(post.id)
      expect(payload["action"]).to eq("create")
      expect(payload["timestamp"]).to be_a(String)
    end

    it "reports action as update on update" do
      post = Post.create!(title: "Hello", board: board)
      enqueued_jobs.clear
      post.update!(title: "Changed")

      payload = enqueued_jobs.last["arguments"].last
      expect(payload["action"]).to eq("update")
    end

    it "reports action as destroy on destroy" do
      post = Post.create!(title: "Hello", board: board)
      enqueued_jobs.clear
      post.destroy!

      payload = enqueued_jobs.last["arguments"].last
      expect(payload["action"]).to eq("destroy")
    end
  end

  # ---------------------------------------------------------------------------
  # Instance methods — splat streamables
  # ---------------------------------------------------------------------------
  describe "instance methods" do
    describe "#broadcast_refresh_to" do
      it "broadcasts synchronously with splat args" do
        post = Post.create!(title: "Hello", board: board)

        expect(InertiaCable).to receive(:broadcast)
          .with([board, :posts], hash_including(type: "refresh"))

        post.broadcast_refresh_to(board, :posts)
      end

      it "broadcasts with a single argument" do
        post = Post.create!(title: "Hello", board: board)

        expect(InertiaCable).to receive(:broadcast)
          .with(["my_stream"], hash_including(type: "refresh"))

        post.broadcast_refresh_to("my_stream")
      end
    end

    describe "#broadcast_refresh_later_to" do
      it "enqueues a job with resolved stream name" do
        post = Post.create!(title: "Hello", board: board)
        enqueued_jobs.clear

        post.broadcast_refresh_later_to("custom_stream")

        expect(enqueued_jobs.size).to eq(1)
        expect(enqueued_jobs.last["job_class"]).to eq("InertiaCable::BroadcastJob")
      end
    end

    describe "#broadcast_refresh" do
      it "broadcasts to model_name.plural" do
        post = Post.create!(title: "Hello", board: board)

        expect(InertiaCable).to receive(:broadcast)
          .with(["posts"], hash_including(type: "refresh"))

        post.broadcast_refresh
      end
    end

    describe "#broadcast_refresh_later" do
      it "enqueues a job to model_name.plural" do
        post = Post.create!(title: "Hello", board: board)
        enqueued_jobs.clear

        post.broadcast_refresh_later

        expect(enqueued_jobs.size).to eq(1)
        args = enqueued_jobs.last["arguments"]
        expect(args.first).to eq("posts")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Stream resolution
  # ---------------------------------------------------------------------------
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
  end
end
