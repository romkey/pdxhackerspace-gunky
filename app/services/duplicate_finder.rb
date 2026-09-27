class DuplicateFinder
  Match = Struct.new(:item, :rank, :shared_lexemes, keyword_init: true)

  # Stemmed words that vision-model descriptions share regardless of the object.
  STOPLIST = %w[
    condit good fair poor use appear item object photo imag show wear worn visibl look
  ].freeze

  WINDOW = 60.days
  MIN_SHARED_LEXEMES = 2
  DEFAULT_MIN_RANK = 0.2
  LIMIT = 3

  TEXT_SQL = "coalesce(items.description, '') || ' ' || coalesce(items.ai_description, '')".freeze
  VECTOR_SQL = "to_tsvector('english', #{TEXT_SQL})".freeze

  def self.min_rank
    Float(ENV.fetch("DUPLICATE_HINT_MIN_RANK", DEFAULT_MIN_RANK))
  rescue ArgumentError
    DEFAULT_MIN_RANK
  end

  def initialize(item)
    @item = item
  end

  def matches(min_rank: self.class.min_rank, min_shared: MIN_SHARED_LEXEMES, limit: LIMIT)
    return [] if lexemes.size < min_shared

    ranked_candidates
      .map { |candidate| match_for(candidate) }
      .select { |match| match.rank >= min_rank && match.shared_lexemes.size >= min_shared }
      .first(limit)
  end

  def lexemes
    @lexemes ||= begin
      text = "#{@item.description} #{@item.ai_description}"
      sql = Item.sanitize_sql_array([ "SELECT unnest(tsvector_to_array(to_tsvector('english', ?)))", text ])
      Item.connection.select_values(sql).reject { |lexeme| lexeme.length < 2 || STOPLIST.include?(lexeme) }
    end
  end

  private

  def ranked_candidates
    query = Item.sanitize_sql_array([ "CAST(? AS tsquery)", tsquery_text ])

    candidates
      .select(
        "items.*",
        "ts_rank_cd(#{VECTOR_SQL}, #{query}, 32) AS duplicate_rank",
        "tsvector_to_array(#{VECTOR_SQL}) AS duplicate_lexemes"
      )
      .where("#{VECTOR_SQL} @@ #{query}")
      .order(Arel.sql("duplicate_rank DESC"), created_at: :desc)
  end

  # Earlier items only, so the report over past items matches the live check.
  def candidates
    scope = @item.in_lost_found? ? Item.lost_found_visible : Item.gunky_visible
    scope
      .where.not(id: @item.id)
      .where(created_at: (@item.created_at - WINDOW)...@item.created_at)
  end

  # Cast rather than to_tsquery so the lexemes are not stemmed a second time.
  def tsquery_text
    lexemes.map { |lexeme| "'#{lexeme.gsub('\\', '\\\\\\\\').gsub("'", "''")}'" }.join(" | ")
  end

  def match_for(candidate)
    shared = Array(candidate.duplicate_lexemes) & lexemes
    Match.new(item: candidate, rank: candidate.duplicate_rank.to_f, shared_lexemes: shared)
  end
end
