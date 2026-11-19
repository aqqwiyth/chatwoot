class AddCredentialModeToWecomCustomerServices < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_wecom_customer_services, :credential_mode, :string, default: 'direct', null: false
  end
end
