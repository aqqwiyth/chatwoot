class WecomCustomerService::AutoCloseJob < MutexApplicationJob
  queue_as :high
  retry_on StandardError, wait: 10.seconds, attempts: 3
  retry_on_lock_conflict wait: 2.seconds, attempts: 20
  discard_on ActiveRecord::RecordNotFound

  def perform(message_id, replied_at)
    message = Message.find(message_id)
    with_lock("wecom_customer_service:#{message.inbox.channel_id}", 5.minutes) do
      WecomCustomerService::AutoCloseService.execute(message, replied_at)
    end
  end
end
