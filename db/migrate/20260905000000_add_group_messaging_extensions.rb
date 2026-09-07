class AddGroupMessagingExtensions < ActiveRecord::Migration[7.0]
  def change
    create_table :channel_group_messaging do |t|
      t.references :account, null: false
      t.string :provider, null: false
      t.string :identifier, null: false
      t.jsonb :provider_config, null: false, default: {}
      t.jsonb :capabilities, null: false, default: {}
      t.timestamps
    end unless table_exists?(:channel_group_messaging)

    add_index :channel_group_messaging, [:provider, :identifier], unique: true unless
      index_exists?(:channel_group_messaging, [:provider, :identifier], unique: true)

    add_column :contacts, :extensions, :jsonb, null: false, default: {} unless column_exists?(:contacts, :extensions)
    add_column :conversations, :extensions, :jsonb, null: false, default: {} unless column_exists?(:conversations, :extensions)
    add_column :messages, :extensions, :jsonb, null: false, default: {} unless column_exists?(:messages, :extensions)
    add_column :messages, :external_event_id, :string unless column_exists?(:messages, :external_event_id)

    return if index_exists?(:messages, [:inbox_id, :external_event_id],
                            unique: true,
                            name: 'index_messages_on_inbox_id_and_external_event_id')

    add_index :messages, [:inbox_id, :external_event_id], unique: true,
              where: 'external_event_id IS NOT NULL',
              name: 'index_messages_on_inbox_id_and_external_event_id'
  end
end
