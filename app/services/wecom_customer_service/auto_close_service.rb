class WecomCustomerService::AutoCloseService
  def self.observe_customer_message(channel, raw_message)
    return unless raw_message['origin'].to_i == 3 && raw_message['msgtype'] != 'event'
    return if WecomCustomerService::SessionEndingService.rating_callback(raw_message).present?
    return if raw_message['external_userid'].blank?

    timestamp = Time.zone.at(raw_message.fetch('send_time').to_i)
    session = WecomCustomerService::PlatformSessionService.new(channel: channel, external_userid: raw_message['external_userid']).session
    session.with_lock do
      session.update!(last_customer_message_at: timestamp) if session.last_customer_message_at.nil? || session.last_customer_message_at < timestamp
    end
  end

  def self.observe_transfer(channel, raw_message)
    event = raw_message['event'].to_h
    return unless event['event_type'] == 'session_status_change' && [1, 2, 4].include?(event['change_type'].to_i)
    return if event['external_userid'].blank?

    session = WecomCustomerService::PlatformSessionService.new(channel: channel, external_userid: event['external_userid']).session
    clear_before(session, Time.zone.at(raw_message.fetch('send_time').to_i))
  end

  def self.clear_before(session, timestamp, ai_only: false)
    session.with_lock do
      return if session.auto_close_reply_at.blank? || session.auto_close_reply_at > timestamp
      return if ai_only && !WecomCustomerService::SessionScope.ai_reply?(Message.find(session.auto_close_reply_id))

      session.update!(auto_close_reply_id: nil, auto_close_reply_at: nil, auto_close_attempted_at: nil)
    end
  end

  # The inactivity timeout belongs to the entry type of the reply that armed it: assistant replies
  # follow the AI settings, replies of a servicer follow the handoff or direct-human settings.
  def self.timeout_minutes(channel, entry_scope)
    config_scope = WecomCustomerService::SessionScope.config_scope(entry_scope, WecomCustomerService::SessionScope::AUTO_TRIGGER)
    channel.end_config(config_scope).auto_close_after_minutes
  end

  def self.schedule(message, replied_at)
    channel = message.inbox.channel
    session = WecomCustomerService::PlatformSessionService.new(
      channel: channel, external_userid: message.conversation.contact_inbox.source_id
    ).session
    session.with_lock do
      return if session.auto_close_reply_at.present? && session.auto_close_reply_at >= replied_at

      session.update!(auto_close_reply_id: message.id, auto_close_reply_at: replied_at, auto_close_attempted_at: nil)
    end
    timeout = timeout_minutes(channel, WecomCustomerService::SessionScope.for_message(message))
    return if timeout.zero?

    WecomCustomerService::AutoCloseJob.set(wait_until: replied_at + timeout.minutes)
                                      .perform_later(message.id, replied_at.iso8601(6))
  end

  def self.execute(message, replied_at)
    conversation = message.conversation
    channel = conversation.inbox.channel.reload
    entry_scope = WecomCustomerService::SessionScope.for_message(message)
    timeout = timeout_minutes(channel, entry_scope)
    return if timeout.zero? || conversation.resolved? || message.reload.failed?

    replied_at = Time.iso8601(replied_at)
    session_service = WecomCustomerService::PlatformSessionService.new(channel: channel, external_userid: conversation.contact_inbox.source_id)
    session = session_service.session.reload
    return unless session.auto_close_reply_id == message.id && session.auto_close_reply_at == replied_at
    return if session.last_customer_message_at.present? && session.last_customer_message_at.to_i >= replied_at.to_i

    deadline = replied_at + timeout.minutes
    if deadline > Time.current
      WecomCustomerService::AutoCloseJob.set(wait_until: deadline).perform_later(message.id, replied_at.iso8601(6))
      return
    end

    client = WecomCustomerService::ApiClient.new(channel: channel)
    state = client.get_service_state(external_userid: conversation.contact_inbox.source_id)
    service_state = state.fetch('service_state').to_i
    ai_reply = WecomCustomerService::SessionScope.ai_reply?(message)
    return unless (service_state == 1 && ai_reply) || (service_state == 3 && !ai_reply) ||
                  (service_state == 4 && session.auto_close_attempted_at.present?)
    if service_state == 3 && state['servicer_userid'] != message.extensions.to_h.dig('wecom', 'servicer_userid')
      return
    end
    return if session.reload.last_customer_message_at.present? && session.last_customer_message_at.to_i >= replied_at.to_i
    return unless session.auto_close_reply_id == message.id && !conversation.reload.resolved?

    if [1, 3].include?(service_state)
      session.update!(auto_close_attempted_at: Time.current)
      response = client.transfer_service_state(external_userid: conversation.contact_inbox.source_id, service_state: 4)
      send_ending(channel, conversation, response['msg_code'], entry_scope: entry_scope, servicer_userid: state['servicer_userid'])
    end
    session_service.write(service_state: 4, source: 'auto_close')
    conversation.update!(extensions: conversation.extensions.to_h.merge('wecom_session_ended' => true, 'wecom_auto_close' => {
                           'reason' => 'customer_inactivity', 'timeout_minutes' => timeout,
                           'entry_scope' => entry_scope, 'last_reply_at' => replied_at.iso8601(6)
                         }))
    conversation.resolved!
  end

  def self.send_ending(channel, conversation, code, entry_scope:, servicer_userid: nil)
    WecomCustomerService::SessionEndingService.new(channel: channel, conversation: conversation)
                                               .perform(code: code, entry_scope: entry_scope,
                                                        trigger: WecomCustomerService::SessionScope::AUTO_TRIGGER,
                                                        servicer_userid: servicer_userid)
  rescue StandardError => e
    Rails.logger.warn("[WecomCustomerService::AutoCloseService] Ending message failed: #{e.class}: #{e.message}")
  end
end
