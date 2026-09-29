# == Schema Information
#
# Table name: channel_wecom_customer_services
#
#  id               :bigint           not null, primary key
#  callback_token   :string           not null
#  cursor           :string
#  encoding_aes_key :string           not null
#  identifier       :string           not null
#  open_kfid        :string           not null
#  secret           :string           not null
#  webhook_url      :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  corp_id          :string           not null
#
# Indexes
#
#  index_channel_wecom_customer_services_on_account_id  (account_id)
#  index_channel_wecom_customer_services_on_identifier  (identifier) UNIQUE
#
class Channel::WecomCustomerService < ApplicationRecord
  include Channelable

  self.table_name = 'channel_wecom_customer_services'
  EDITABLE_ATTRS = [:open_kfid, :secret, :webhook_url, :callback_token, :encoding_aes_key, :corp_id].freeze

  has_secure_token :identifier

  before_update :reset_cursor, if: :sync_scope_changed?
  after_update_commit :clear_access_token_cache, if: :access_token_credentials_changed?

  if Chatwoot.encryption_configured?
    encrypts :secret
    encrypts :callback_token
    encrypts :encoding_aes_key
  end

  validates :identifier, uniqueness: true
  validates :webhook_url,
            presence: true,
            length: { maximum: Limits::URL_LENGTH_LIMIT },
            format: URI::DEFAULT_PARSER.make_regexp(%w[http https])
  validates :open_kfid, presence: true
  validates :secret, presence: true
  validates :corp_id, presence: true
  validates :callback_token, presence: true
  validates :encoding_aes_key, presence: true, length: { is: 43 }

  def name
    '微信客服'
  end

  def callback_webhook_url
    "#{ENV.fetch('FRONTEND_URL', '')}/webhooks/wecom_customer_service/#{identifier}"
  end

  private

  def sync_scope_changed?
    will_save_change_to_open_kfid? || will_save_change_to_corp_id?
  end

  def reset_cursor
    self.cursor = nil
  end

  def access_token_credentials_changed?
    saved_change_to_secret? || saved_change_to_corp_id?
  end

  def clear_access_token_cache
    Rails.cache.delete("wecom_customer_service/access_token/#{id}")
  end
end
