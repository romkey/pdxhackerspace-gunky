require "test_helper"

class ItemsHelperTest < ActionView::TestCase
  test "disposition_label maps internal values to display labels" do
    assert_equal "Want", disposition_label("mine")
    assert_equal "Keep", disposition_label("foster")
    assert_equal "Trash", disposition_label("kill")
    assert_equal "Pending", disposition_label("pending")
  end

  test "item_disposition_label shows Owned for cancelled items with owner" do
    item = items(:owned_item)

    assert_equal "Owned", item_disposition_label(item)
  end

  test "pending_vote_counts_line summarizes want keep and trash votes" do
    item = items(:pending_item)

    assert_equal "Want: 1 · Keep: 1 · Trash: 0", pending_vote_counts_line(item)
  end

  test "pending_vote_counts_line returns nil for non-pending items" do
    assert_nil pending_vote_counts_line(items(:claimed_item))
  end
end
