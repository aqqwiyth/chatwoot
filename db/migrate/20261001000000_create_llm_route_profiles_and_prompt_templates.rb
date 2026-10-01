class CreateLlmRouteProfilesAndPromptTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :llm_route_profiles do |t|
      t.references :account, foreign_key: true, null: true
      t.string :route_key, null: false
      t.string :provider, null: false, default: 'openai'
      t.string :protocol, null: false, default: 'openai_compatible'
      t.string :model, null: false
      t.string :endpoint
      t.text :api_key
      t.boolean :enabled, null: false, default: true
      t.jsonb :options, null: false, default: {}
      t.integer :version, null: false, default: 1
      t.timestamps
    end
    add_index :llm_route_profiles, [:account_id, :route_key], unique: true
    add_index :llm_route_profiles, :route_key

    create_table :llm_prompt_templates do |t|
      t.string :key, null: false
      t.text :content, null: false
      t.jsonb :metadata, null: false, default: {}
      t.string :source_path
      t.string :source_checksum
      t.integer :revision, null: false, default: 1
      t.references :updated_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
    end
    add_index :llm_prompt_templates, :key, unique: true

    add_column :article_embeddings, :embedding_profile_version, :integer, null: false, default: 1
    add_column :captain_assistant_responses, :embedding_profile_version, :integer, null: false, default: 1
    add_column :captain_faq_suggestions, :embedding_profile_version, :integer, null: false, default: 1
  end
end
