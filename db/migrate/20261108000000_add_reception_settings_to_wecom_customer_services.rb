class AddReceptionSettingsToWecomCustomerServices < ActiveRecord::Migration[7.1]
  def change
    change_table :channel_wecom_customer_services, bulk: true do |t|
      t.boolean :human_reception_enabled, null: false, default: true
      t.boolean :reception_queue_enabled, null: false, default: true
      t.jsonb :reception_servicer_names, null: false, default: {}
      t.text :outside_reception_hours_message, null: false,
                                               default: 'Our human agents are currently outside working hours.'
      t.text :reception_busy_message, null: false,
                                      default: 'No human agents are available right now. Please wait for the next available agent.'
    end
  end
end
