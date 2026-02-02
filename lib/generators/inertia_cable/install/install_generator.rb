module InertiaCable
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install InertiaCable into your Rails application"

      def copy_cable_setup
        template "cable_setup.ts", "app/javascript/channels/inertia_cable.ts"
      end

      def show_instructions
        say ""
        say "InertiaCable installed!", :green
        say ""
        say "Next steps:"
        say "  1. Add the npm package to your frontend:"
        say "     npm install @inertia-cable/react @rails/actioncable"
        say ""
        say "  2. Ensure ActionCable is configured in config/cable.yml"
        say "     (use redis adapter for production)"
        say ""
        say "  3. Add broadcasts_refreshes_to to your models:"
        say "     class Message < ApplicationRecord"
        say "       belongs_to :chat"
        say "       broadcasts_refreshes_to :chat"
        say "     end"
        say ""
        say "  4. Pass cable_stream prop from your controller:"
        say "     render inertia: 'Chats/Show', props: {"
        say "       cable_stream: inertia_cable_stream(chat)"
        say "     }"
        say ""
        say "  5. Use the hook in your React component:"
        say "     useInertiaCable(cable_stream, { only: ['messages'] })"
        say ""
      end
    end
  end
end
