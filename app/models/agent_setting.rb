class AgentSetting < ApplicationRecord
  validates :ollama_url, presence: true
  validates :ollama_model, presence: true
  validates :prompt, presence: true

  def has_api_key?
    api_key.present?
  end

  def self.instance
    first_or_create!
  end

  def self.enabled?
    instance.enabled?
  end
end
