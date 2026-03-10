class DescribeItemJob < ApplicationJob
  queue_as :default

  retry_on OllamaService::Error, wait: 30.seconds, attempts: 3

  def perform(item_id)
    item = Item.find_by(id: item_id)
    return unless item
    return unless item.photo.attached?
    return unless AgentSetting.enabled?

    # Don't overwrite a user-provided description
    return if item.description.present? && item.ai_description.blank? && item.description != item.ai_description

    ai_text = OllamaService.new.describe_image(item.photo)

    if item.description.blank?
      item.update!(description: ai_text, ai_description: ai_text)
    else
      item.update!(ai_description: ai_text)
    end

    item.broadcast_replace_to(
      "item_#{item.id}",
      target: "item_description",
      partial: "items/description",
      locals: { item: item }
    )
  rescue OllamaService::Error => e
    Rails.logger.error("Ollama describe failed for item #{item_id}: #{e.message}")
    raise
  end
end
