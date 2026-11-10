class WecomCustomerService::HandoffService
  ACTIVE_SERVICER_STATUS = 0
  QUEUED_SERVICE_STATE = 2
  HUMAN_SERVICE_STATE = 3

  def self.servicer_cursors
    @servicer_cursors ||= Hash.new(0)
  end

  def initialize(message: nil, conversation: nil, queued_only: false)
    @message = message
    @queued_only = queued_only
    @conversation = conversation || message.conversation
    @channel = @conversation.inbox.channel
  end

  def perform
    raise ArgumentError, 'WeCom handoff requires a WeCom customer service channel' unless @channel.is_a?(Channel::WecomCustomerService)

    @channel.with_lock { perform_handoff }
  end

  private

  def perform_handoff
    unless @channel.human_reception_enabled?
      update_handoff(status: 'disabled')
      return { handoff_status: 'disabled' }
    end

    external_userid = @conversation.contact_inbox.source_id
    api_client = WecomCustomerService::ApiClient.new(channel: @channel)

    send_pending_event_response(api_client)
    state = api_client.get_service_state(external_userid: external_userid)
    if @queued_only && state.fetch('service_state').to_i != QUEUED_SERVICE_STATE
      WecomCustomerService::PlatformSessionService.new(channel: @channel, external_userid: external_userid).write(
        service_state: state.fetch('service_state'), servicer_userid: state['servicer_userid'], source: 'queue_poll'
      )
      return { handoff_status: 'not_queued' }
    end

    handoff_started_at = Time.current
    result = transfer_if_needed(api_client, external_userid, state)
    transition_conversation_to_human if %w[queued transferred].include?(result[:handoff_status])
    session = WecomCustomerService::PlatformSessionService.new(channel: @channel, external_userid: external_userid).write(
      service_state: result.fetch(:service_state), servicer_userid: result[:servicer_userid], source: 'handoff'
    )
    status = result.delete(:handoff_status) || 'transferred'
    if %w[queued transferred].include?(status) && state.fetch('service_state').to_i != result[:service_state]
      WecomCustomerService::AutoCloseService.clear_before(session, handoff_started_at)
    elsif status == 'unavailable'
      WecomCustomerService::AutoCloseService.clear_before(session, handoff_started_at, ai_only: true)
    end
    update_handoff(status: status, **result)
    send_event_response(api_client, result)
    send_unavailable_response(api_client, external_userid, @conversation.inbox.out_of_office?) if status == 'unavailable'
    result.merge(handoff_status: status)
  end

  def transition_conversation_to_human
    WecomCustomerService::BotFallbackService.stop(@conversation)
    @conversation.with_lock do
      @conversation.bot_handoff! if @conversation.pending? || @conversation.assignee_agent_bot_id.present?
    end
  end

  def transfer_if_needed(api_client, external_userid, state)
    current_state = state.fetch('service_state').to_i
    return state_result(state, current_state) if current_state == HUMAN_SERVICE_STATE
    return failed_state_result(state) if current_state == 4

    outside_hours = @conversation.inbox.out_of_office?
    assignment = transfer_to_active_servicer(api_client, external_userid) unless outside_hours
    return state_result(state, HUMAN_SERVICE_STATE, **assignment) if assignment

    queue_or_decline(api_client, external_userid, state, outside_hours)
  end

  def queue_or_decline(api_client, external_userid, state, outside_hours)
    current_state = state.fetch('service_state').to_i
    return state_result(state, QUEUED_SERVICE_STATE) if current_state == QUEUED_SERVICE_STATE
    return state_result(state, current_state).merge(handoff_status: 'unavailable') unless @channel.reception_queue_enabled?

    response = api_client.transfer_service_state(external_userid: external_userid, service_state: QUEUED_SERVICE_STATE)
    state_result(state, QUEUED_SERVICE_STATE, msg_code: response['msg_code']).merge(
      response_content: outside_hours ? @channel.outside_reception_hours_message : @channel.reception_busy_message
    )
  end

  def transfer_to_active_servicer(api_client, external_userid)
    attempted = []
    while (userid = next_active_servicer_userid(api_client.list_servicers, excluded_userids: attempted))
      begin
        response = api_client.transfer_service_state(external_userid: external_userid, service_state: HUMAN_SERVICE_STATE,
                                                     servicer_userid: userid)
        return { servicer_userid: userid, msg_code: response['msg_code'] }
      rescue WecomCustomerService::ApiError => e
        raise unless e.servicer_offline?

        attempted << userid
      end
    end
    nil
  end

  def next_active_servicer_userid(payload, excluded_userids: [])
    active_counts = WecomCustomerService::PlatformSession.where(channel: @channel, service_state: HUMAN_SERVICE_STATE)
                                                         .group(:servicer_userid).count
    active_userids = payload.fetch('servicer_list').filter_map do |servicer|
      userid = servicer['userid'].presence
      next if userid.blank? || excluded_userids.include?(userid)
      next unless servicer.fetch('status') == ACTIVE_SERVICER_STATUS
      next if active_counts.fetch(userid, 0) >= @channel.max_concurrent_receptions

      userid
    end
    return if active_userids.empty?

    cursors = self.class.servicer_cursors
    index = cursors[@channel.id] % active_userids.size
    cursors[@channel.id] = index + 1
    active_userids[index]
  end

  def state_result(state, service_state, servicer_userid: nil, msg_code: nil)
    {
      service_state: service_state,
      servicer_userid: servicer_userid || state['servicer_userid'],
      msg_code: msg_code,
      handoff_status: service_state == QUEUED_SERVICE_STATE ? 'queued' : 'transferred'
    }.compact
  end

  def failed_state_result(state)
    {
      service_state: state['service_state'].to_i,
      servicer_userid: state['servicer_userid'],
      handoff_status: 'failed',
      error: 'WeCom customer service session has ended'
    }
  end

  def send_pending_event_response(api_client)
    return unless @message

    handoff = @message.extensions.to_h.deep_stringify_keys.fetch('handoff', {})
    return if handoff['event_response_sent'] == true || handoff['msg_code'].blank?

    send_event_response(api_client, msg_code: handoff['msg_code'])
  end

  def send_event_response(api_client, result)
    msg_code = result[:msg_code] || result['msg_code']
    return if msg_code.blank?

    handoff = @message&.extensions.to_h.deep_stringify_keys.fetch('handoff', {})
    return if handoff['event_response_sent'] == true || handoff['event_response_error'].present?

    content = event_response_content(result, handoff)
    return if content.blank?

    api_client.send_event_response(code: msg_code, content: content, msgid: event_response_message_id(msg_code))
    update_handoff_event_response_sent if @message
  rescue StandardError => e
    record_handoff_event_response_failure(e)
  end

  def event_response_content(result, handoff)
    result[:response_content].presence || handoff['response_content'].presence ||
      handoff['event_content'].presence || @channel.session_assigned_message.presence
  end

  def send_unavailable_response(api_client, external_userid, outside_hours)
    handoff = @message&.extensions.to_h.deep_stringify_keys.fetch('handoff', {})
    return if handoff['unavailable_response_sent'] == true

    content = outside_hours ? @channel.outside_reception_hours_message : @channel.reception_busy_message
    api_client.send_text(external_userid: external_userid, content: content,
                         msgid: event_response_message_id)
    return unless @message

    extensions = @message.extensions.to_h.deep_stringify_keys
    extensions['handoff'] = extensions.fetch('handoff', {}).merge('unavailable_response_sent' => true)
    @message.update!(extensions: extensions)
  end

  def record_handoff_event_response_failure(error)
    Rails.logger.warn "WeCom handoff event response failed for conversation=#{@conversation.id} message=#{@message&.id}: " \
                      "#{error.class}: #{error.message}"
    if @message
      extensions = @message.extensions.to_h.deep_stringify_keys
      handoff = extensions.fetch('handoff', {}).merge('event_response_error' => error.message)
      @message.update!(extensions: extensions.merge('handoff' => handoff), external_error: error.message)
    else
      @conversation.with_lock do
        extensions = @conversation.extensions.to_h
        fallback = extensions.fetch('wecom_bot_fallback', {}).merge('event_response_error' => error.message)
        @conversation.update!(extensions: extensions.merge('wecom_bot_fallback' => fallback))
      end
    end
  end

  def update_handoff_event_response_sent
    extensions = @message.extensions.to_h.deep_stringify_keys
    handoff = extensions.fetch('handoff', {})
    @message.update!(extensions: extensions.merge('handoff' => handoff.merge('event_response_sent' => true)))
  end

  def event_response_message_id(code = 'unavailable')
    identity = @message ? @message.id.to_s : "fallback:#{@conversation.id}:#{@conversation.extensions.dig('wecom_bot_fallback', 'token')}"
    "cw_#{Digest::SHA256.hexdigest("#{identity}:#{code}")[0, 24]}"
  end

  def update_handoff(status:, error: nil, **result)
    return unless @message

    extensions = @message.extensions.to_h.deep_stringify_keys
    handoff = extensions.fetch('handoff', {})
    if result[:msg_code].present? && result[:msg_code] != handoff['msg_code']
      handoff.except!('event_response_sent', 'event_response_error', 'response_content')
    end
    updates = result.compact.stringify_keys.merge('status' => status)
    handoff.delete('error')
    updates['error'] = error if error.present?
    extensions['handoff'] = handoff.merge(updates)
    attributes = { extensions: extensions }
    attributes[:content_attributes] = @message.content_attributes.to_h.deep_stringify_keys.merge('external_error' => error) if error.present?
    @message.update!(attributes)
  end
end
