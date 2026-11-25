class RemoveLegacyEndSettingsFromWecomCustomerServices < ActiveRecord::Migration[7.2]
  LEGACY_COLUMNS = {
    auto_close_after_minutes: { type: :integer, null: false, default: 0 },
    satisfaction_invitation_enabled: { type: :boolean, null: false, default: false },
    satisfaction_invitation_message: { type: :text, null: false, default: '你对本次服务是否满意？' },
    session_ended_message: { type: :text, null: true }
  }.freeze

  def up
    remove_column :channel_wecom_customer_services, :auto_close_after_minutes, :integer
    remove_column :channel_wecom_customer_services, :satisfaction_invitation_enabled, :boolean
    remove_column :channel_wecom_customer_services, :satisfaction_invitation_message, :text
    remove_column :channel_wecom_customer_services, :session_ended_message, :text
  end

  def down
    LEGACY_COLUMNS.each do |column, options|
      add_column :channel_wecom_customer_services, column, options[:type], **options.except(:type)
    end

    execute <<~SQL.squish
      UPDATE channel_wecom_customer_services c
      SET auto_close_after_minutes = e.auto_close_after_minutes,
          satisfaction_invitation_enabled = e.satisfaction_enabled,
          satisfaction_invitation_message = e.satisfaction_message,
          session_ended_message = NULLIF(e.ending_message, '')
      FROM wecom_customer_service_end_configs e
      WHERE e.channel_id = c.id AND e.scope = 'ai'
    SQL
  end
end
