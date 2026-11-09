class ChangeDefaultInboxTimezone < ActiveRecord::Migration[7.2]
  def change
    change_column_default :inboxes, :timezone, from: 'UTC', to: 'Asia/Shanghai'
  end
end
