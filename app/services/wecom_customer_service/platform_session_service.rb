class WecomCustomerService::PlatformSessionService
  REFRESH_INTERVAL = 10.minutes
  SESSION_CHANGE_STATES = { 1 => 3, 2 => 2, 3 => 4, 4 => 3 }.freeze
  UNCHECKED_OBSERVATION = Object.new.freeze

  def initialize(channel:, external_userid:)
    @channel = channel
    @external_userid = external_userid
  end

  def session
    @session ||= WecomCustomerService::PlatformSession.find_by(channel: @channel, external_userid: @external_userid) ||
                 WecomCustomerService::PlatformSession.create_or_find_by!(channel: @channel, external_userid: @external_userid) do |record|
                   record.source = 'unknown'
                   record.next_refresh_at = Time.current
                 end
  rescue ActiveRecord::RecordInvalid => e
    raise unless e.record.errors.of_kind?(:external_userid, :taken)

    @session = WecomCustomerService::PlatformSession.find_by!(channel: @channel, external_userid: @external_userid)
  end

  def write(service_state:, servicer_userid: nil, source: 'handoff', observed_at: Time.current, expected_observed_at: UNCHECKED_OBSERVATION)
    session.with_lock do
      return session if expected_observed_at != UNCHECKED_OBSERVATION && session.observed_at != expected_observed_at
      return session if session.observed_at.present? && session.observed_at > observed_at

      session.update!(service_state: service_state, servicer_userid: servicer_userid, source: source,
                      observed_at: observed_at, next_refresh_at: Time.current + REFRESH_INTERVAL)
    end
    stop_bot_fallback if [2, 3, 4].include?(session.service_state)
    session
  end

  def refresh(source: 'api')
    expected_observed_at = session.reload.observed_at
    observed_at = Time.current
    state = fetch_service_state
    return session unless state

    write(service_state: state.fetch('service_state'), servicer_userid: state['servicer_userid'], source: source,
          observed_at: observed_at, expected_observed_at: expected_observed_at)
  end

  def observe_message(message)
    event = message['event'].to_h
    service_state = SESSION_CHANGE_STATES[event['change_type'].to_i] if event['event_type'] == 'session_status_change'
    if service_state
      timestamp = message['send_time'].to_i
      return write(service_state: service_state, servicer_userid: event['servicer_userid'], source: 'event',
                   observed_at: timestamp.positive? ? Time.zone.at(timestamp) : Time.current)
    end

    force_refresh = event['event_type'] == 'enter_session' || (session.service_state == 4 && message['origin'].to_i == 3)
    enqueue_refresh(force: force_refresh)
    session
  end

  def enqueue_refresh(force: false)
    session.with_lock do
      return session unless force || session.next_refresh_at <= Time.current

      session.update!(next_refresh_at: Time.current + REFRESH_INTERVAL)
    end
    WecomCustomerService::RefreshPlatformSessionJob.perform_later(session.id, force: true)
    session
  end

  def payload
    session.attributes.symbolize_keys.slice(:service_state, :servicer_userid, :source, :observed_at, :next_refresh_at)
      .merge(provider: 'wecom_customer_service', channel_id: @channel.id, open_kfid: @channel.open_kfid, external_userid: @external_userid,
             stale: session.observed_at.nil? || session.observed_at <= Time.current - REFRESH_INTERVAL)
  end

  private

  def fetch_service_state
    WecomCustomerService::ApiClient.new(channel: @channel).get_service_state(external_userid: @external_userid)
  rescue StandardError => e
    session.update!(next_refresh_at: Time.current + REFRESH_INTERVAL)
    Rails.logger.warn("[WecomCustomerService::PlatformSessionService] Refresh failed channel=#{@channel.id}: #{e.class}: #{e.message}")
    nil
  end

  def stop_bot_fallback
    contact_inbox = @channel.inbox.contact_inboxes.find_by(source_id: @external_userid)
    return unless contact_inbox

    contact_inbox.conversations.where.not(status: :resolved).find_each do |conversation|
      WecomCustomerService::BotFallbackService.stop(conversation)
    end
  end
end
