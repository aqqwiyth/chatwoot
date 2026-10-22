class WecomCustomerService::BotFallbackJob < MutexApplicationJob
  queue_as :high
  retry_on StandardError, wait: 10.seconds, attempts: 3
  retry_on_lock_conflict wait: 10.seconds, attempts: 5
  discard_on ActiveRecord::RecordNotFound

  def perform(conversation_id, token, reason, poll_token = nil)
    with_lock("wecom_customer_service:bot_fallback:#{conversation_id}", 5.minutes) do
      WecomCustomerService::BotFallbackService.execute(Conversation.find(conversation_id), token, reason, poll_token)
    end
  end
end
