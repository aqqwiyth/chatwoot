class WecomCustomerService::SatisfactionInvitationService
  OPTIONS = { 5 => '满意', 3 => '一般', 1 => '不满意' }.freeze

  def self.rating_callback(message)
    return unless message['origin'].to_i == 3 && message['msgtype'] == 'text'

    match = /\Acw_csat_(\d+)_(1|3|5)\z/.match(message.dig('text', 'menu_id').to_s)
    return unless match

    rating = match[2].to_i
    { conversation_id: match[1].to_i, rating: rating, label: OPTIONS.fetch(rating) }
  end

  def initialize(channel:, conversation:)
    @channel = channel
    @conversation = conversation
  end

  def perform(code:)
    return unless @channel.satisfaction_invitation_enabled?

    if code.blank?
      Rails.logger.warn("WeCom satisfaction invitation missing event code for conversation=#{@conversation.id}")
      return
    end

    @conversation.with_lock do
      extensions = @conversation.extensions.to_h
      return if extensions.dig('wecom_satisfaction_invitation', 'sent') == true

      WecomCustomerService::ApiClient.new(channel: @channel).send_event_menu_response(
        code: code,
        msgid: "cw_#{Digest::SHA256.hexdigest("wecom_survey:#{@channel.id}:#{@conversation.id}")[0, 24]}",
        menu: menu
      )
      @conversation.update!(extensions: extensions.merge('wecom_satisfaction_invitation' => { 'sent' => true }))
    end
  end

  private

  def menu
    items = OPTIONS.map do |rating, label|
      { type: 'click', click: { id: "cw_csat_#{@conversation.id}_#{rating}", content: label } }
    end
    { head_content: @channel.satisfaction_invitation_message, list: items }
  end
end
