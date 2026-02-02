module InertiaCable
  module ControllerHelpers
    # Returns a signed stream name to pass as an Inertia prop.
    #
    #   inertia_cable_stream(chat)
    #   inertia_cable_stream(chat, :messages)
    #
    def inertia_cable_stream(*streamables)
      InertiaCable::Streams::StreamName.signed_stream_name(*streamables)
    end
  end
end
