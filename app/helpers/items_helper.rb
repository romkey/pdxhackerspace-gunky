module ItemsHelper
  DISPOSITION_BADGES = {
    "pending" => "bg-secondary",
    "mine"    => "bg-primary",
    "foster"  => "bg-info",
    "kill"    => "bg-danger"
  }.freeze

  VOTE_BADGES = {
    "mine"   => "bg-primary",
    "foster" => "bg-info",
    "kill"   => "bg-danger"
  }.freeze

  def disposition_badge_class(disposition)
    DISPOSITION_BADGES[disposition] || "bg-secondary"
  end

  def vote_badge_class(choice)
    VOTE_BADGES[choice] || "bg-secondary"
  end
end
