class WecomCustomerServiceEventResponseJob < ApplicationJob
  queue_as :high

  retry_on StandardError, wait: 10.seconds, attempts: 3

  def perform(message_id)
    message = Message.find(message_id)
    return unless response_message?(message)

    response = message.extensions.to_h.deep_stringify_keys.fetch('wecom_event_response')
    return if response['sent'] == true

    channel = message.inbox.channel
    WecomCustomerService::ApiClient.new(channel: channel).send_event_response(
      code: response.fetch('code'),
      content: message.content,
      msgid: response['msgid']
    )
    mark_sent(message)
  end

  private

  def response_message?(message)
    message.private? && message.sender_type == 'AgentBot' &&
      message.extensions.to_h['agent_bot_action'] == 'wecom_event_response'
  end

  def mark_sent(message)
    extensions = message.extensions.to_h.deep_stringify_keys
    response = extensions.fetch('wecom_event_response')
    message.update!(extensions: extensions.merge('wecom_event_response' => response.merge('sent' => true)))
  end
end
