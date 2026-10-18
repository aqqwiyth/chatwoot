class WecomCustomerService::SendOnChannelService < Base::SendOnChannelService
  SERVICE_STATE_LABELS = {
    0 => '未处理',
    1 => '机器人接待中',
    2 => '排队中',
    3 => '人工接待中',
    4 => '已结束/超过24小时'
  }.freeze

  private

  def channel_class
    Channel::WecomCustomerService
  end

  def perform_reply
    api_client = WecomCustomerService::ApiClient.new(channel: channel)
    external_userid = conversation.contact_inbox.source_id

    send_text(api_client, external_userid) if message.content.present?
    message.attachments.each do |attachment|
      send_attachment(api_client, external_userid, attachment)
    end
  rescue StandardError => e
    error_message = send_error_message(api_client, external_userid, e)
    Rails.logger.error "WecomCustomerService::SendOnChannelService failed: #{error_message}"
    Messages::StatusUpdateService.new(message, 'failed', error_message).perform
  end

  def send_error_message(api_client, external_userid, error)
    service_state = api_client.get_service_state(external_userid: external_userid)
    state = service_state.fetch('service_state').to_i
    state_label = SERVICE_STATE_LABELS[state]
    suffix = " (service_state: #{state}#{": #{state_label}" if state_label})"
    "#{error.message}#{suffix}"
  rescue StandardError => state_error
    Rails.logger.warn "WeCom service state lookup failed: #{state_error.class}: #{state_error.message}"
    error.message
  end

  def send_text(api_client, external_userid)
    response = api_client.send_text(external_userid: external_userid, content: message.outgoing_content)
    message.update!(source_id: response['msgid']) if response['msgid'].present?
  end

  def send_attachment(api_client, external_userid, attachment)
    media_type = attachment_media_type(attachment)
    attachment.file.blob.open do |file|
      upload = api_client.upload_media(
        file: file,
        filename: attachment.file.filename.to_s,
        content_type: attachment.file.content_type || 'application/octet-stream',
        media_type: media_type
      )
      response = api_client.send_media(
        external_userid: external_userid,
        media_type: media_type,
        media_id: upload.fetch('media_id')
      )
      message.update!(source_id: response['msgid']) if response['msgid'].present?
    end
  end

  def attachment_media_type(attachment)
    return 'image' if attachment.image?
    return 'voice' if attachment.audio?
    return 'video' if attachment.video?

    'file'
  end
end
