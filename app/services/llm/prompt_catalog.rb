class Llm::PromptCatalog
  DIRECTORIES = %w[lib/integrations/openai/openai_prompts enterprise/lib/captain/prompts].freeze

  class << self
    def sync!
      prompt_files.each do |path|
        key = path.basename('.liquid').to_s
        template = Llm::PromptTemplate.find_or_initialize_by(key: key)
        next if template.persisted?

        template.content = path.read
        template.source_path = path.to_s.delete_prefix("#{Rails.root}/")
        template.metadata = metadata_for(key)
        template.save!
      end
      method_defaults.each do |key, content|
        next if Llm::PromptTemplate.exists?(key: key)

        Llm::PromptTemplate.create!(key: key, content: content, metadata: metadata_for(key), source_path: 'enterprise/app/services/captain/llm/system_prompts_service.rb')
      end
    end

    def method_defaults
      return {} unless defined?(Captain::Llm::SystemPromptsService)

      {
        'faq_generator' => Captain::Llm::SystemPromptsService.repository_faq_generator,
        'notes_generator' => Captain::Llm::SystemPromptsService.repository_notes_generator,
        'attributes_generator' => Captain::Llm::SystemPromptsService.repository_attributes_generator,
        'assistant_action_classifier' => Captain::Llm::SystemPromptsService.repository_assistant_action_classifier,
        'assistant_false_promise_detector' => Captain::Llm::SystemPromptsService.repository_assistant_false_promise_detector
      }
    end

    def prompt_files
      DIRECTORIES.flat_map do |directory|
        root = Rails.root.join(directory)
        root.exist? ? root.glob('**/*.liquid') : []
      end.uniq { |path| path.basename('.liquid').to_s }
    end

    def metadata_for(key)
      { 'route' => route_for(key), 'liquid' => true, 'output_format' => 'text' }
    end

    def route_for(key)
      return 'label_suggestion' if key == 'label_suggestion'
      return 'assistant' if key.start_with?('assistant') || key.in?(%w[scenario instruction_auditor instruction_classifier])
      return 'copilot' if key.include?('copilot')
      return 'embedding' if key == 'embedding'

      'editor'
    end
  end
end
