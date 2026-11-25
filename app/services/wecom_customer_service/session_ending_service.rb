# Sends the end-of-session action (rating menu and/or closing message) configured for the entry type
# the session belongs to. WeCom allows a single event response per session end, so the closing
# message is used as the rating menu's guiding text when both are configured.
class WecomCustomerService::SessionEndingService
  OPTIONS = { 5 => '满意', 3 => '一般', 1 => '不满意' }.freeze
  HANDLED_KEY = 'wecom_session_ending'.freeze

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

  def perform(code:, entry_scope:, trigger:, servicer_userid: nil)
    config_scope = WecomCustomerService::SessionScope.config_scope(entry_scope, trigger)
    config = @channel.end_config(config_scope)

    @conversation.with_lock do
      return if handled?

      return mark_handled(config_scope, trigger, servicer_userid, kind: 'missing_code') if code.blank?

      if config.satisfaction_enabled?
        client.send_event_menu_response(code: code, menu: menu(config), msgid: message_id)
        mark_handled(config_scope, trigger, servicer_userid, kind: 'menu')
      elsif config.ending_message.present?
        client.send_event_response(code: code, content: config.ending_message, msgid: message_id)
        mark_handled(config_scope, trigger, servicer_userid, kind: 'text')
      else
        mark_handled(config_scope, trigger, servicer_userid, kind: 'none')
      end
    end
  end

  private

  def client
    @client ||= WecomCustomerService::ApiClient.new(channel: @channel)
  end

  def handled?
    @conversation.extensions.to_h.dig(HANDLED_KEY, 'handled') == true
  end

  def menu(config)
    {
      head_content: [config.ending_message.presence, config.satisfaction_message].compact.join("\n"),
      list: OPTIONS.map do |rating, label|
        { type: 'click', click: { id: "cw_csat_#{@conversation.id}_#{rating}", content: label } }
      end
    }
  end

  def mark_handled(config_scope, trigger, servicer_userid, kind:)
    ending = {
      'handled' => true,
      'message_sent' => %w[menu text].include?(kind),
      'kind' => kind,
      'scope' => config_scope,
      'trigger' => trigger.to_s
    }
    ending['servicer_userid'] = servicer_userid.presence if servicer_userid.present?
    @conversation.update!(extensions: @conversation.extensions.to_h.merge(HANDLED_KEY => ending))
  end

  def message_id
    "cw_#{Digest::SHA256.hexdigest("wecom_survey:#{@channel.id}:#{@conversation.id}")[0, 24]}"
  end
end
