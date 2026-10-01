class Captain::PromptResolver
  class InvalidTemplateError < StandardError; end

  class << self
    def validate!(content, key: nil)
      raise InvalidTemplateError, 'Prompt template is too long' if content.to_s.length > 100_000

      Liquid::Template.parse(content.to_s)
      true
    rescue Liquid::SyntaxError => e
      raise InvalidTemplateError, "Invalid Liquid template #{key}: #{e.message}"
    end

    def install_inline_prompt_overrides!
      return if @inline_overrides_installed

      mappings = {
        'Captain::AssistantMigration::InstructionAuditor' => 'instruction_auditor',
        'Captain::AssistantMigration::InstructionClassifier' => 'instruction_classifier',
        'Captain::AssistantOverviewSummaryService' => 'assistant_overview_summary',
        'Captain::Llm::ConversationFaqService' => 'conversation_faq',
        'Captain::Llm::HelpCenterCurationService' => 'help_center_curation',
        'Captain::Llm::TranslateQueryService' => 'translate_query',
        'Captain::Llm::WidgetTaglineService' => 'widget_tagline'
      }

      mappings.each do |class_name, key|
        klass = class_name.safe_constantize
        next unless klass && (klass.method_defined?(:system_prompt) || klass.private_method_defined?(:system_prompt))

        resolver = self
        klass.prepend(Module.new do
          define_method(:system_prompt) do |*args, **kwargs|
            resolver.render(key, fallback: super(*args, **kwargs))
          end
        end)
      end
      @inline_overrides_installed = true
    end

    def render(key, variables = {}, fallback: nil)
      install_inline_prompt_overrides!
      template = Llm::PromptTemplate.find_by(key: key.to_s)&.content
      template ||= fallback || default_template(key)
      validate!(template, key: key)
      return template if variables.blank?

      Liquid::Template.parse(template).render(variables.stringify_keys)
    rescue Liquid::SyntaxError => e
      raise InvalidTemplateError, "Invalid Liquid template #{key}: #{e.message}"
    end

    def revision(key)
      Llm::PromptTemplate.find_by(key: key.to_s)&.revision || 0
    end

    def default_template(key)
      paths = [
        Rails.root.join('lib/integrations/openai/openai_prompts', "#{key}.liquid"),
        Rails.root.join('enterprise/lib/captain/prompts', "#{key}.liquid")
      ]
      path = paths.find(&:exist?)
      path ? path.read : ''
    end
  end
end
