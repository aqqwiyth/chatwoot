# End-of-session settings for one entry type of a WeCom customer service channel.
#
#   ai             - the smart assistant serves the customer
#   handoff_auto   - a session this system handed off, ended by customer inactivity
#   handoff_manual - a session this system handed off, ended by a servicer
#   direct         - a session the platform already served with a human servicer
class WecomCustomerService::EndConfig < ApplicationRecord
  SCOPES = %w[ai handoff_auto handoff_manual direct].freeze
  MANUAL_SCOPE = 'handoff_manual'.freeze
  TIMEOUT_OPTIONS = [0, 10, 20, 30, 60, 720, 2880].freeze
  MESSAGE_BYTE_LIMIT = 1024

  self.table_name = 'wecom_customer_service_end_configs'

  belongs_to :channel, class_name: 'Channel::WecomCustomerService', inverse_of: :end_configs

  before_validation :clear_manual_timeout
  after_update_commit :reschedule_auto_close, if: :saved_change_to_auto_close_after_minutes?

  validates :scope, inclusion: { in: SCOPES }, uniqueness: { scope: :channel_id }
  validates :auto_close_after_minutes, inclusion: { in: TIMEOUT_OPTIONS }
  validates :satisfaction_enabled, inclusion: { in: [true, false] }
  validates :satisfaction_message, presence: true, if: :satisfaction_enabled?
  validate :message_sizes

  def api_payload
    {
      scope: scope,
      auto_close_after_minutes: auto_close_after_minutes,
      satisfaction_enabled: satisfaction_enabled,
      satisfaction_message: satisfaction_message,
      ending_message: ending_message
    }
  end

  private

  def clear_manual_timeout
    self.auto_close_after_minutes = 0 if scope == MANUAL_SCOPE
  end

  def message_sizes
    errors.add(:ending_message, :wecom_menu_too_long) if ending_message.to_s.bytesize > MESSAGE_BYTE_LIMIT
    return unless satisfaction_enabled? && satisfaction_message.present?

    errors.add(:satisfaction_message, :wecom_menu_too_long) if satisfaction_message.bytesize > MESSAGE_BYTE_LIMIT
    head_content = [ending_message.presence, satisfaction_message].compact.join("\n")
    errors.add(:ending_message, :wecom_menu_too_long) if head_content.bytesize > MESSAGE_BYTE_LIMIT
  end

  def reschedule_auto_close
    WecomCustomerService::RescheduleAutoCloseJob.perform_later(channel_id)
  end
end
