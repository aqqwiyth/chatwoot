class CreateWecomCustomerServiceEndConfigs < ActiveRecord::Migration[7.2]
  def up
    create_table :wecom_customer_service_end_configs do |t|
      t.bigint :channel_id, null: false
      t.string :scope, null: false
      t.integer :auto_close_after_minutes, null: false, default: 0
      t.boolean :satisfaction_enabled, null: false, default: false
      t.text :satisfaction_message, null: false, default: '你对本次服务是否满意？'
      t.text :ending_message, null: false, default: ''
      t.timestamps
    end
    add_index :wecom_customer_service_end_configs, %i[channel_id scope], unique: true,
                                                                          name: 'index_wecom_end_configs_on_channel_and_scope'
    add_foreign_key :wecom_customer_service_end_configs, :channel_wecom_customer_services, column: :channel_id,
                                                                                         on_delete: :cascade

    # Existing channels were configured through the global settings, so every entry type starts from
    # the same values. Manual handoff endings have no inactivity timeout.
    execute <<~SQL.squish
      INSERT INTO wecom_customer_service_end_configs
        (channel_id, scope, auto_close_after_minutes, satisfaction_enabled, satisfaction_message,
         ending_message, created_at, updated_at)
      SELECT c.id, s.scope,
             CASE WHEN s.scope = 'handoff_manual' THEN 0 ELSE c.auto_close_after_minutes END,
             c.satisfaction_invitation_enabled,
             c.satisfaction_invitation_message,
             COALESCE(c.session_ended_message, ''),
             NOW(), NOW()
      FROM channel_wecom_customer_services c
      CROSS JOIN (VALUES ('ai'), ('handoff_auto'), ('handoff_manual'), ('direct')) AS s(scope)
    SQL
  end

  def down
    drop_table :wecom_customer_service_end_configs
  end
end
