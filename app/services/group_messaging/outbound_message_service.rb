module GroupMessaging
  class OutboundMessageService < Base::SendOnChannelService
    private

    def channel_class
      Channel::GroupMessaging
    end

    def perform_reply
      message.source_id = channel.adapter.send_message(message)
      message.save! if message.changed?
    end
  end
end
