# frozen_string_literal: true

require "test_helper"

class TestProCampaignClient < Minitest::Test
  CREATE_URL = "https://netfile.com/go/v2/create-bearer-token"
  BASE_URL = "https://netfile.com/go/v2/api/pro-campaign-account/ACCT"
  ENTITY_URL = "#{BASE_URL}/upsert/entity"
  ACTIVITY_URL = "#{BASE_URL}/upsert/activity"
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze
  UPSERT_RESPONSE = { "committed" => true, "successCount" => 1, "failureCount" => 0, "items" => [{ "index" => 0, "action" => "Insert", "netFileId" => 11 }] }.freeze

  class FakeTokenProvider
    attr_reader :calls

    def initialize(*tokens)
      @tokens = tokens
      @calls = []
    end

    def fetch(refresh: false)
      @calls << refresh
      @tokens.shift if refresh
      @tokens.first
    end
  end

  def stub_entity(token, status)
    stub_request(:post, ENTITY_URL)
      .with(headers: { "Authorization" => "Bearer #{token}" })
      .to_return(status: status, headers: JSON_HEADERS, body: UPSERT_RESPONSE.to_json)
  end

  def stub_create_token(*tokens)
    responses = tokens.map do |token|
      { status: 200, headers: JSON_HEADERS,
        body: { access_token: token, token_type: "Bearer", expires_in: 3600 }.to_json }
    end
    stub_request(:post, CREATE_URL).to_return(*responses)
  end

  def upsert(client)
    client.upsert_entity("ACCT", { "items" => [] })
  end

  test "upsert_entity posts the payload and returns an upsert response" do
    payload = { "rollbackOnAnyFailure" => false, "items" => [{ "uploadId" => "c-1", "lname" => "Lee" }] }
    stub = stub_request(:post, ENTITY_URL)
      .with(body: payload.to_json, headers: JSON_HEADERS)
      .to_return(status: 200, headers: JSON_HEADERS, body: UPSERT_RESPONSE.to_json)

    result = NetFile::ProCampaign::Client.new(token: "abc").upsert_entity("ACCT", payload)

    assert_requested stub
    assert_equal ENTITY_URL, result.url
    assert_equal 200, result.status
    assert_equal payload, result.request
    assert_equal UPSERT_RESPONSE, result.response
    assert_equal UPSERT_RESPONSE["items"], result.items
    assert result.success?
  end

  test "upsert_activity posts the payload and returns an upsert response" do
    payload = { "items" => [{ "uploadId" => "t-1", "rptType" => "A", "fppcDate" => "2026-11-01", "amount" => 100 }] }
    stub = stub_request(:post, ACTIVITY_URL)
      .with(body: payload.to_json, headers: JSON_HEADERS)
      .to_return(status: 200, headers: JSON_HEADERS, body: UPSERT_RESPONSE.to_json)

    result = NetFile::ProCampaign::Client.new(token: "abc").upsert_activity("ACCT", payload)

    assert_requested stub
    assert_equal ACTIVITY_URL, result.url
    assert_equal UPSERT_RESPONSE, result.response
  end

  test "an uncommitted upsert is not a success" do
    failed = { "committed" => false, "successCount" => 0, "failureCount" => 1,
               "items" => [{ "index" => 0, "action" => "Failed", "errorMessage" => "Validation failed." }] }
    stub_request(:post, ENTITY_URL).to_return(status: 200, headers: JSON_HEADERS, body: failed.to_json)

    result = upsert(NetFile::ProCampaign::Client.new(token: "abc"))

    refute result.success?
    assert_equal "Failed", result.items[0]["action"]
  end

  test "a committed upsert with failed items is not a success" do
    partial = { "committed" => true, "successCount" => 1, "failureCount" => 1,
                "items" => [{ "index" => 0, "action" => "Update" }, { "index" => 1, "action" => "Failed" }] }
    stub_request(:post, ENTITY_URL).to_return(status: 200, headers: JSON_HEADERS, body: partial.to_json)

    refute upsert(NetFile::ProCampaign::Client.new(token: "abc")).success?
  end

  test "a rejected request raises with the parsed request and response" do
    error_body = { "statusCode" => 400, "errors" => { "generalErrors" => ["bad"] } }
    stub_request(:post, ENTITY_URL)
      .to_return(status: 400, headers: { "Content-Type" => "application/problem+json" }, body: error_body.to_json)

    error = assert_raises(NetFile::ClientError) { upsert(NetFile::ProCampaign::Client.new(token: "abc")) }
    assert_equal ENTITY_URL, error.url
    assert_equal 400, error.status
    assert_equal({ "items" => [] }, error.request)
    assert_equal error_body, error.response
  end

  test "a non-JSON error body is kept as a string" do
    stub_request(:post, ENTITY_URL)
      .to_return(status: 502, headers: { "Content-Type" => "text/html" }, body: "<html>Bad Gateway</html>")

    error = assert_raises(NetFile::ServerError) { upsert(NetFile::ProCampaign::Client.new(token: "abc")) }
    assert_equal "<html>Bad Gateway</html>", error.response
  end

  def stub_query(resource, id, items, status: 200)
    stub_request(:get, "#{BASE_URL}/query/#{resource}")
      .with(query: { "filters[0].field" => "id", "filters[0].operator" => "Eq", "filters[0].value" => id.to_s })
      .to_return(status: status, headers: JSON_HEADERS, body: { "items" => items, "totalCount" => items.size }.to_json)
  end

  test "fetch_entity returns the matching record" do
    stub_query("entity", 11, [{ "id" => 11, "lname" => "Lee" }])

    assert_equal({ "id" => 11, "lname" => "Lee" }, NetFile::ProCampaign::Client.new(token: "abc").fetch_entity("ACCT", 11))
  end

  test "fetch_activity returns the matching record" do
    stub_query("activity", 11, [{ "id" => 11, "rptType" => "A" }])

    assert_equal({ "id" => 11, "rptType" => "A" }, NetFile::ProCampaign::Client.new(token: "abc").fetch_activity("ACCT", 11))
  end

  test "fetch returns nil when no record has the id" do
    stub_query("entity", 999, [])

    assert_nil NetFile::ProCampaign::Client.new(token: "abc").fetch_entity("ACCT", 999)
  end

  test "fetch raises with the full url on a rejected query" do
    stub_query("entity", "abc", [], status: 400)

    error = assert_raises(NetFile::ClientError) { NetFile::ProCampaign::Client.new(token: "abc").fetch_entity("ACCT", "abc") }
    assert_equal 400, error.status
    assert_includes error.url, "#{BASE_URL}/query/entity?filters%5B0%5D.field=id"
  end

  test "token raises on 401 without retrying" do
    stub = stub_entity("abc", 401)

    assert_raises(NetFile::AuthenticationError) { upsert(NetFile::ProCampaign::Client.new(token: "abc")) }
    assert_requested stub, times: 1
  end

  test "api key creates a token once and reuses it" do
    create = stub_create_token("t1")
    stub_entity("t1", 200)
    client = NetFile::ProCampaign::Client.new(api_key: "key", api_secret: "secret")

    2.times { upsert(client) }

    assert_requested create, times: 1
  end

  test "api key refreshes the token once on 401" do
    stub_create_token("old", "new")
    stub_entity("old", 401)
    stub_entity("new", 200)
    client = NetFile::ProCampaign::Client.new(api_key: "key", api_secret: "secret")

    assert_equal UPSERT_RESPONSE, upsert(client).response
  end

  test "api key raises when the refreshed token is also rejected" do
    stub_create_token("old", "new")
    stub_entity("old", 401)
    retry_stub = stub_entity("new", 401)
    client = NetFile::ProCampaign::Client.new(api_key: "key", api_secret: "secret")

    assert_raises(NetFile::AuthenticationError) { upsert(client) }
    assert_requested retry_stub, times: 1
  end

  test "token provider is asked to refresh once on 401" do
    stub_entity("old", 401)
    stub_entity("new", 200)
    provider = FakeTokenProvider.new("old", "new")
    client = NetFile::ProCampaign::Client.new(token_provider: provider)

    assert_equal UPSERT_RESPONSE, upsert(client).response
    assert_equal [false, true], provider.calls
  end

  test "403 is not retried" do
    stub = stub_entity("old", 403)
    provider = FakeTokenProvider.new("old", "new")
    client = NetFile::ProCampaign::Client.new(token_provider: provider)

    assert_raises(NetFile::AuthenticationError) { upsert(client) }
    assert_requested stub, times: 1
    assert_equal [false], provider.calls
  end

  test "requires exactly one way to authenticate" do
    assert_raises(ArgumentError) { NetFile::ProCampaign::Client.new }
    assert_raises(ArgumentError) { NetFile::ProCampaign::Client.new(api_key: "key") }
    assert_raises(ArgumentError) { NetFile::ProCampaign::Client.new(token: "abc", token_provider: Object.new) }
  end
end
