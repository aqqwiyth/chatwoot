class LocalizeWecomReceptionDefaults < ActiveRecord::Migration[7.2]
  DEFAULTS = {
    outside_reception_hours_message: [
      'Our human agents are currently outside working hours.',
      '当前不在人工接待时间，请稍后联系。'
    ],
    reception_busy_message: [
      'No human agents are available right now. Please wait for the next available agent.',
      '当前暂无客服接待，请稍后联系。'
    ]
  }.freeze

  def up
    update_defaults(0, 1)
  end

  def down
    update_defaults(1, 0)
  end

  private

  def update_defaults(from_index, to_index)
    DEFAULTS.each do |column, values|
      change_column_default :channel_wecom_customer_services, column, from: values[from_index], to: values[to_index]
      execute <<~SQL.squish
        UPDATE channel_wecom_customer_services
        SET #{column} = #{connection.quote(values[to_index])}
        WHERE #{column} = #{connection.quote(values[from_index])}
      SQL
    end
  end
end
