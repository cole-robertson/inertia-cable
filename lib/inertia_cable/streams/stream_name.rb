module InertiaCable
  module Streams
    module StreamName
      extend self

      def signed_stream_name(*streamables)
        InertiaCable.signed_stream_verifier.generate(stream_name_from(streamables))
      end

      def stream_name_from(streamables)
        streamables = Array(streamables).flatten
        streamables.compact_blank!
        streamables.map { |s| single_stream_name(s) }.join(":")
      end

      private

      def single_stream_name(streamable)
        if streamable.respond_to?(:to_gid_param)
          streamable.to_gid_param
        else
          streamable.to_param
        end
      end
    end
  end
end
