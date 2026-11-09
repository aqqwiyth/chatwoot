class WecomCustomerService::InboundMessageService
  def initialize(channel:, message:, content:, media_file: nil)
    @channel = channel
    @message = message.deep_stringify_keys
    @content = content
    @media_file = media_file
  end

  def perform
    if external_userid.present? && satisfaction_callback.blank?
      WecomCustomerService::PlatformSessionService.new(channel: @channel, external_userid: external_userid).observe_message(@message)
    end
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
    return if external_userid.blank?

    contact_inbox = find_contact_inbox
    return if contact_inbox.blank?

    conversation = WecomCustomerService::ConversationResolver.new(
      inbox: inbox, contact_inbox: contact_inbox, ended_event: ended_session_event?,
      event_time: message_created_at, satisfaction: satisfaction_callback
    ).perform
    return if conversation.blank?

    message = build_message(conversation, contact_inbox)
    attach_media(message)
    message.save!
    message
  end

  def build_message(conversation, contact_inbox)
    conversation.messages.build(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: message_type,
      private: satisfaction_callback.present?,
      status: message_status,
      sender: message_sender(contact_inbox),
      content: @content,
      source_id: message_id,
      external_event_id: external_event_id,
      content_attributes: content_attributes,
      extensions: message_extensions,
      created_at: message_created_at
    )
  end

  def find_contact_inbox
    if ended_session_event? || satisfaction_callback.present?
      existing = inbox.contact_inboxes.find_by(source_id: external_userid)
      return existing if existing.present? || satisfaction_callback.present?
    end

    ContactInboxWithContactBuilder.new(
      source_id: external_userid,
      inbox: inbox,
      contact_attributes: contact_attributes
    ).perform
  end

  def ended_session_event?
    @message['msgtype'] == 'event' && @message.dig('event', 'event_type') == 'session_status_change' &&
      @message.dig('event', 'change_type').to_i == 3
  end

  def contact_attributes
    customer = customer_details

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

  def message_type
    return :activity if event_message?
    return :outgoing if satisfaction_callback.present?

    outgoing_service_message? ? :outgoing : :incoming
  end

  def message_status
    outgoing_service_message? ? :delivered : :sent
  end

  def message_sender(contact_inbox)
    return nil if event_message? || outgoing_service_message? || satisfaction_callback.present?

    contact_inbox.contact
  end

  def content_attributes
    outgoing_service_message? ? { 'external_echo' => true } : {}
  end

  def outgoing_service_message? = @message['origin'].to_i == 5

  def event_message? = @message['msgtype'] == 'event'

  def satisfaction_callback = @satisfaction_callback ||= WecomCustomerService::SatisfactionInvitationService.rating_callback(@message)

  def customer_details
    @customer_details ||= begin
      payload = WecomCustomerService::ApiClient.new(channel: @channel).get_customer(external_userid: external_userid)
      Array(payload['customer_list']).find { |customer| customer['external_userid'] == external_userid } || {}
    end
  end

  def message_extensions
    extensions = { 'provider' => 'wecom_customer_service', 'wecom' => wecom_message_extensions }
    extensions['wecom']['event_type'] = @message.dig('event', 'event_type') if @message['msgtype'] == 'event'
    extensions['wecom']['satisfaction'] = satisfaction_callback if satisfaction_callback.present?

    add_event_actor(extensions) if event_message?

    servicer_userid = @message['servicer_userid'].presence
    add_servicer_extensions(extensions, servicer_userid) if outgoing_service_message? && servicer_userid.present?
    extensions
  end

  def add_event_actor(extensions)
    event = @message['event'].to_h
    servicer_userid = event['servicer_userid'].presence
    display_name = servicer_userid.present? ? "客服坐席 #{servicer_userid}" : '企业微信客服系统'
    external_id = servicer_userid.presence || 'system'
    extensions['actor'] = {
      'display_name' => display_name,
      'external_id' => external_id,
      'identity_key' => "wecom:#{servicer_userid.presence || 'system'}"
    }
    extensions['wecom']['servicer_userid'] = servicer_userid if servicer_userid.present?
  end

  def wecom_message_extensions
    {
      'msgid' => @message['msgid'],
      'open_kfid' => @message['open_kfid'].presence || @message.dig('event', 'open_kfid') || @channel.open_kfid,
      'external_userid' => external_userid,
      'msgtype' => @message['msgtype'],
      'send_time' => @message['send_time'],
      'origin' => @message['origin'].to_i,
      'raw_message' => @message
    }
  end

  def add_servicer_extensions(extensions, servicer_userid)
    extensions['wecom']['servicer_userid'] = servicer_userid
    extensions['actor'] = {
      'display_name' => servicer_userid,
      'external_id' => servicer_userid,
      'identity_key' => "wecom:servicer:#{servicer_userid}"
    }
  end

  def message_created_at
    timestamp = @message['send_time'].to_i
    return Time.current if timestamp.zero?

    Time.zone.at(timestamp)
  end

  def external_event_id
    @external_event_id ||= "wecom_customer_service:#{@channel.open_kfid}:#{message_id}"
  end

  def message_id
    @message_id ||= @message['msgid'].presence || Digest::SHA256.hexdigest(@message.to_json)[0, 24]
  end

  def external_userid
    @external_userid ||= @message['external_userid'].presence || @message.dig('event', 'external_userid').presence
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
