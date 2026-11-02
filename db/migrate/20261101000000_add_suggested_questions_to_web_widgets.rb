class AddSuggestedQuestionsToWebWidgets < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_web_widgets, :suggested_questions, :jsonb, null: false, default: []
  end
end
