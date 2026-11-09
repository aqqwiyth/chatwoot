class UpdateWecomReceptionConfiguration < ActiveRecord::Migration[7.2]
  def change
    change_table :channel_wecom_customer_services, bulk: true do |t|
      t.remove :webhook_url, type: :string, null: false
      t.integer :max_concurrent_receptions, null: false, default: 10
      t.boolean :reception_queue_auto_assign, null: false, default: false
      t.boolean :satisfaction_invitation_enabled, null: false, default: false
      t.text :satisfaction_invitation_message, null: false, default: '你对本次服务是否满意？'
    end
    change_column_default :channel_wecom_customer_services, :bot_fallback_timeout_seconds, from: 30, to: 120
  end
end
