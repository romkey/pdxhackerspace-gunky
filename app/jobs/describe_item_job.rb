class DescribeItemJob < ApplicationJob
  queue_as :default

  retry_on OllamaService::Error, wait: 30.seconds, attempts: 3

  def perform(item_id, force: false)
    item = Item.find_by(id: item_id)
    return unless item
    return unless item.photo.attached?
    return unless AgentSetting.enabled?

    Rails.logger.info("DescribeItemJob: processing item #{item_id} (force=#{force})")

    ai_text = OllamaService.new.describe_image(item.photo)
    Rails.logger.info("DescribeItemJob: got AI response for item #{item_id}: #{ai_text.truncate(100)}")

    if item.description.blank? || force
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
    Rails.logger.error("DescribeItemJob: Ollama failed for item #{item_id}: #{e.message}")
    raise
  end
end
