class ReconcileContactTypeForChatwootV417 < ActiveRecord::Migration[7.0]
  def up
    return unless column_exists?(:contacts, :contact_type)
    return if contact_type_column.type == :integer

    remove_check_constraint :contacts, name: 'contacts_contact_type_check' if
      check_constraint_exists?(:contacts, name: 'contacts_contact_type_check')

    execute <<~SQL
      ALTER TABLE contacts ALTER COLUMN contact_type DROP DEFAULT;
      ALTER TABLE contacts
        ALTER COLUMN contact_type TYPE integer
        USING CASE contact_type
          WHEN 'lead' THEN 1
          WHEN 'customer' THEN 2
          WHEN 'group' THEN 3
          ELSE 0
        END;
      ALTER TABLE contacts ALTER COLUMN contact_type SET DEFAULT 0;
      ALTER TABLE contacts ALTER COLUMN contact_type SET NOT NULL;
    SQL
  end

  def down
    return unless column_exists?(:contacts, :contact_type)
    return unless contact_type_column.type == :integer

    execute <<~SQL
      ALTER TABLE contacts ALTER COLUMN contact_type DROP DEFAULT;
      ALTER TABLE contacts
        ALTER COLUMN contact_type TYPE varchar
        USING CASE contact_type
          WHEN 3 THEN 'group'
          ELSE 'person'
        END;
      ALTER TABLE contacts ALTER COLUMN contact_type SET DEFAULT 'person';
    SQL

    add_check_constraint :contacts, "contact_type IN ('person', 'group')",
                         name: 'contacts_contact_type_check'
  end

  private

  def contact_type_column
    connection.columns(:contacts).find { |column| column.name == 'contact_type' }
  end
end
