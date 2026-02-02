module InertiaCable
  module Streams
    module StreamName
      extend self

      def signed_stream_name(streamable)
        InertiaCable.signed_stream_verifier.generate(stream_name_from(streamable))
      end

      def stream_name_from(streamable)
        if streamable.is_a?(Array)
          streamable.map { |s| stream_name_from(s) }.join(":")
        elsif streamable.respond_to?(:to_gid_param)
          streamable.to_gid_param
        else
          streamable.to_s
        end
      end
    end
  end
end
