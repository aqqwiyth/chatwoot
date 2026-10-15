class WecomCustomerService::InboundMessageService
  def initialize(channel:, message:, content:, media_file: nil)
    @channel = channel
    @message = message.deep_stringify_keys
    @content = content
    @media_file = media_file
  end

  def perform
    existing_message || create_message
  end

  private

  def inbox
    @channel.inbox
  end

  def existing_message
    inbox.messages.find_by(external_event_id: external_event_id)
  end

  def create_message
    contact_inbox = ContactInboxWithContactBuilder.new(
      source_id: external_userid,
      inbox: inbox,
      contact_attributes: contact_attributes
    ).perform

    conversation = find_or_create_conversation(contact_inbox)
    message = conversation.messages.build(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :incoming,
      sender: contact_inbox.contact,
      content: @content,
      source_id: @message.fetch('msgid'),
      external_event_id: external_event_id,
      extensions: message_extensions,
      created_at: message_created_at
    )
    attach_media(message)
    message.save!
    message
  end

  def find_or_create_conversation(contact_inbox)
    conversation = if inbox.lock_to_single_conversation
                     contact_inbox.conversations.order(created_at: :desc).first
                   else
                     contact_inbox.conversations.where.not(status: :resolved).order(created_at: :desc).first
                   end
    return conversation if conversation

    contact_inbox.conversations.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact_inbox.contact_id,
      contact_inbox_id: contact_inbox.id
    )
  end

  def contact_attributes
    customer = fetch_customer

    {
      name: customer['nickname'].presence || external_userid,
      avatar_url: customer['avatar'].presence,
      identifier: "wecom:#{@channel.corp_id}:#{external_userid}",
      additional_attributes: {
        'wecom_external_userid' => external_userid,
        'wecom_open_kfid' => @channel.open_kfid
      }
    }
  end

  def fetch_customer
    @customer ||= begin
      payload = WecomCustomerService::ApiClient.new(channel: @channel).get_customer(external_userid: external_userid)
      Array(payload['customer_list']).find { |customer| customer['external_userid'] == external_userid } || {}
    end
  end

  def message_extensions
    {
      'provider' => 'wecom_customer_service',
      'wecom' => {
        'msgid' => @message['msgid'],
        'open_kfid' => @message['open_kfid'],
        'external_userid' => external_userid,
        'msgtype' => @message['msgtype'],
        'send_time' => @message['send_time']
      },
      'webhook_forwarded' => false
    }
  end

  def message_created_at
    timestamp = @message['send_time'].to_i
    return Time.current if timestamp.zero?

    Time.zone.at(timestamp)
  end

  def external_event_id
    @external_event_id ||= "wecom_customer_service:#{@channel.open_kfid}:#{@message.fetch('msgid')}"
  end

  def external_userid
    @external_userid ||= @message.fetch('external_userid')
  end

  def attach_media(message)
    return if @media_file.blank?

    message.attachments.new(
      account_id: inbox.account_id,
      file_type: media_file_type,
      file: {
        io: @media_file.io,
        filename: @media_file.filename,
        content_type: @media_file.content_type
      }
    )
  end

  def media_file_type
    {
      'image' => :image,
      'voice' => :audio,
      'video' => :video,
      'file' => :file
    }.fetch(@message['msgtype'], :file)
  end
end
