# == Schema Information
#
# Table name: channel_wecom_customer_services
#
#  id                              :bigint           not null, primary key
#  agent_response_timeout_minutes  :integer          default(0), not null
#  bot_fallback_enabled            :boolean          default(FALSE), not null
#  bot_fallback_target             :string           default("wecom_platform"), not null
#  bot_fallback_timeout_seconds    :integer          default(120), not null
#  callback_token                  :string           not null
#  cursor                          :string
#  encoding_aes_key                :string           not null
#  human_reception_enabled         :boolean          default(TRUE), not null
#  identifier                      :string           not null
#  max_concurrent_receptions       :integer          default(10), not null
#  open_kfid                       :string           not null
#  outside_reception_hours_message :text             default("当前不在人工接待时间，请稍后联系。"), not null
#  reception_busy_message          :text             default("当前暂无客服接待，请稍后联系。"), not null
#  reception_queue_auto_assign     :boolean          default(FALSE), not null
#  reception_queue_enabled         :boolean          default(TRUE), not null
#  reception_servicer_names        :jsonb            not null
#  secret                          :string           not null
#  session_assigned_message        :text
#  welcome_message                 :text
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  account_id                      :bigint           not null
#  corp_id                         :string           not null
#
# Indexes
#
#  index_channel_wecom_customer_services_on_account_id  (account_id)
#  index_channel_wecom_customer_services_on_identifier  (identifier) UNIQUE
#
class Channel::WecomCustomerService < ApplicationRecord
  include Channelable

  self.table_name = 'channel_wecom_customer_services'
  EDITABLE_ATTRS = [:open_kfid, :secret, :callback_token, :encoding_aes_key, :corp_id,
                    :welcome_message, :session_assigned_message,
                    :bot_fallback_timeout_seconds,
                    :human_reception_enabled, :reception_queue_enabled, :outside_reception_hours_message,
                    :reception_busy_message, :max_concurrent_receptions, :reception_queue_auto_assign,
                    :agent_response_timeout_minutes, :credential_mode].freeze

  has_many :end_configs, class_name: 'WecomCustomerService::EndConfig', dependent: :destroy, inverse_of: :channel

  has_secure_token :identifier

  before_validation :set_isv_secret_placeholder
  before_update :reset_cursor, if: :sync_scope_changed?
  after_update_commit :clear_access_token_cache, if: :access_token_credentials_changed?

  if Chatwoot.encryption_configured?
    encrypts :secret
    encrypts :callback_token
    encrypts :encoding_aes_key
  end

  validates :agent_response_timeout_minutes, inclusion: { in: [0, 10, 30, 60, 720, 2880] }
  validates :bot_fallback_enabled, inclusion: { in: [true, false] }
  validates :human_reception_enabled, :reception_queue_enabled, inclusion: { in: [true, false] }
  validates :outside_reception_hours_message, :reception_busy_message, presence: true, length: { maximum: 500 }
  validates :bot_fallback_timeout_seconds, numericality: { only_integer: true, in: 60..300 }, if: :will_save_change_to_bot_fallback_timeout_seconds?
  validates :max_concurrent_receptions, numericality: { only_integer: true, greater_than: 0 }
  validates :reception_queue_auto_assign, inclusion: { in: [true, false] }
  validates :bot_fallback_target, inclusion: { in: %w[wecom_platform chatwoot] }
  validates :identifier, uniqueness: true
  validates :open_kfid, presence: true
  validates :credential_mode, inclusion: { in: %w[direct isv] }
  validates :secret, presence: true, if: -> { credential_mode == 'direct' }
  validates :corp_id, presence: true
  validates :callback_token, presence: true
  validates :encoding_aes_key, presence: true, length: { is: 43 }

  def name
    '微信客服'
  end

  def callback_webhook_url
    "#{ENV.fetch('FRONTEND_URL', '')}/webhooks/wecom_customer_service/#{identifier}"
  end

  # Every entry type has its own end-of-session settings. Rows are created lazily so a channel that
  # was never configured keeps the column defaults.
  def end_config(scope)
    end_configs.find_or_initialize_by(scope: scope)
  end

  def end_configs_snapshot
    WecomCustomerService::EndConfig::SCOPES.map { |scope| end_config(scope) }
  end

  private

  def sync_scope_changed?
    will_save_change_to_open_kfid? || will_save_change_to_corp_id?
  end

  def reset_cursor
    self.cursor = nil
    self.reception_servicer_names = {}
  end

  def set_isv_secret_placeholder
    self.secret = '' if credential_mode == 'isv' && secret.nil?
  end

  def access_token_credentials_changed?
    saved_change_to_secret? || saved_change_to_corp_id? || saved_change_to_credential_mode?
  end

  def clear_access_token_cache
    Rails.cache.delete("wecom_customer_service/access_token/#{id}")
  end
end
