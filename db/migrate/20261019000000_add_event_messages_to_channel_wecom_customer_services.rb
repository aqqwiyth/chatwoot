class AddEventMessagesToChannelWecomCustomerServices < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_wecom_customer_services, :welcome_message, :text
    add_column :channel_wecom_customer_services, :session_assigned_message, :text
    add_column :channel_wecom_customer_services, :session_ended_message, :text
  end
end
