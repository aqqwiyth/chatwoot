class WecomCustomerService::HandoffService
  ACTIVE_SERVICER_STATUS = 0
  QUEUED_SERVICE_STATE = 2
  HUMAN_SERVICE_STATE = 3
  SERVICER_POLL_INTERVAL = 3.minutes

  def initialize(message:)
    @message = message
    @conversation = message.conversation
    @channel = @conversation.inbox.channel
  end

  def perform
    ensure_supported_channel!
    external_userid = @conversation.contact_inbox.source_id
    api_client = WecomCustomerService::ApiClient.new(channel: @channel)

    send_pending_event_response(api_client)
    transition_conversation_to_human
    state = api_client.get_service_state(external_userid: external_userid)
    result = transfer_if_needed(api_client, external_userid, state)
    status = result.delete(:handoff_status) || 'transferred'
    update_handoff(status: status, **result)
    send_event_response(api_client, result)
    result.merge(handoff_status: status)
  end

  private

  def ensure_supported_channel!
    return if @channel.is_a?(Channel::WecomCustomerService)

    raise ArgumentError, 'WeCom handoff requires a WeCom customer service channel'
  end

  def transition_conversation_to_human
    @conversation.with_lock do
      return if @conversation.assignee_agent_bot_id.blank?

      @conversation.bot_handoff!
    end
  end

  def transfer_if_needed(api_client, external_userid, state)
    current_state = state.fetch('service_state').to_i
    return state_result(state, current_state) if current_state == HUMAN_SERVICE_STATE
    return failed_state_result(state) if current_state == 4

    servicer_userid = active_servicer_userid(api_client.list_servicers)
    return state_result(state, QUEUED_SERVICE_STATE) if servicer_userid.blank? && current_state == QUEUED_SERVICE_STATE

    target_state = servicer_userid.present? ? HUMAN_SERVICE_STATE : QUEUED_SERVICE_STATE
    response = transfer_service_state(
      api_client,
      external_userid,
      target_state,
      servicer_userid
    )

    state_result(state, target_state, servicer_userid: servicer_userid, msg_code: response['msg_code'])
  end

  def active_servicer_userid(payload)
    Array(payload['servicer_list']).filter_map do |servicer|
      next unless servicer['status'].to_i == ACTIVE_SERVICER_STATUS

      servicer['userid'].presence
    end.first
  end

  def transfer_service_state(api_client, external_userid, service_state, servicer_userid)
    api_client.transfer_service_state(
      external_userid: external_userid,
      service_state: service_state,
      servicer_userid: servicer_userid
    )
  rescue WecomCustomerService::ApiError => e
    raise unless e.servicer_offline? && service_state == HUMAN_SERVICE_STATE

    refreshed_servicer_userid = active_servicer_userid(api_client.list_servicers)
    raise if refreshed_servicer_userid.blank?

    api_client.transfer_service_state(
      external_userid: external_userid,
      service_state: service_state,
      servicer_userid: refreshed_servicer_userid
    )
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
    handoff = @message.extensions.to_h.deep_stringify_keys.fetch('handoff', {})
    return if handoff['event_response_sent'] == true || handoff['msg_code'].blank?

    send_event_response(api_client, msg_code: handoff['msg_code'])
  end

  def send_event_response(api_client, result)
    msg_code = result[:msg_code] || result['msg_code']
    return if msg_code.blank?

    handoff = @message.extensions.to_h.deep_stringify_keys.fetch('handoff', {})
    return if handoff['event_response_sent'] == true || handoff['event_response_error'].present?

    content = handoff['event_content'].presence || @channel.try(:session_assigned_message).presence
    return if content.blank?

    api_client.send_event_response(code: msg_code, content: content, msgid: event_response_message_id)
    update_handoff_event_response_sent
  rescue StandardError => e
    Rails.logger.warn "WeCom handoff event response failed for message=#{@message.id}: #{e.class}: #{e.message}"
    extensions = @message.extensions.to_h.deep_stringify_keys
    handoff = extensions.fetch('handoff', {}).merge('event_response_error' => e.message)
    @message.update!(extensions: extensions.merge('handoff' => handoff), external_error: e.message)
  end

  def update_handoff_event_response_sent
    extensions = @message.extensions.to_h.deep_stringify_keys
    handoff = extensions.fetch('handoff', {})
    @message.update!(extensions: extensions.merge('handoff' => handoff.merge('event_response_sent' => true)))
  end

  def event_response_message_id
    "cw_#{Digest::SHA256.hexdigest(@message.id.to_s)[0, 24]}"
  end

  def update_handoff(status:, service_state:, servicer_userid: nil, msg_code: nil, error: nil)
    extensions = @message.extensions.to_h.deep_stringify_keys
    handoff = extensions.fetch('handoff', {})
    updates = {
      'status' => status,
      'service_state' => service_state,
      'servicer_userid' => servicer_userid,
      'msg_code' => msg_code
    }.compact
    handoff.delete('error') if error.blank?
    updates['error'] = error if error.present?
    extensions['handoff'] = handoff.merge(updates)
    attributes = { extensions: extensions }
    if error.present?
      content_attributes = @message.content_attributes.to_h.deep_stringify_keys
      attributes[:content_attributes] = content_attributes.merge('external_error' => error)
    end
    @message.update!(attributes)
  end
end
