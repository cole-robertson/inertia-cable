module InertiaCable
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc "Install InertiaCable into your Rails application"

      def patch_inertia_entrypoint
        entrypoint = detect_entrypoint
        unless entrypoint
          say "Could not find Inertia entrypoint — you'll need to add InertiaCableProvider manually.", :yellow
          return
        end

        say "Patching #{entrypoint}...", :green

        # Add import after the createInertiaApp import
        if File.read(entrypoint).include?("@inertia-cable/react")
          say "  Import already present, skipping", :yellow
        else
          inject_into_file entrypoint, after: /^import \{ createInertiaApp \} from .+\n/ do
            "import { InertiaCableProvider } from '@inertia-cable/react'\n"
          end
        end

        content = File.read(entrypoint)

        if content.include?("InertiaCableProvider")
          say "  InertiaCableProvider already present, skipping", :yellow
          return
        end

        # Pattern 1: createElement style
        #   createRoot(el).render(createElement(App, props))
        if content.match?(/createRoot\(el\)\.render\(\s*createElement\(App,\s*props\)\s*\)/)
          gsub_file entrypoint,
            /createRoot\(el\)\.render\(\s*createElement\(App,\s*props\)\s*\)/,
            "createRoot(el).render(\n        createElement(InertiaCableProvider, null, createElement(App, props)),\n      )"
          say "  Wrapped render in InertiaCableProvider (createElement style)", :green

        # Pattern 2: JSX with StrictMode
        #   createRoot(el).render(<StrictMode><App {...props} /></StrictMode>)
        elsif content.match?(/createRoot\(el\)\.render\(\s*\n?\s*<StrictMode>\s*\n?\s*<App\s+\{\.\.\.props\}\s*\/>\s*\n?\s*<\/StrictMode>/)
          gsub_file entrypoint,
            /<StrictMode>\s*\n?\s*<App\s+\{\.\.\.props\}\s*\/>\s*\n?\s*<\/StrictMode>/,
            "<StrictMode>\n        <InertiaCableProvider>\n          <App {...props} />\n        </InertiaCableProvider>\n      </StrictMode>"
          say "  Wrapped render in InertiaCableProvider (JSX + StrictMode style)", :green

        # Pattern 3: JSX without StrictMode
        #   createRoot(el).render(<App {...props} />)
        elsif content.match?(/createRoot\(el\)\.render\(\s*\n?\s*<App\s+\{\.\.\.props\}\s*\/>/)
          gsub_file entrypoint,
            /<App\s+\{\.\.\.props\}\s*\/>/,
            "<InertiaCableProvider>\n          <App {...props} />\n        </InertiaCableProvider>"
          say "  Wrapped render in InertiaCableProvider (JSX style)", :green

        else
          say "  Could not detect render pattern — add InertiaCableProvider manually.", :yellow
          say "  See: https://github.com/cole-robertson/inertia_cable#inertiaCableProvider"
        end
      end

      def show_next_steps
        say ""
        say "InertiaCable installed!", :green
        say ""
        say "Next steps:"
        say ""
        say "  1. Install the npm package:"
        say "     npm install @inertia-cable/react @rails/actioncable"
        say ""
        say "  2. Add broadcasts to your models:"
        say "     class Message < ApplicationRecord"
        say "       belongs_to :chat"
        say "       broadcasts_to :chat"
        say "     end"
        say ""
        say "  3. Pass cable_stream prop from your controller:"
        say "     render inertia: 'Chats/Show', props: {"
        say "       cable_stream: inertia_cable_stream(chat)"
        say "     }"
        say ""
        say "  4. Use the hook in your React component:"
        say "     import { useInertiaCable } from '@inertia-cable/react'"
        say ""
        say "     const { connected } = useInertiaCable(cable_stream, { only: ['messages'] })"
        say ""
      end

      private

      def detect_entrypoint
        candidates = %w[
          app/frontend/entrypoints/inertia.ts
          app/frontend/entrypoints/inertia.tsx
          app/frontend/entrypoints/inertia.js
          app/frontend/entrypoints/inertia.jsx
          app/javascript/entrypoints/inertia.ts
          app/javascript/entrypoints/inertia.tsx
          app/javascript/entrypoints/inertia.js
          app/javascript/entrypoints/inertia.jsx
        ]
        candidates.find { |f| File.exist?(Rails.root.join(f)) }
      end
    end
  end
end
