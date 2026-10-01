class Captain::Llm::ReindexEmbeddingsJob < ApplicationJob
  queue_as :low

  def perform(account_id = nil)
    scope = account_id ? Captain::AssistantResponse.where(account_id: account_id) : Captain::AssistantResponse.all
    scope.find_each { |record| Captain::Llm::UpdateEmbeddingJob.perform_later(record, "#{record.question}: #{record.answer}") }

    faq_scope = account_id ? Captain::FaqSuggestion.where(account_id: account_id) : Captain::FaqSuggestion.all
    faq_scope.find_each { |record| Captain::Llm::UpdateEmbeddingJob.perform_later(record, "#{record.question}: #{record.answer}") }

    articles = account_id ? Article.where(account_id: account_id) : Article.all
    articles.find_each { |article| Portal::ArticleIndexingJob.perform_later(article) }
  end
end
