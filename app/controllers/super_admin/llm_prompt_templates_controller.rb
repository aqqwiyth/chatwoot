class SuperAdmin::LlmPromptTemplatesController < SuperAdmin::ApplicationController
  before_action :set_template, only: [:edit, :update, :destroy]

  def index
    Llm::PromptCatalog.sync!
    @templates = Llm::PromptTemplate.order(:key)
  end

  def edit; end

  def create
    template = Llm::PromptTemplate.new(prompt_params.merge(updated_by: current_super_admin, metadata: { 'liquid' => true }))
    Captain::PromptResolver.validate!(template.content, key: template.key)
    template.save!
    redirect_to super_admin_llm_prompt_templates_path, notice: 'Prompt template created.'
  rescue Captain::PromptResolver::InvalidTemplateError, ActiveRecord::RecordInvalid => e
    redirect_to super_admin_llm_prompt_templates_path, alert: e.message
  end

  def update
    @template.content = params.require(:llm_prompt_template).fetch(:content)
    @template.updated_by = current_super_admin
    if Captain::PromptResolver.validate!(@template.content, key: @template.key)
      @template.save!
      redirect_to super_admin_llm_prompt_templates_path, notice: 'Prompt template saved.'
    end
  rescue Captain::PromptResolver::InvalidTemplateError, Liquid::SyntaxError, ActiveRecord::RecordInvalid => e
    redirect_to edit_super_admin_llm_prompt_template_path(@template), alert: e.message
  end

  def destroy
    @template.destroy!
    redirect_to super_admin_llm_prompt_templates_path, notice: 'Prompt template restored to repository default.'
  end

  private

  def set_template
    @template = Llm::PromptTemplate.find(params[:id])
  end

  def prompt_params
    params.require(:llm_prompt_template).permit(:key, :content)
  end
end
