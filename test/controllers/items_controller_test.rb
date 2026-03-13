require "test_helper"

class ItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @item = items(:pending_item)
  end

  # Index

  test "index returns success" do
    get items_path
    assert_response :success
  end

  test "index filters by disposition" do
    get items_path(disposition: "pending")
    assert_response :success
  end

  test "index shows all dispositions without filter" do
    get items_path
    assert_response :success
    assert_select "a.nav-link", text: "All"
  end

  test "index shows winner actions for mine item" do
    item = Item.create!(
      description: "Desk lamp",
      disposition: :mine,
      claimed_by: "alice",
      expiration_date: Date.current - 1.day
    )
    item.votes.create!(slack_user_id: "U111", slack_username: "alice", choice: :mine)
    item.votes.create!(slack_user_id: "U222", slack_username: "bob", choice: :mine)

    get items_path

    assert_response :success
    assert_select "h6", text: "Winners"
    assert_select "form[action='#{winner_forfeit_item_path(item, slack_user_id: "U111")}']"
    assert_select "form[action='#{winner_picked_up_item_path(item, slack_user_id: "U111")}']"
    assert_select "form[action='#{winner_forfeit_item_path(item, slack_user_id: "U222")}']"
    assert_select "form[action='#{winner_picked_up_item_path(item, slack_user_id: "U222")}']"
  end

  # Show

  test "show returns success" do
    get item_path(@item)
    assert_response :success
  end

  test "show displays item description" do
    get item_path(@item)
    assert_select "h1", @item.description
  end

  test "show displays vote summary for item with votes" do
    get item_path(@item)
    assert_response :success
  end

  test "show displays resolve form for pending item" do
    get item_path(@item)
    assert_select "select[name='disposition']"
  end

  test "show hides resolve form for non-pending item" do
    get item_path(items(:claimed_item))
    assert_select "select[name='disposition']", count: 0
  end

  # New

  test "new returns success" do
    get new_item_path
    assert_response :success
  end

  test "new renders form" do
    get new_item_path
    assert_select "form"
    assert_select "textarea[name='item[description]']"
  end

  # Create

  test "create with valid params creates item" do
    assert_difference "Item.count", 1 do
      post items_path, params: { item: { description: "New junk", location: "Hallway" } }
    end
    assert_redirected_to item_path(Item.last)
    assert_equal "Item was successfully created.", flash[:notice]
  end

  test "create allows blank description when pre-uploaded signed photo is provided" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake image bytes"),
      filename: "item.jpg",
      content_type: "image/jpeg"
    )

    assert_difference "Item.count", 1 do
      post items_path, params: { item: { description: "", photo: blob.signed_id } }
    end

    created_item = Item.last
    assert created_item.photo.attached?
    assert_redirected_to item_path(created_item)
  end

  test "create sets default expiration" do
    post items_path, params: { item: { description: "New junk" } }
    assert_equal 7.days.from_now.to_date, Item.last.expiration_date
  end

  test "create with invalid params renders new" do
    assert_no_difference "Item.count" do
      post items_path, params: { item: { description: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "create does not enqueue slack job when token is blank" do
    assert_no_enqueued_jobs(only: PostToSlackJob) do
      post items_path, params: { item: { description: "No slack" } }
    end
  end

  test "create enqueues slack job when token is present" do
    ENV["SLACK_BOT_TOKEN"] = "xoxb-test"
    assert_enqueued_with(job: PostToSlackJob) do
      post items_path, params: { item: { description: "Post me" } }
    end
  ensure
    ENV["SLACK_BOT_TOKEN"] = nil
  end

  # Edit

  # Preview description

  test "preview_description uploads photo and returns AI description" do
    file = Tempfile.new([ "item-photo", ".jpg" ])
    file.binmode
    file.write("fake image bytes")
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "image/jpeg", true, original_filename: "item.jpg")

    with_overridden_class_method(AgentSetting, :enabled?, -> { true }) do
      with_overridden_instance_method(OllamaService, :describe_image, ->(_blob) { "AI found a red toolbox." }) do
        post preview_description_items_path, params: { photo: upload }
      end
    end

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal "AI found a red toolbox.", payload["description"]
    assert payload["signed_id"].present?
    assert ActiveStorage::Blob.find_signed(payload["signed_id"]).present?
  ensure
    file&.close
    file&.unlink
  end

  test "preview_description returns error without photo" do
    post preview_description_items_path

    assert_response :unprocessable_entity
    assert_equal "Photo is required.", JSON.parse(response.body)["error"]
  end

  test "preview_description uploads photo when AI disabled" do
    file = Tempfile.new([ "item-photo", ".jpg" ])
    file.binmode
    file.write("fake image bytes")
    file.rewind

    upload = Rack::Test::UploadedFile.new(file.path, "image/jpeg", true, original_filename: "item.jpg")

    with_overridden_class_method(AgentSetting, :enabled?, -> { false }) do
      post preview_description_items_path, params: { photo: upload }
    end

    assert_response :success
    payload = JSON.parse(response.body)
    assert_nil payload["description"]
    assert payload["signed_id"].present?
  ensure
    file&.close
    file&.unlink
  end

  test "edit returns success" do
    get edit_item_path(@item)
    assert_response :success
  end

  # Update

  test "update with valid params updates item" do
    patch item_path(@item), params: { item: { description: "Updated description" } }
    assert_redirected_to item_path(@item)
    assert_equal "Updated description", @item.reload.description
  end

  test "update with invalid params renders edit" do
    patch item_path(@item), params: { item: { description: "" } }
    assert_response :unprocessable_entity
  end

  # Destroy

  test "destroy deletes item" do
    assert_difference "Item.count", -1 do
      delete item_path(@item)
    end
    assert_redirected_to items_path
  end

  # Resolve

  test "resolve sets disposition to mine with claimed_by" do
    patch resolve_item_path(@item), params: { disposition: "mine", claimed_by: "charlie" }
    @item.reload
    assert @item.mine?
    assert_equal "charlie", @item.claimed_by
    assert_redirected_to item_path(@item)
  end

  test "resolve sets disposition to foster" do
    patch resolve_item_path(@item), params: { disposition: "foster" }
    assert @item.reload.foster?
  end

  test "resolve sets disposition to kill" do
    patch resolve_item_path(@item), params: { disposition: "kill" }
    assert @item.reload.kill?
  end

  test "resolve rejects invalid disposition" do
    patch resolve_item_path(@item), params: { disposition: "bogus" }
    assert_redirected_to item_path(@item)
    assert_equal "Invalid disposition.", flash[:alert]
    assert @item.reload.pending?
  end

  test "winner_forfeit removes mine winner and falls back to foster when no mine remains" do
    item = Item.create!(
      description: "Shelf",
      disposition: :mine,
      claimed_by: "alice",
      expiration_date: Date.current - 1.day,
      slack_channel_id: "C123",
      slack_message_ts: "111.222"
    )
    item.votes.create!(slack_user_id: "U111", slack_username: "alice", choice: :mine)
    item.votes.create!(slack_user_id: "U222", slack_username: "bob", choice: :foster)

    repost_called = false
    original = SlackService.instance_method(:replace_expired_item_message)
    SlackService.define_method(:replace_expired_item_message) { |_| repost_called = true }

    post winner_forfeit_item_path(item), params: { slack_user_id: "U111" }

    assert_redirected_to items_path
    assert repost_called
    assert_nil item.votes.find_by(slack_user_id: "U111", choice: :mine)
    assert item.reload.foster?
  ensure
    SlackService.define_method(:replace_expired_item_message, original)
  end

  test "winner_forfeit promotes next mine winner when available" do
    item = Item.create!(
      description: "Camera",
      disposition: :mine,
      claimed_by: "alice",
      expiration_date: Date.current - 1.day
    )
    item.votes.create!(slack_user_id: "U111", slack_username: "alice", choice: :mine)
    item.votes.create!(slack_user_id: "U222", slack_username: "bob", choice: :mine)

    post winner_forfeit_item_path(item), params: { slack_user_id: "U111" }

    assert_redirected_to items_path
    item.reload
    assert item.mine?
    assert_equal "bob", item.claimed_by
  end

  test "winner_picked_up marks selected winner as claimed_by" do
    item = Item.create!(
      description: "Toolbox",
      disposition: :mine,
      claimed_by: "alice",
      expiration_date: Date.current - 1.day
    )
    item.votes.create!(slack_user_id: "U111", slack_username: "alice", choice: :mine)
    item.votes.create!(slack_user_id: "U222", slack_username: "bob", choice: :mine)

    post winner_picked_up_item_path(item), params: { slack_user_id: "U222" }

    assert_redirected_to items_path
    item.reload
    assert item.mine?
    assert_equal "bob", item.claimed_by
  end

  private

  def with_overridden_class_method(klass, method_name, replacement)
    original_method = klass.method(method_name)
    klass.define_singleton_method(method_name, &replacement)
    yield
  ensure
    klass.define_singleton_method(method_name, original_method)
  end

  def with_overridden_instance_method(klass, method_name, replacement)
    original_method = klass.instance_method(method_name)
    klass.define_method(method_name, &replacement)
    yield
  ensure
    klass.define_method(method_name, original_method)
  end
end
