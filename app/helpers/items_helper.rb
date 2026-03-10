module ItemsHelper
  include Pagy::Frontend

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

  def pagy_bootstrap_nav(pagy)
    return "" if pagy.pages <= 1

    html = +""
    html << '<nav><ul class="pagination">'

    if pagy.prev
      html << %(<li class="page-item">#{link_to(raw("&laquo;"), url_for(page: pagy.prev), class: "page-link")}</li>)
    else
      html << '<li class="page-item disabled"><span class="page-link">&laquo;</span></li>'
    end

    pagy.series.each do |item|
      case item
      when Integer
        html << %(<li class="page-item">#{link_to(item, url_for(page: item), class: "page-link")}</li>)
      when String
        html << %(<li class="page-item active"><span class="page-link">#{item}</span></li>)
      when :gap
        html << '<li class="page-item disabled"><span class="page-link">&hellip;</span></li>'
      end
    end

    if pagy.next
      html << %(<li class="page-item">#{link_to(raw("&raquo;"), url_for(page: pagy.next), class: "page-link")}</li>)
    else
      html << '<li class="page-item disabled"><span class="page-link">&raquo;</span></li>'
    end

    html << "</ul></nav>"
    html.html_safe
  end
end
