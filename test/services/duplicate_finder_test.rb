require "test_helper"

class DuplicateFinderTest < ActiveSupport::TestCase
  setup do
    @earlier = Item.create!(
      description: "Cordless power drill, DeWalt, with two batteries",
      created_at: 3.days.ago
    )
    @unrelated = Item.create!(description: "Box of HDMI cables", created_at: 2.days.ago)
  end

  test "matches an earlier item that shares nouns" do
    item = Item.create!(
      description: "Black power drill with battery pack",
      ai_description: "A black cordless drill with a battery pack, in good condition, showing some wear."
    )

    matches = DuplicateFinder.new(item).matches(min_rank: 0)

    assert_includes matches.map(&:item), @earlier
    assert_not_includes matches.map(&:item), @unrelated
    match = matches.find { |m| m.item == @earlier }
    assert_operator match.rank, :>, 0
    assert_includes match.shared_lexemes, "drill"
  end

  test "does not match on vision-model boilerplate alone" do
    Item.create!(description: "Teapot in good condition, shows some wear", created_at: 1.day.ago)
    item = Item.create!(description: "Skateboard in good condition, shows some wear")

    assert_empty DuplicateFinder.new(item).matches(min_rank: 0)
  end

  test "lexemes drop the stoplist" do
    item = Item.new(description: "A drill in good condition, visible wear", created_at: Time.current)

    lexemes = DuplicateFinder.new(item).lexemes

    assert_includes lexemes, "drill"
    assert_empty lexemes & %w[good condit visibl wear]
  end

  test "requires two shared lexemes" do
    item = Item.create!(description: "Drill press stand")

    assert_not_includes DuplicateFinder.new(item).matches(min_rank: 0).map(&:item), @earlier
    assert_includes DuplicateFinder.new(item).matches(min_rank: 0, min_shared: 1).map(&:item), @earlier
  end

  test "applies the rank threshold" do
    item = Item.create!(description: "Cordless power drill with batteries")

    assert_empty DuplicateFinder.new(item).matches(min_rank: 1.1)
  end

  test "excludes the item itself, later items, and items older than the window" do
    old = Item.create!(description: "Cordless power drill with batteries", created_at: 61.days.ago)
    item = Item.create!(description: "Cordless power drill with batteries", created_at: 1.day.ago)
    later = Item.create!(description: "Cordless power drill with batteries")

    found = DuplicateFinder.new(item).matches(min_rank: 0).map(&:item)

    assert_includes found, @earlier
    assert_not_includes found, item
    assert_not_includes found, old
    assert_not_includes found, later
  end

  test "compares lost+found items only with lost+found items" do
    lost = Item.create!(
      description: "Blue insulated water bottle",
      lost_found_state: :lost_found_unclaimed,
      created_at: 2.days.ago
    )
    gunky = Item.create!(description: "Blue insulated water bottle", created_at: 2.days.ago)
    item = Item.create!(description: "Insulated blue water bottle", lost_found_state: :lost_found_unclaimed)

    found = DuplicateFinder.new(item).matches(min_rank: 0).map(&:item)

    assert_includes found, lost
    assert_not_includes found, gunky
  end

  test "gunky items are not compared with lost+found items" do
    lost = Item.create!(
      description: "Blue insulated water bottle",
      lost_found_state: :lost_found_unclaimed,
      created_at: 2.days.ago
    )
    item = Item.create!(description: "Insulated blue water bottle")

    assert_not_includes DuplicateFinder.new(item).matches(min_rank: 0).map(&:item), lost
  end

  test "survives punctuation that is special in tsquery syntax" do
    item = Item.create!(description: "Power drill: it's O'Brien's (batteries & charger) | spare!")

    assert_nothing_raised { DuplicateFinder.new(item).matches(min_rank: 0) }
  end

  test "min_rank reads DUPLICATE_HINT_MIN_RANK and falls back on garbage" do
    original = ENV["DUPLICATE_HINT_MIN_RANK"]
    ENV["DUPLICATE_HINT_MIN_RANK"] = "0.3"
    assert_in_delta 0.3, DuplicateFinder.min_rank
    ENV["DUPLICATE_HINT_MIN_RANK"] = "lots"
    assert_in_delta DuplicateFinder::DEFAULT_MIN_RANK, DuplicateFinder.min_rank
  ensure
    ENV["DUPLICATE_HINT_MIN_RANK"] = original
  end
end
