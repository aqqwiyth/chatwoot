class WecomCustomerService::PlatformSession < ApplicationRecord
  self.table_name = 'wecom_customer_service_platform_sessions'

  belongs_to :channel, class_name: 'Channel::WecomCustomerService'

  validates :external_userid, presence: true, uniqueness: { scope: :channel_id }
  validates :service_state, inclusion: { in: 0..4 }, allow_nil: true
  validates :source, :next_refresh_at, presence: true

  scope :due, -> { where(next_refresh_at: ..Time.current) }

  def refreshable?
    return false if service_state == 4

    contact_inbox = channel.inbox.contact_inboxes.find_by(source_id: external_userid)
    contact_inbox.present? && contact_inbox.conversations.where.not(status: :resolved).exists?
  end
end
