class WecomCustomerService::BotFallbackService
  KEY = 'wecom_bot_fallback'.freeze
  POLL_INTERVAL = 3.minutes
  PLATFORM_REPLY_STATES = [0, 1].freeze

  def self.platform_service_state(conversation)
    WecomCustomerService::PlatformSession.find_by(
      channel_id: conversation.inbox.channel.id, external_userid: conversation.contact_inbox.source_id
    )&.service_state
  end

  def self.platform_reply_allowed?(conversation)
    PLATFORM_REPLY_STATES.include?(platform_service_state(conversation))
  end

  def self.cancel_waiting(conversation)
    if [2, 3, 4].include?(platform_service_state(conversation))
      stop(conversation)
    else
      state = conversation.extensions.to_h.fetch(KEY, {})
      write(conversation, state.merge('status' => 'cancelled')) if state['status'] == 'waiting'
    end
  end

  def self.track(message, agent_bot)
    conversation = message.conversation
    return unless message.inbox.wecom_customer_service? && message.incoming? && !message.private?
    return if message.created_at < 5.minutes.ago

    # A conversation created by this job still carries the DB trigger synced display_id as an
    # unsaved change, and with_lock refuses records with unsaved changes.
    conversation.reload if conversation.changed?
    conversation.with_lock do
      channel = message.inbox.channel.reload
      return unless channel.bot_fallback_enabled? && current_bot_id(message.inbox) == agent_bot.id

      # Delivery never waits for a synchronous API lookup. Only a confirmed human/ended state stops
      # reception here; an unknown state (new session whose platform refresh has not landed yet)
      # still arms the deadline, which the job re-checks against the state at that time.
      if platform_service_state(conversation).in?([2, 3, 4])
        cancel_waiting(conversation)
        return
      end
      return unless conversation.pending?

      state = conversation.extensions.to_h.fetch(KEY, {})
      return if state['message_id'].to_i >= message.id
      # Pending explicitly returns reception to the bot, but replaying an old delivery must not restart it.
      return if state['stopped_at'].present? && message.created_at <= Time.iso8601(state['stopped_at'])

      token = SecureRandom.uuid
      deadline = Time.current + channel.bot_fallback_timeout_seconds.seconds
      write(conversation, { 'token' => token, 'bot_id' => agent_bot.id, 'message_id' => message.id,
                            'message_created_at' => message.created_at.iso8601(6),
                            'deadline' => deadline.iso8601(6), 'status' => 'waiting' })
      WecomCustomerService::BotFallbackJob.set(wait_until: deadline).perform_later(conversation.id, token, 'timeout')
      token
    end
  end

  def self.current_bot_id(inbox)
    AgentBotInbox.active.find_by(inbox_id: inbox.id)&.agent_bot_id
  end

  def self.write(conversation, state)
    conversation.update!(extensions: conversation.extensions.to_h.merge(KEY => state))
  end

  def self.reception_stopped?(conversation)
    conversation.reload.extensions.to_h.dig(KEY, 'stopped') == true
  end

  def self.stop(conversation)
    conversation.with_lock do
      state = conversation.extensions.to_h.fetch(KEY, {})
      status = state['status'] == 'waiting' ? 'handed_off' : state['status']
      write(conversation, state.merge('stopped' => true, 'stopped_at' => Time.current.iso8601(6), 'status' => status))
    end
  end

  # Call before saving an outgoing bot message. The marker survives asynchronous channel delivery.
  def self.stamp_reply(message)
    return unless message.inbox.wecom_customer_service? && message.outgoing? && message.sender_type == 'AgentBot'

    message.conversation.with_lock do
      state = message.conversation.extensions.to_h.fetch(KEY, {})
      context = { 'token' => message.extensions.to_h['wecom_bot_fallback_token'],
                  'reception_token' => state['token'], 'bot_id' => message.sender_id, 'message_id' => state['message_id'] }
      message.extensions = message.extensions.to_h.merge(KEY => context)
    end
  end

  def self.reply_allowed?(message)
    return false unless platform_reply_allowed?(message.conversation)
    return true unless message.sender_type == 'AgentBot'

    state = message.conversation.reload.extensions.to_h.fetch(KEY, {})
    return true unless message.inbox.channel.reload.bot_fallback_enabled? || state['stopped']
    return false unless current_bot_id(message.inbox) == message.sender_id
    return false if state['stopped']
    return true if state['token'].blank?

    context = message.extensions.to_h.fetch(KEY, {})
    return false unless context['reception_token'] == state['token'] && context['bot_id'] == state['bot_id']

    context['token'].blank? || context['token'] == state['token']
  end

  def self.reply_sent(message)
    conversation = message.conversation
    conversation.with_lock do
      state = conversation.extensions.to_h.fetch(KEY, {})
      return unless state['status'] == 'waiting'
      return unless reply_allowed?(message)
      return if message.sender_type == 'AgentBot' && message.extensions.to_h.dig(KEY, 'token') != state['token']

      incoming_created_at = state['message_created_at'].presence || conversation.messages.find(state.fetch('message_id')).created_at.iso8601(6)
      return if message.created_at < Time.iso8601(incoming_created_at)

      write(conversation, state.merge('status' => 'replied'))
    end
  end

  def self.delivery_failed(message, context)
    return false unless message.inbox.wecom_customer_service? && context.present?

    context = context.to_h.stringify_keys
    message.conversation.with_lock do
      state = message.conversation.extensions.to_h.fetch(KEY, {})
      if state['status'] == 'waiting' && !platform_reply_allowed?(message.conversation)
        cancel_waiting(message.conversation)
        return true
      end

      channel = message.inbox.channel.reload
      if channel.bot_fallback_enabled? && context['token'].present? && state['token'] == context['token'] &&
         state['bot_id'] == context['bot_id'] && current_bot_id(message.inbox) == context['bot_id'] && state['status'] == 'waiting'
        WecomCustomerService::BotFallbackJob.perform_later(message.conversation_id, context['token'], 'delivery_error')
      end
    end
    # Even stale/disabled tracked deliveries are consumed: never fall through to the legacy open! handler.
    true
  end

  def self.execute(conversation, token, reason, poll_token = nil)
    claimed = claim(conversation, token, reason, poll_token)
    return unless claimed

    result = if claimed['target'] == 'wecom_platform'
               WecomCustomerService::HandoffService.new(conversation: conversation).perform
             else
               { handoff_status: 'transferred' }
             end
    finish(conversation, token, claimed, result)
  rescue StandardError => e
    if claimed
      conversation.with_lock do
        state = conversation.extensions.to_h.fetch(KEY, {})
        if state['token'] == token && state['status'] == 'processing'
          write(conversation, state.merge('status' => 'failed', 'error' => e.message))
        end
      end
    end
    raise
  end

  def self.claim(conversation, token, reason, poll_token)
    conversation.with_lock do
      state = conversation.extensions.to_h.fetch(KEY, {})
      channel = conversation.inbox.channel.reload
      return unless state['token'] == token && eligible_trigger?(state, reason, poll_token)
      return unless channel.bot_fallback_enabled? && current_bot_id(conversation.inbox) == state['bot_id']
      return if conversation.resolved? || conversation.snoozed?
      return if state['status'] == 'waiting' && !conversation.pending?
      # Once handoff has started, state 2 is its queue: polls and failed/processing retries must continue.
      if state['status'] == 'waiting' && !platform_reply_allowed?(conversation)
        cancel_waiting(conversation)
        return
      end

      claimed = state.except('error', 'next_poll_at').merge(
        'stopped' => true, 'stopped_at' => Time.current.iso8601(6), 'status' => 'processing',
        'target' => state['target'] || channel.bot_fallback_target,
        'reason' => state['reason'] || reason, 'trigger_reason' => reason, 'poll_token' => poll_token
      )
      write(conversation, claimed)
      conversation.bot_handoff! if conversation.pending?
      claimed
    end
  end

  def self.eligible_trigger?(state, reason, poll_token)
    case state['status']
    when 'waiting'
      return true if reason == 'delivery_error'

      reason == 'timeout' && Time.current >= Time.iso8601(state.fetch('deadline'))
    when 'queued'
      reason == 'poll' && poll_token.present? && state['poll_token'] == poll_token &&
        Time.current >= Time.iso8601(state.fetch('next_poll_at'))
    when 'processing', 'failed'
      state['trigger_reason'] == reason && state['poll_token'] == poll_token
    else
      false
    end
  end

  def self.finish(conversation, token, claimed, result)
    conversation.with_lock do
      state = conversation.extensions.to_h.fetch(KEY, {})
      return unless state['token'] == token && state['status'] == 'processing'

      updates = { 'status' => result.fetch(:handoff_status) }
      updates['error'] = result[:error] if result[:error].present?
      if result[:handoff_status] == 'queued'
        updates.merge!('poll_token' => SecureRandom.uuid, 'next_poll_at' => (Time.current + POLL_INTERVAL).iso8601(6))
      end
      write(conversation, state.merge(updates))
      if updates['status'] == 'queued'
        WecomCustomerService::BotFallbackJob.set(wait_until: Time.iso8601(updates['next_poll_at'])).perform_later(
          conversation.id, token, 'poll', updates['poll_token']
        )
      end
      Conversations::ActivityMessageJob.perform_later(conversation, {
        account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity,
        content: I18n.t('conversations.activity.agent_bot.wecom_fallback',
                        reason: claimed['reason'], target: claimed['target'], status: result[:handoff_status])
      })
    end
  end
end
