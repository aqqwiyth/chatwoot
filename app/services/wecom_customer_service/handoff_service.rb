class WecomCustomerService::HandoffService
  ACTIVE_SERVICER_STATUS = 0
  QUEUED_SERVICE_STATE = 2
  HUMAN_SERVICE_STATE = 3

  def initialize(message:)
    @message = message
    @conversation = message.conversation
    @channel = @conversation.inbox.channel
  end

  def perform
    ensure_supported_channel!
    external_userid = @conversation.contact_inbox.source_id
    api_client = WecomCustomerService::ApiClient.new(channel: @channel)

    transition_conversation_to_human
    state = api_client.get_service_state(external_userid: external_userid)
    result = transfer_if_needed(api_client, external_userid, state)
    status = result.delete(:handoff_status) || 'transferred'
    update_handoff(status: status, **result)
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
    return state_result(state, current_state) if [QUEUED_SERVICE_STATE, HUMAN_SERVICE_STATE].include?(current_state)
    return failed_state_result(state) if current_state == 4

    servicer_userid = active_servicer_userid(api_client.list_servicers)
    target_state = servicer_userid.present? ? HUMAN_SERVICE_STATE : QUEUED_SERVICE_STATE
    api_client.transfer_service_state(
      external_userid: external_userid,
      service_state: target_state,
      servicer_userid: servicer_userid
    )

    state_result(state, target_state, servicer_userid: servicer_userid)
  end

  def active_servicer_userid(payload)
    Array(payload['servicer_list']).filter_map do |servicer|
      next unless servicer['status'].to_i == ACTIVE_SERVICER_STATUS

      servicer['userid'].presence
    end.first
  end

  def state_result(state, service_state, servicer_userid: nil)
    {
      service_state: service_state,
      servicer_userid: servicer_userid || state['servicer_userid'],
      handoff_status: service_state == QUEUED_SERVICE_STATE ? 'queued' : 'transferred'
    }
  end

  def failed_state_result(state)
    {
      service_state: state['service_state'].to_i,
      servicer_userid: state['servicer_userid'],
      handoff_status: 'failed',
      error: 'WeCom customer service session has ended'
    }
  end

  def update_handoff(status:, service_state:, servicer_userid: nil, error: nil)
    extensions = @message.extensions.to_h.deep_stringify_keys
    handoff = extensions.fetch('handoff', {})
    extensions['handoff'] = handoff.merge(
      'status' => status,
      'service_state' => service_state,
      'servicer_userid' => servicer_userid,
      'error' => error
    ).compact
    attributes = { extensions: extensions }
    if error.present?
      content_attributes = @message.content_attributes.to_h.deep_stringify_keys
      attributes[:content_attributes] = content_attributes.merge('external_error' => error)
    end
    @message.update!(attributes)
  end
end
