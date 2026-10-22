class WecomCustomerService::RefreshPlatformSessionJob < ApplicationJob
  queue_as :low

  def perform(session_id, force: false)
    session = WecomCustomerService::PlatformSession.find_by(id: session_id)
    return unless session && (force || session.refreshable?)

    WecomCustomerService::PlatformSessionService.new(channel: session.channel, external_userid: session.external_userid).refresh
  end
end
