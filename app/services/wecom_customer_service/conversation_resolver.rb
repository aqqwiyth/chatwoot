class WecomCustomerService::ConversationResolver
  def initialize(inbox:, contact_inbox:, ended_event:, event_time:, satisfaction:)
    @inbox = inbox
    @contact_inbox = contact_inbox
    @ended_event = ended_event
    @event_time = event_time
    @satisfaction = satisfaction
  end

  def perform
    return @contact_inbox.conversations.find_by(id: @satisfaction[:conversation_id]) if @satisfaction.present?

    conversation = previous_conversation
    return conversation if conversation && (@ended_event || !closed_wecom_session?(conversation))

    @contact_inbox.conversations.create!(
      account_id: @inbox.account_id,
      inbox: @inbox,
      contact_id: @contact_inbox.contact_id
    )
  end

  private

  def previous_conversation
    conversations = @contact_inbox.conversations
    if @ended_event
      conversations.where('created_at < ?', @event_time + 1.second).order(created_at: :desc).first
    elsif @inbox.lock_to_single_conversation
      conversations.order(created_at: :desc).first
    else
      conversations.where.not(status: :resolved).order(created_at: :desc).first
    end
  end

  def closed_wecom_session?(conversation)
    conversation.resolved? && conversation.extensions.to_h['wecom_session_ended'] == true
  end
end
