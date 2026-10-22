class AgentBotListener < BaseListener
  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    inbox = conversation.inbox
    event_name = __method__.to_s
    payload = conversation.webhook_data.merge(event: event_name).merge(platform_session_payload(conversation))
    agent_bots_for(inbox, conversation).each { |agent_bot| process_webhook_bot_event(agent_bot, payload) }
  end

  def conversation_opened(event)
    conversation = extract_conversation_and_account(event)[0]
    inbox = conversation.inbox
    event_name = __method__.to_s
    payload = conversation.webhook_data.merge(event: event_name).merge(platform_session_payload(conversation))
    agent_bots_for(inbox, conversation).each { |agent_bot| process_webhook_bot_event(agent_bot, payload) }
  end

  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)
    inbox = conversation.inbox
    event_name = __method__.to_s
    payload = conversation.webhook_data.merge(event: event_name, changed_attributes: changed_attributes).merge(platform_session_payload(conversation))
    agent_bots_for(inbox, conversation).each { |agent_bot| process_webhook_bot_event(agent_bot, payload) }
  end

  def conversation_updated(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)
    inbox = conversation.inbox
    event_name = __method__.to_s
    payload = conversation.webhook_data.merge(event: event_name, changed_attributes: changed_attributes).merge(platform_session_payload(conversation))
    agent_bots_for(inbox, conversation).each { |agent_bot| process_webhook_bot_event(agent_bot, payload) }
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox
    return unless message.webhook_sendable? || wecom_activity?(message)
    return if agent_bot_command?(message)

    method_name = __method__.to_s
    agent_bots_for(inbox, message.conversation).each { |agent_bot| process_message_event(method_name, agent_bot, message, event) }
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox
    return unless message.webhook_sendable? || wecom_activity?(message)
    return if agent_bot_command?(message)

    return if wecom_activity?(message)

    method_name = __method__.to_s
    agent_bots_for(inbox, message.conversation).each { |agent_bot| process_message_event(method_name, agent_bot, message, event) }
  end

  def webwidget_triggered(event)
    contact_inbox = event.data[:contact_inbox]
    inbox = contact_inbox.inbox
    event_name = __method__.to_s
    payload = contact_inbox.webhook_data.merge(event: event_name)
    payload[:event_info] = event.data[:event_info]
    agent_bots_for(inbox).each { |agent_bot| process_webhook_bot_event(agent_bot, payload) }
  end

  private

  def agent_bots_for(inbox, conversation = nil)
    bots = []
    bots << conversation.assignee_agent_bot if conversation&.assignee_agent_bot.present?
    inbox_bot = active_inbox_agent_bot(inbox)
    bots << inbox_bot if inbox_bot.present?
    bots.compact.uniq
  end

  def active_inbox_agent_bot(inbox)
    return unless inbox.agent_bot_inbox&.active?

    inbox.agent_bot
  end

  def process_message_event(method_name, agent_bot, message, _event)
    # Only webhook bots are supported
    payload = message.webhook_data.merge(event: wecom_activity?(message) ? 'wecom_sync_message' : method_name)
    wecom = message.extensions.to_h['wecom'].to_h
    if wecom['raw_message'].present?
      payload = payload.merge(
        source: 'wecom_customer_service',
        origin: wecom['origin'],
        content: message.content,
        raw_message: wecom['raw_message']
      )
    end
    payload.merge!(platform_session_payload(message.conversation))
    if method_name == 'message_created'
      token = WecomCustomerService::BotFallbackService.track(message, agent_bot)
      payload[:wecom_bot_fallback] = { token: token, bot_id: agent_bot.id } if token
    end
    process_webhook_bot_event(agent_bot, payload)
  end

  def wecom_activity?(message)
    message.inbox.wecom_customer_service? && message.activity? && message.extensions.to_h.dig('wecom', 'raw_message').present?
  end

  def platform_session_payload(conversation)
    return {} unless conversation.inbox.wecom_customer_service?

    service = WecomCustomerService::PlatformSessionService.new(
      channel: conversation.inbox.channel, external_userid: conversation.contact_inbox.source_id
    )
    { platform_session: service.payload }
  end

  def process_webhook_bot_event(agent_bot, payload)
    return if agent_bot.outgoing_url.blank?

    AgentBots::WebhookJob.perform_later(agent_bot.outgoing_url, payload, :agent_bot_webhook,
                                        secret: agent_bot.secret, delivery_id: webhook_delivery_id(payload))
  end

  def webhook_delivery_id(payload)
    raw_message = payload[:raw_message]
    return SecureRandom.uuid if raw_message.blank?

    message_id = raw_message['msgid'] || raw_message[:msgid] || raw_message.to_json
    Digest::SHA256.hexdigest("wecom:#{message_id}")
  end

  def agent_bot_command?(message)
    message.extensions.to_h['agent_bot_action'].present?
  end
end
