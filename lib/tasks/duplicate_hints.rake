namespace :gunky do
  namespace :duplicate_hints do
    desc "Print each recent item's closest earlier matches, for tuning DUPLICATE_HINT_MIN_RANK and the stoplist"
    task :report, [ :days ] => :environment do |_task, args|
      days = Integer(args[:days] || 14)
      min_rank = DuplicateFinder.min_rank
      puts "Items from the last #{days} days. Threshold: rank >= #{min_rank}, " \
           "shared >= #{DuplicateFinder::MIN_SHARED_LEXEMES}. [x] = would reply."

      Item.where(created_at: days.days.ago..).find_each do |item|
        finder = DuplicateFinder.new(item)
        site = item.in_lost_found? ? "lost+found" : "gunky"

        puts
        puts "##{item.id} #{item.created_at.to_date} [#{site}] #{item.display_description.to_s.squish.truncate(100)}"
        puts "  lexemes: #{finder.lexemes.join(' ')}"

        matches = finder.matches(min_rank: 0, min_shared: 1, limit: 5)
        puts "  (no candidates)" if matches.empty?
        matches.each do |match|
          hit = match.rank >= min_rank && match.shared_lexemes.size >= DuplicateFinder::MIN_SHARED_LEXEMES
          puts format(
            "  [%s] %.3f #%d %s | shared: %s",
            hit ? "x" : " ",
            match.rank,
            match.item.id,
            match.item.display_description.to_s.squish.truncate(60),
            match.shared_lexemes.join(" ")
          )
        end
      end
    end
  end
end
