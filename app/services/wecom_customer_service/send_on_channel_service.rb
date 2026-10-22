class WecomCustomerService::SendOnChannelService < Base::SendOnChannelService
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
    Messages::StatusUpdateService.new(message, 'delivered').perform
  rescue StandardError => e
    Rails.logger.warn "WeCom reply failed for message=#{message.id}: #{e.class}: #{e.message}"
    Messages::StatusUpdateService.new(message, 'failed', e.message).perform
  end

  def invalid_message?
    super || message.failed?
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
