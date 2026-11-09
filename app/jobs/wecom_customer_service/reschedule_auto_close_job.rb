class WecomCustomerService::RescheduleAutoCloseJob < ApplicationJob
  queue_as :low
  discard_on ActiveRecord::RecordNotFound

  def perform(channel_id)
    channel = Channel::WecomCustomerService.find(channel_id)
    return if channel.auto_close_after_minutes.zero?

    WecomCustomerService::PlatformSession.where(channel: channel).where.not(auto_close_reply_id: nil).find_each do |session|
      WecomCustomerService::AutoCloseJob.set(wait_until: session.auto_close_reply_at + channel.auto_close_after_minutes.minutes)
                                        .perform_later(session.auto_close_reply_id, session.auto_close_reply_at.iso8601(6))
    end
  end
end
