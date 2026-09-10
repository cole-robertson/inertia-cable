import { createInertiaApp, type ResolvedComponent } from "@inertiajs/react"
import createServer from "@inertiajs/react/server"
import { createElement } from "react"
import ReactDOMServer from "react-dom/server"

import PersistentLayout from "@/layouts/persistent-layout"

const appName = import.meta.env.VITE_APP_NAME ?? "React Starter Kit"

createServer((page) =>
  createInertiaApp({
    page,
    render: ReactDOMServer.renderToString,
    title: (title) => (title ? `${title} - ${appName}` : appName),
    resolve: (name) => {
      const pages = import.meta.glob<{ default: ResolvedComponent }>(
        "../pages/**/*.tsx",
        {
          eager: true,
        },
      )
      const page = pages[`../pages/${name}.tsx`]
      if (!page) {
        console.error(`Missing Inertia page component: '${name}.tsx'`)
      }

      // To use a default layout, import the Layout component
      // and use the following line.
      // see https://inertia-rails.dev/guide/pages#default-layouts
      //
      page.default.layout ??= [PersistentLayout]

      return page
    },

    defaults: {
      form: {
        forceIndicesArrayFormatInFormData: false,
      },
    },

    setup: ({ App, props }) => createElement(App, props),
  }),
)
