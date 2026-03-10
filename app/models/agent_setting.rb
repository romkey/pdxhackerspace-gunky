class AgentSetting < ApplicationRecord
  validates :ollama_url, presence: true
  validates :ollama_model, presence: true
  validates :prompt, presence: true

  def self.instance
    first_or_create!
  end

  def self.enabled?
    instance.enabled?
  end
end
