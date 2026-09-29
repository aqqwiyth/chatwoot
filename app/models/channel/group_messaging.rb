# == Schema Information
#
# Table name: channel_group_messaging
#
#  id              :bigint           not null, primary key
#  capabilities    :jsonb            not null
#  identifier      :string           not null
#  provider        :string           not null
#  provider_config :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  index_channel_group_messaging_on_account_id               (account_id)
#  index_channel_group_messaging_on_provider_and_identifier  (provider,identifier) UNIQUE
#
class Channel::GroupMessaging < ApplicationRecord
  include Channelable

  self.table_name = 'channel_group_messaging'

  PROVIDERS = %w[wecom feishu dingtalk].freeze
  EDITABLE_ATTRS = [:provider, :identifier, { provider_config: {} }, { capabilities: {} }].freeze

  validates :provider, inclusion: { in: PROVIDERS }
  validates :provider_config, presence: true
  validates :identifier, presence: true, uniqueness: { scope: :provider }
  validate :validate_wecom_config

  def name
    {
      'wecom' => '企业微信',
      'feishu' => '飞书',
      'dingtalk' => '钉钉'
    }.fetch(provider, provider.to_s.capitalize)
  end

  def messaging_window_enabled?
    false
  end

  def hmac_mandatory
    false
  end

  def hmac_token
    provider_config['hmac_token']
  end

  def adapter
    "GroupMessaging::Providers::#{provider.camelize}".constantize.new(channel: self)
  end

  def callback_webhook_url
    "#{ENV.fetch('FRONTEND_URL', '')}/webhooks/group_messaging/#{provider}/#{identifier}"
  end

  private

  def validate_wecom_config
    return unless provider == 'wecom'

    %w[company_name company_id].each do |key|
      errors.add(:provider_config, "#{key} is required") if provider_config[key].blank?
    end
  end
end
