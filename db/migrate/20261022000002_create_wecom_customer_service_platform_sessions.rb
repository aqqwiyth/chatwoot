class CreateWecomCustomerServicePlatformSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :wecom_customer_service_platform_sessions do |t|
      t.references :channel, null: false, foreign_key: { to_table: :channel_wecom_customer_services, on_delete: :cascade }
      t.string :external_userid, null: false
      t.integer :service_state
      t.string :servicer_userid
      t.string :source, null: false, default: 'unknown'
      t.datetime :observed_at
      t.datetime :next_refresh_at, null: false
      t.timestamps
    end

    add_index :wecom_customer_service_platform_sessions, [:channel_id, :external_userid], unique: true,
              name: 'index_wecom_platform_sessions_on_channel_and_user'
    add_index :wecom_customer_service_platform_sessions, :next_refresh_at, name: 'index_wecom_platform_sessions_on_next_refresh'
  end
end
