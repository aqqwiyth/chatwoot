# Classifies the WeCom customer service session that a reply belongs to, so the end-of-session
# settings can be picked per entry type:
#
#   ai      - the smart assistant is serving the customer (service_state 1)
#   handoff - this system moved the session to human reception (service_state 2/3)
#   direct  - the platform already had a human servicer and this system did not hand it off
#             (repeat entry inside an active session, platform-side auto assignment)
#
# Each entry type then has one or two config scopes: handoff sessions track their inactivity
# timeout and their end action separately for system ends and servicer ends.
module WecomCustomerService::SessionScope
  AI = 'ai'.freeze
  HANDOFF = 'handoff'.freeze
  DIRECT = 'direct'.freeze
  ENTRY_KEY = 'wecom_entry_type'.freeze
  AUTO_TRIGGER = 'auto'.freeze
  MANUAL_TRIGGER = 'manual'.freeze
  CONFIG_SCOPES = {
    [HANDOFF, AUTO_TRIGGER] => 'handoff_auto',
    [HANDOFF, MANUAL_TRIGGER] => 'handoff_manual'
  }.freeze

  def self.ai_reply?(message)
    message.sender_type == 'AgentBot' || message.content_attributes.to_h['kefu_ai_reply_task_id'].present?
  end

  def self.for_message(message)
    return AI if ai_reply?(message)

    handoff?(message.conversation) ? HANDOFF : DIRECT
  end

  def self.for_conversation(conversation, servicer_userid: nil)
    return HANDOFF if handoff?(conversation)
    return DIRECT if servicer_userid.present?

    AI
  end

  def self.config_scope(entry_scope, trigger)
    CONFIG_SCOPES.fetch([entry_scope, trigger.to_s], entry_scope)
  end

  def self.handoff?(conversation)
    conversation.extensions.to_h[ENTRY_KEY] == HANDOFF
  end
end
