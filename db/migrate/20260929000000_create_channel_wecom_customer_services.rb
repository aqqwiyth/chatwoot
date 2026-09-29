class CreateChannelWecomCustomerServices < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_wecom_customer_services do |t|
      t.references :account, null: false
      t.string :identifier, null: false
      t.string :open_kfid, null: false
      t.string :secret, null: false
      t.string :webhook_url, null: false
      t.string :callback_token, null: false
      t.string :encoding_aes_key, null: false
      t.string :corp_id, null: false
      t.string :cursor
      t.timestamps
    end

    add_index :channel_wecom_customer_services, :identifier, unique: true
  end
end
