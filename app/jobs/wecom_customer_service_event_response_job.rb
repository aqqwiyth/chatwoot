class WecomCustomerServiceEventResponseJob < ApplicationJob
  queue_as :high

  def perform(message_id)
    message = Message.find(message_id)
    return unless response_message?(message)

    response = message.extensions.to_h.deep_stringify_keys.fetch('wecom_event_response')
    return Messages::StatusUpdateService.new(message, 'delivered').perform if response['sent'] == true
    return if message.failed?

    channel = message.inbox.channel
    WecomCustomerService::ApiClient.new(channel: channel).send_event_response(
      code: response.fetch('code'),
      content: message.content,
      msgid: response['msgid']
    )
    mark_sent(message)
  rescue StandardError => e
    raise if message.blank?

    Rails.logger.warn "WeCom event response failed for message=#{message.id}: #{e.class}: #{e.message}"
    Messages::StatusUpdateService.new(message, 'failed', e.message).perform
  end

  private

  def response_message?(message)
    message.private? && message.sender_type == 'AgentBot' &&
      message.extensions.to_h['agent_bot_action'] == 'wecom_event_response'
  end

  def mark_sent(message)
    extensions = message.extensions.to_h.deep_stringify_keys
    response = extensions.fetch('wecom_event_response')
    message.update!(
      extensions: extensions.merge('wecom_event_response' => response.merge('sent' => true)),
      status: 'delivered',
      external_error: nil
    )
  end
end
