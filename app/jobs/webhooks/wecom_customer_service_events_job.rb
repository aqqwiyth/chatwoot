# rubocop:disable Metrics/ClassLength
class Webhooks::WecomCustomerServiceEventsJob < MutexApplicationJob
  queue_as :default
  MAX_MESSAGE_AGE = 3.minutes
  SESSION_CHANGE_LABELS = {
    1 => '接入人工客服',
    2 => '转接会话',
    3 => '结束人工接待',
    4 => '重新接入会话'
  }.freeze
  SESSION_STATUS_CHANGE_EVENT = 'session_status_change'
  SESSION_ENDED_CHANGE_TYPE = 3

  retry_on StandardError, wait: 10.seconds, attempts: 3
  retry_on LockAcquisitionError, wait: 2.seconds, attempts: 20

  def perform(channel_id:, token:, open_kfid:)
    with_lock("wecom_customer_service:#{channel_id}", 5.minutes) do
      channel = Channel::WecomCustomerService.find(channel_id)
      return unless channel.open_kfid == open_kfid

      sync_messages(channel, token)
    end
  end

  private

  def sync_messages(channel, callback_token)
    cursor = channel.cursor.presence
    api_client = WecomCustomerService::ApiClient.new(channel: channel)

    loop do
      payload = api_client.sync_messages(cursor: cursor, callback_token: callback_token)

      Array(payload['msg_list']).each { |message| process_message(channel, message) }

      next_cursor = payload['next_cursor'].to_s.presence
      update_cursor(channel, next_cursor) if next_cursor.present? && next_cursor != cursor
      break unless more_messages?(payload['has_more'])
      raise 'WeCom sync_msg returned has_more without next_cursor' if next_cursor.blank?

      cursor = next_cursor
    end
  end

  def update_cursor(channel, cursor)
    channel.update!(cursor: cursor)
  end

  def more_messages?(value)
    value == true || value.to_s == '1'
  end

  def process_message(channel, message)
    WecomCustomerService::AutoCloseService.observe_customer_message(channel, message)
    WecomCustomerService::AutoCloseService.observe_transfer(channel, message)
    if message.fetch('send_time').to_i < MAX_MESSAGE_AGE.ago.to_i && !ended_session_event?(message) &&
       WecomCustomerService::SatisfactionInvitationService.rating_callback(message).blank?
      return
    end

    content = message_content(message)
    media_file = download_media(channel, message)
    stored_message = WecomCustomerService::InboundMessageService.new(
      channel: channel,
      message: message,
      content: content,
      media_file: media_file
    ).perform
    if message['origin'].to_i == 5 && message['msgtype'] != 'event' && message['servicer_userid'].present? && stored_message.present?
      WecomCustomerService::AutoCloseService.schedule(stored_message, stored_message.created_at)
    end
    send_fixed_event_response(channel, message, stored_message) if stored_message
    close_ended_session_conversation(stored_message, message)
    forward_unassociated_event_to_agent_bot(channel, message, content) if stored_message.blank? && message['msgtype'] == 'event'
  rescue StandardError => e
    Rails.logger.error(
      '[Webhooks::WecomCustomerServiceEventsJob] Message forwarding failed for ' \
      "msgid=#{message['msgid']}: #{e.class}: #{e.message}"
    )
    raise
  ensure
    media_file&.io&.close!
  end

  # change_type=3 means the WeCom session ended. The event is recorded and the configured ended
  # message is sent first, then the conversation holding it is resolved so that later messages from
  # the same customer start a new Chatwoot conversation.
  def close_ended_session_conversation(stored_message, message)
    return if stored_message.blank? || !ended_session_event?(message)

    conversation = stored_message.conversation
    conversation.update!(extensions: conversation.extensions.to_h.merge('wecom_session_ended' => true))
    conversation.resolved! unless conversation.resolved?
  end

  def ended_session_event?(message)
    message['msgtype'] == 'event' && message.dig('event', 'event_type') == SESSION_STATUS_CHANGE_EVENT &&
      message.dig('event', 'change_type').to_i == SESSION_ENDED_CHANGE_TYPE
  end

  def send_fixed_event_response(channel, message, stored_message)
    event = message['event'].to_h
    extensions = stored_message.extensions.to_h.deep_stringify_keys
    return if extensions.dig('wecom', 'event_response_sent') == true || extensions.dig('wecom', 'event_response_error').present?

    if event['event_type'] == SESSION_STATUS_CHANGE_EVENT && event['change_type'].to_i == SESSION_ENDED_CHANGE_TYPE
      if event['msg_code'].blank?
        Rails.logger.warn("WeCom satisfaction invitation missing event code for message=#{stored_message.id}")
        return
      end

      WecomCustomerService::SatisfactionInvitationService.new(channel: channel, conversation: stored_message.conversation)
                                                         .perform(code: event['msg_code'])
    else
      code, content = fixed_event_response(channel, event)
      return if code.blank? || content.blank?

      WecomCustomerService::ApiClient.new(channel: channel).send_event_response(
        code: code,
        content: content,
        msgid: event_response_message_id(stored_message.external_event_id)
      )
    end
    extensions['wecom'] = extensions.fetch('wecom', {}).merge('event_response_sent' => true)
    stored_message.update!(extensions: extensions)
  rescue StandardError => e
    record_event_response_failure(stored_message, e)
  end

  def record_event_response_failure(message, error)
    Rails.logger.warn "WeCom fixed event response failed for message=#{message.id}: #{error.class}: #{error.message}"
    extensions = message.extensions.to_h.deep_stringify_keys
    extensions['wecom'] = extensions.fetch('wecom', {}).merge('event_response_error' => error.message)
    message.update!(
      extensions: extensions,
      external_error: error.message,
      content: "#{message.content}\n#{error.message}"
    )
  end

  def fixed_event_response(channel, event)
    case event['event_type']
    when 'enter_session'
      [event['welcome_code'], channel.inbox.greeting_enabled? ? channel.inbox.greeting_message : nil]
    when SESSION_STATUS_CHANGE_EVENT
      content = channel.session_assigned_message if event['change_type'].to_i == 1
      [event['msg_code'], content]
    else
      [nil, nil]
    end
  end

  def event_response_message_id(external_event_id)
    "cw_#{Digest::SHA256.hexdigest(external_event_id.to_s)[0, 24]}"
  end

  def download_media(channel, message)
    return unless %w[image voice video file].include?(message['msgtype'])

    media_id = message.dig(message['msgtype'], 'media_id').presence
    return if media_id.blank?

    WecomCustomerService::ApiClient.new(channel: channel).download_media(media_id: media_id)
  end

  def forward_unassociated_event_to_agent_bot(channel, message, content)
    inbox = channel.inbox
    agent_bot = inbox.agent_bot if inbox.agent_bot_inbox&.active?
    return if agent_bot.blank? || agent_bot.outgoing_url.blank?

    AgentBots::WebhookJob.perform_later(
      agent_bot.outgoing_url,
      {
        event: 'wecom_sync_message',
        source: 'wecom_customer_service',
        origin: message['origin'].to_i,
        content: content,
        raw_message: message,
        platform_session: platform_session_payload(channel, message),
        inbox: inbox.webhook_data,
        account: inbox.account.webhook_data
      },
      :agent_bot_webhook,
      secret: agent_bot.secret,
      delivery_id: delivery_id(channel, message)
    )
  end

  def platform_session_payload(channel, message)
    external_userid = message['external_userid'].presence || message.dig('event', 'external_userid').presence
    return nil if external_userid.blank?

    WecomCustomerService::PlatformSessionService.new(channel: channel, external_userid: external_userid).payload
  end

  def delivery_id(channel, message)
    message_id = message['msgid'].presence || Digest::SHA256.hexdigest(message.to_json)[0, 24]
    Digest::SHA256.hexdigest("wecom:#{channel.id}:#{message_id}")
  end

  def message_content(message)
    satisfaction = WecomCustomerService::SatisfactionInvitationService.rating_callback(message)
    return "服务评价：#{satisfaction[:label]}" if satisfaction.present?

    return message.dig('text', 'content').to_s if message['msgtype'] == 'text'
    return message_content_for_type(message) unless message['msgtype'] == 'event'

    event_content(message['event'].to_h)
  end

  def event_content(event)
    event_type = event['event_type'].presence || 'unknown'
    change_type = event['change_type'].presence
    servicer_userid = event['new_servicer_userid'].presence || event['servicer_userid'].presence
    details = event.except('event_type').to_json
    change_label = SESSION_CHANGE_LABELS[change_type.to_i] if change_type
    summary = ["事件: #{event_type}", ("状态: #{change_label || change_type}" if change_type),
               ("客服坐席: #{servicer_userid}" if servicer_userid)].compact.join(' | ')
    [summary, details].join("\n")
  end

  def message_content_for_type(message)
    content = {
      'voice' => '[语音消息]',
      'image' => '[图片消息]',
      'video' => '[视频消息]',
      'file' => "[文件消息] #{message.dig('file', 'filename')}",
      'location' => "[位置消息] #{message.dig('location', 'name')}",
      'link' => "[链接消息] #{message.dig('link', 'title')} #{message.dig('link', 'url')}"
    }[message['msgtype']]
    return content if content

    "[#{message['msgtype']}] #{message.except('msgid', 'open_kfid', 'external_userid').to_json}"
  end
end
# rubocop:enable Metrics/ClassLength
