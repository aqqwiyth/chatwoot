class AddBotFallbackToChannelWecomCustomerServices < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_wecom_customer_services, :bot_fallback_enabled, :boolean, null: false, default: false
    add_column :channel_wecom_customer_services, :bot_fallback_timeout_seconds, :integer, null: false, default: 30
    add_column :channel_wecom_customer_services, :bot_fallback_target, :string, null: false, default: 'wecom_platform'
  end
end
