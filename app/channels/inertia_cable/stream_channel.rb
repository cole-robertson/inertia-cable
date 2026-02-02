module InertiaCable
  class StreamChannel < ActionCable::Channel::Base
    def subscribed
      verified_stream = InertiaCable.signed_stream_verifier.verified(params[:signed_stream_name])
      if verified_stream
        stream_from Array(verified_stream).join(":")
      else
        reject
      end
    end
  end
end
