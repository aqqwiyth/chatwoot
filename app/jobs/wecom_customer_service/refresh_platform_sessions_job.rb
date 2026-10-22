class WecomCustomerService::RefreshPlatformSessionsJob < MutexApplicationJob
  queue_as :scheduled_jobs

  BATCH_SIZE = 100

  def perform
    with_lock('wecom_customer_service:refresh_platform_sessions', 5.minutes) do
      WecomCustomerService::PlatformSession.due.in_batches(of: BATCH_SIZE) do |batch|
        sessions = batch.includes(channel: :inbox).select(&:refreshable?)
        batch.update_all(next_refresh_at: Time.current + WecomCustomerService::PlatformSessionService::REFRESH_INTERVAL)
        sessions.each { |session| WecomCustomerService::RefreshPlatformSessionJob.perform_later(session.id) }
      end
    end
  end
end
