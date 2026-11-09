class WecomCustomerService::ReceptionQueueJob < MutexApplicationJob
  queue_as :scheduled_jobs

  def perform
    with_lock('wecom_customer_service:reception_queue', 5.minutes) do
      WecomCustomerService::PlatformSession.where(service_state: 2).includes(channel: :inbox).find_each do |session|
        channel = session.channel
        next unless channel.human_reception_enabled? && channel.reception_queue_enabled? && channel.reception_queue_auto_assign?
        next if channel.inbox.out_of_office?

        contact_inbox = channel.inbox.contact_inboxes.find_by(source_id: session.external_userid)
        next unless contact_inbox

        conversation = contact_inbox.conversations.where.not(status: :resolved).order(id: :desc).first
        next unless conversation

        WecomCustomerService::HandoffService.new(conversation: conversation, queued_only: true).perform
      end
    end
  end
end
