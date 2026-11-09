class AddAutoCloseToWecomCustomerServices < ActiveRecord::Migration[7.2]
  def change
    add_column :channel_wecom_customer_services, :auto_close_after_minutes, :integer, null: false, default: 0
    add_column :channel_wecom_customer_services, :agent_response_timeout_minutes, :integer, null: false, default: 0
    add_column :wecom_customer_service_platform_sessions, :last_customer_message_at, :datetime
    add_column :wecom_customer_service_platform_sessions, :auto_close_attempted_at, :datetime
    add_column :wecom_customer_service_platform_sessions, :auto_close_reply_at, :datetime
    add_column :wecom_customer_service_platform_sessions, :auto_close_reply_id, :bigint
  end
end
