class WecomCustomerServiceHandoffJob < ApplicationJob
  queue_as :high

  retry_on StandardError, wait: 10.seconds, attempts: 3

  def perform(message_id)
    message = Message.find(message_id)
    return unless handoff_message?(message)

    result = WecomCustomerService::HandoffService.new(message: message).perform
    return unless result[:handoff_status] == 'queued'

    self.class.set(wait: WecomCustomerService::HandoffService::SERVICER_POLL_INTERVAL).perform_later(message.id)
  rescue StandardError => e
    mark_failed(message, e)
    raise
  end

  private

  def handoff_message?(message)
    message.private? && message.sender_type == 'AgentBot' && message.extensions.to_h['agent_bot_action'] == 'handoff'
  end

  def mark_failed(message, error)
    return if message.blank?

    extensions = message.extensions.to_h.deep_stringify_keys
    handoff = extensions.fetch('handoff', {})
    extensions['handoff'] = handoff.merge(
      'status' => 'failed',
      'error' => error.message
    )
    content_attributes = message.content_attributes.to_h.deep_stringify_keys
    message.update!(
      extensions: extensions,
      content_attributes: content_attributes.merge('external_error' => error.message)
    )
    Rails.logger.error "WeCom customer service handoff failed for message=#{message.id}: #{error.class}: #{error.message}"
  end
end
