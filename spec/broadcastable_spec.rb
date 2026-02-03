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
  broadcasts_to :board
end

class Article < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts
end

class SelectivePost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_to :board, on: %i[create destroy]
end

class ConditionalPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_to :board, if: :published?

  def published?
    published
  end
end

class UnlessPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_to :board, unless: -> { title == "draft" }
end

class LambdaStreamPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_to ->(post) { [post.board, :posts] }
end

class LegacyAliasPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_refreshes_to :board
end

class LegacyAliasConventionPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_refreshes
end

class ExtraHashPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_to :board, extra: { priority: "high" }
end

class ExtraProcPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_to :board, extra: ->(post) { { title_length: post.title.length } }
end

class DebouncedPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_to :board, debounce: true
end

class CustomDelayDebouncedPost < ActiveRecord::Base
  self.table_name = "posts"
  belongs_to :board, foreign_key: :board_id
  broadcasts_to :board, debounce: 2.0
end

RSpec.describe InertiaCable::Broadcastable do
  let(:board) { Board.create!(name: "Test Board") }

  def enqueued_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs
  end

  before(:each) { enqueued_jobs.clear }

  # ---------------------------------------------------------------------------
  # broadcasts_to (basic)
  # ---------------------------------------------------------------------------
  describe ".broadcasts_to" do
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
  # broadcasts (convention-based)
  # ---------------------------------------------------------------------------
  describe ".broadcasts" do
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
  # Legacy aliases (broadcasts_refreshes_to / broadcasts_refreshes)
  # ---------------------------------------------------------------------------
  describe ".broadcasts_refreshes_to legacy alias" do
    it "works the same as broadcasts_to" do
      expect { LegacyAliasPost.create!(title: "Hello", board: board) }
        .to change { enqueued_jobs.size }.by(1)

      expect(enqueued_jobs.last["job_class"]).to eq("InertiaCable::BroadcastJob")
    end
  end

  describe ".broadcasts_refreshes legacy alias" do
    it "works the same as broadcasts" do
      expect { LegacyAliasConventionPost.create!(title: "Hello", board_id: board.id) }
        .to change { enqueued_jobs.size }.by(1)
    end
  end

  # ---------------------------------------------------------------------------
  # extra: option
  # ---------------------------------------------------------------------------
  describe "extra: option" do
    it "includes extra hash in payload" do
      ExtraHashPost.create!(title: "Hello", board: board)
      payload = enqueued_jobs.last["arguments"].last

      expect(payload["extra"]).to include("priority" => "high")
    end

    it "evaluates proc extra with record" do
      ExtraProcPost.create!(title: "Hello", board: board)
      payload = enqueued_jobs.last["arguments"].last

      expect(payload["extra"]).to include("title_length" => 5)
    end

    it "omits extra key when not provided" do
      Post.create!(title: "Hello", board: board)
      payload = enqueued_jobs.last["arguments"].last

      expect(payload).not_to have_key("extra")
    end
  end

  # ---------------------------------------------------------------------------
  # debounce: option (macro level)
  # ---------------------------------------------------------------------------
  describe "debounce: option" do
    it "calls Debounce.broadcast with default delay when debounce: true" do
      expect(InertiaCable::Debounce).to receive(:broadcast)
        .with(anything, hash_including(type: "refresh"), delay: nil)

      DebouncedPost.create!(title: "Hello", board: board)
    end

    it "calls Debounce.broadcast with custom delay" do
      expect(InertiaCable::Debounce).to receive(:broadcast)
        .with(anything, hash_including(type: "refresh"), delay: 2.0)

      CustomDelayDebouncedPost.create!(title: "Hello", board: board)
    end

    it "does not enqueue a job when using debounce" do
      allow(InertiaCable::Debounce).to receive(:broadcast)

      expect { DebouncedPost.create!(title: "Hello", board: board) }
        .not_to change { enqueued_jobs.size }
    end
  end

  # ---------------------------------------------------------------------------
  # Block support on instance methods
  # ---------------------------------------------------------------------------
  describe "block support" do
    describe "#broadcast_refresh_to with block" do
      it "broadcasts when block returns truthy" do
        post = Post.create!(title: "Hello", board: board, published: true)

        expect(InertiaCable).to receive(:broadcast)
          .with([board], hash_including(type: "refresh"))

        post.broadcast_refresh_to(board) { true }
      end

      it "skips broadcast when block returns falsy" do
        post = Post.create!(title: "Hello", board: board)

        expect(InertiaCable).not_to receive(:broadcast)

        post.broadcast_refresh_to(board) { false }
      end

      it "evaluates block in instance context" do
        post = Post.create!(title: "Hello", board: board, published: true)

        expect(InertiaCable).to receive(:broadcast)

        post.broadcast_refresh_to(board) { title == "Hello" }
      end
    end

    describe "#broadcast_refresh_later_to with block" do
      it "enqueues when block returns truthy" do
        post = Post.create!(title: "Hello", board: board)
        enqueued_jobs.clear

        post.broadcast_refresh_later_to(board) { true }

        expect(enqueued_jobs.size).to eq(1)
      end

      it "skips enqueue when block returns falsy" do
        post = Post.create!(title: "Hello", board: board)
        enqueued_jobs.clear

        post.broadcast_refresh_later_to(board) { false }

        expect(enqueued_jobs.size).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # extra: on instance methods
  # ---------------------------------------------------------------------------
  describe "extra: on instance methods" do
    it "includes extra in broadcast_refresh_to payload" do
      post = Post.create!(title: "Hello", board: board)

      expect(InertiaCable).to receive(:broadcast)
        .with([board], hash_including(type: "refresh", extra: { priority: "high" }))

      post.broadcast_refresh_to(board, extra: { priority: "high" })
    end

    it "includes extra in broadcast_refresh_later_to payload" do
      post = Post.create!(title: "Hello", board: board)
      enqueued_jobs.clear

      post.broadcast_refresh_later_to(board, extra: { priority: "high" })

      payload = enqueued_jobs.last["arguments"].last
      expect(payload["extra"]).to include("priority" => "high")
    end
  end

  # ---------------------------------------------------------------------------
  # broadcast_message_to / broadcast_message_later_to
  # ---------------------------------------------------------------------------
  describe "#broadcast_message_to" do
    it "broadcasts a message payload synchronously" do
      post = Post.create!(title: "Hello", board: board)

      expect(InertiaCable).to receive(:broadcast)
        .with([board], { type: "message", data: { progress: 50 } })

      post.broadcast_message_to(board, data: { progress: 50 })
    end

    it "broadcasts with splat args" do
      post = Post.create!(title: "Hello", board: board)

      expect(InertiaCable).to receive(:broadcast)
        .with([board, :posts], { type: "message", data: { step: 3 } })

      post.broadcast_message_to(board, :posts, data: { step: 3 })
    end

    it "skips broadcast when block returns falsy" do
      post = Post.create!(title: "Hello", board: board)

      expect(InertiaCable).not_to receive(:broadcast)

      post.broadcast_message_to(board, data: { progress: 50 }) { false }
    end

    it "broadcasts when block returns truthy" do
      post = Post.create!(title: "Hello", board: board)

      expect(InertiaCable).to receive(:broadcast)
        .with([board], { type: "message", data: { progress: 50 } })

      post.broadcast_message_to(board, data: { progress: 50 }) { true }
    end
  end

  describe "#broadcast_message_later_to" do
    it "enqueues a job with message payload" do
      post = Post.create!(title: "Hello", board: board)
      enqueued_jobs.clear

      post.broadcast_message_later_to("custom_stream", data: { progress: 75 })

      expect(enqueued_jobs.size).to eq(1)
      expect(enqueued_jobs.last["job_class"]).to eq("InertiaCable::BroadcastJob")

      payload = enqueued_jobs.last["arguments"].last
      expect(payload["type"]).to eq("message")
      expect(payload["data"]).to include("progress" => 75)
    end

    it "skips enqueue when block returns falsy" do
      post = Post.create!(title: "Hello", board: board)
      enqueued_jobs.clear

      post.broadcast_message_later_to(board, data: { progress: 50 }) { false }

      expect(enqueued_jobs.size).to eq(0)
    end
  end

  describe "suppression applies to messages" do
    it "suppresses broadcast_message_to" do
      post = Post.create!(title: "Hello", board: board)

      expect(InertiaCable).not_to receive(:broadcast)

      Post.suppressing_broadcasts do
        post.broadcast_message_to(board, data: { progress: 50 })
      end
    end

    it "suppresses broadcast_message_later_to" do
      post = Post.create!(title: "Hello", board: board)
      enqueued_jobs.clear

      Post.suppressing_broadcasts do
        post.broadcast_message_later_to(board, data: { progress: 50 })
      end

      expect(enqueued_jobs.size).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # InertiaCable.broadcast_message_to (class-level, no model instance)
  # ---------------------------------------------------------------------------
  describe "InertiaCable.broadcast_message_to" do
    it "broadcasts a message to a string stream" do
      expect(InertiaCable).to receive(:broadcast)
        .with(["dashboard"], { type: "message", data: { alert: "done" } })

      InertiaCable.broadcast_message_to("dashboard", data: { alert: "done" })
    end

    it "broadcasts a message with splat streamables" do
      expect(InertiaCable).to receive(:broadcast)
        .with([board, :notifications], { type: "message", data: { count: 5 } })

      InertiaCable.broadcast_message_to(board, :notifications, data: { count: 5 })
    end

    it "respects global suppression" do
      expect(ActionCable.server).not_to receive(:broadcast)

      InertiaCable.suppressing_broadcasts do
        InertiaCable.broadcast_message_to("dashboard", data: { alert: "done" })
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
