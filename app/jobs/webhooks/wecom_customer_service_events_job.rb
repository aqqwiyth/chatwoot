class Webhooks::WecomCustomerServiceEventsJob < MutexApplicationJob
  CUSTOMER_MESSAGE_ORIGIN = 3
  SERVICER_MESSAGE_ORIGIN = 5
  SUPPORTED_MESSAGE_ORIGINS = [CUSTOMER_MESSAGE_ORIGIN, SERVICER_MESSAGE_ORIGIN].freeze

  queue_as :default

  retry_on StandardError, wait: 10.seconds, attempts: 3
  retry_on LockAcquisitionError, wait: 2.seconds, attempts: 20

  def perform(channel_id:, token:, open_kfid:)
    with_lock("wecom_customer_service:#{channel_id}", 5.minutes) do
      channel = Channel::WecomCustomerService.find(channel_id)
      return unless channel.open_kfid == open_kfid

      sync_messages(channel, token)
    end
  end

  private

  def sync_messages(channel, callback_token)
    cursor = channel.cursor.presence
    api_client = WecomCustomerService::ApiClient.new(channel: channel)

    loop do
      payload = api_client.sync_messages(cursor: cursor, callback_token: callback_token)

      Array(payload['msg_list']).each do |message|
        process_message(channel, message) if supported_message_origin?(message)
      end

      next_cursor = payload['next_cursor'].to_s.presence
      update_cursor(channel, next_cursor) if next_cursor.present? && next_cursor != cursor
      break unless more_messages?(payload['has_more'])
      raise 'WeCom sync_msg returned has_more without next_cursor' if next_cursor.blank?

      cursor = next_cursor
    end
  end

  def update_cursor(channel, cursor)
    channel.update!(cursor: cursor)
  end

  def more_messages?(value)
    value == true || value.to_s == '1'
  end

  def process_message(channel, message)
    content = message_content(message)
    media_file = download_media(channel, message)
    stored_message = WecomCustomerService::InboundMessageService.new(channel: channel, message: message, content: content,
                                                                      media_file: media_file).perform
    return unless customer_message?(message)
    return if stored_message.extensions.to_h['webhook_forwarded'] == true

    begin
      forward_message(channel, message, content, stored_message.sender)
    rescue StandardError => e
      Rails.logger.error(
        "[Webhooks::WecomCustomerServiceEventsJob] Webhook forwarding failed for " \
        "msgid=#{message['msgid']}: #{e.class}: #{e.message}"
      )
      return
    end

    stored_message.update!(extensions: stored_message.extensions.to_h.merge('webhook_forwarded' => true))
  ensure
    media_file&.io&.close!
  end

  def supported_message_origin?(message)
    SUPPORTED_MESSAGE_ORIGINS.include?(message['origin'].to_i)
  end

  def customer_message?(message)
    message['origin'].to_i == CUSTOMER_MESSAGE_ORIGIN
  end

  def download_media(channel, message)
    return unless %w[image voice video file].include?(message['msgtype'])

    media_id = message.dig(message['msgtype'], 'media_id').presence
    return if media_id.blank?

    WecomCustomerService::ApiClient.new(channel: channel).download_media(media_id: media_id)
  end

  def forward_message(channel, message, content, contact)
    media_id = message.dig(message['msgtype'], 'media_id')
    metadata = [
      "用户: #{message['external_userid']}",
      "客服账号: #{message['open_kfid']}",
      "消息 ID: #{message['msgid']}",
      ("媒体 ID: #{media_id}" if media_id.present?),
      ("头像: #{contact.avatar_url}" if contact&.avatar_url.present?)
    ].compact.join(' | ')
    text = "[企业微信客服] #{metadata}\n#{content}".truncate(2048, omission: '…')

    response = HTTParty.post(
      channel.webhook_url,
      headers: { 'Content-Type' => 'application/json' },
      body: { msgtype: 'text', text: { content: text } }.to_json,
      timeout: 10
    )
    raise "WeCom robot webhook returned HTTP #{response.code}" unless response.success?
  end

  def message_content(message)
    case message['msgtype']
    when 'text'
      message.dig('text', 'content').to_s
    when 'voice'
      '[语音消息]'
    when 'image'
      '[图片消息]'
    when 'video'
      '[视频消息]'
    when 'file'
      "[文件消息] #{message.dig('file', 'filename')}"
    when 'location'
      "[位置消息] #{message.dig('location', 'name')}"
    when 'link'
      "[链接消息] #{message.dig('link', 'title')} #{message.dig('link', 'url')}"
    else
      "[#{message['msgtype']}] #{message.except('msgid', 'open_kfid', 'external_userid').to_json}"
    end
  end
end
