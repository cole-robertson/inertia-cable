module InertiaCable
  module ControllerHelpers
    def inertia_cable_stream(streamable)
      InertiaCable::Streams::StreamName.signed_stream_name(streamable)
    end
  end
end
