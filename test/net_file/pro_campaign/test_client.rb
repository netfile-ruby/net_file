# frozen_string_literal: true

require "test_helper"

class TestProCampaignClient < Minitest::Test
  CREATE_URL = "https://netfile.com/go/v2/create-bearer-token"
  BASE_URL = "https://netfile.com/go/v2/api/pro-campaign-account/ACCT"
  ENTITY_URL = "#{BASE_URL}/upsert/entity"
  ACTIVITY_URL = "#{BASE_URL}/upsert/activity"
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze
  UPSERT_RESPONSE = { "committed" => true, "successCount" => 1, "failureCount" => 0, "items" => [] }.freeze

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

  test "upsert_entity posts the payload and returns the parsed response" do
    payload = { "rollbackOnAnyFailure" => false, "items" => [{ "uploadId" => "c-1", "lname" => "Lee" }] }
    stub = stub_request(:post, ENTITY_URL)
      .with(body: payload.to_json, headers: JSON_HEADERS)
      .to_return(status: 200, headers: JSON_HEADERS, body: UPSERT_RESPONSE.to_json)

    result = NetFile::ProCampaign::Client.new(token: "abc").upsert_entity("ACCT", payload)

    assert_equal UPSERT_RESPONSE, result
    assert_requested stub
  end

  test "upsert_activity posts the payload and returns the parsed response" do
    payload = { "items" => [{ "uploadId" => "t-1", "rptType" => "A", "fppcDate" => "2026-11-01", "amount" => 100 }] }
    stub = stub_request(:post, ACTIVITY_URL)
      .with(body: payload.to_json, headers: JSON_HEADERS)
      .to_return(status: 200, headers: JSON_HEADERS, body: UPSERT_RESPONSE.to_json)

    result = NetFile::ProCampaign::Client.new(token: "abc").upsert_activity("ACCT", payload)

    assert_equal UPSERT_RESPONSE, result
    assert_requested stub
  end

  test "a rejected request raises with the raw request and response" do
    error_body = '{"statusCode":400,"errors":{"generalErrors":["bad"]}}'
    stub_request(:post, ENTITY_URL)
      .to_return(status: 400, headers: { "Content-Type" => "application/problem+json" }, body: error_body)

    error = assert_raises(NetFile::ClientError) { upsert(NetFile::ProCampaign::Client.new(token: "abc")) }
    assert_equal ENTITY_URL, error.url
    assert_equal 400, error.status
    assert_equal '{"items":[]}', error.request
    assert_equal error_body, error.response
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

    assert_equal UPSERT_RESPONSE, upsert(client)
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

    assert_equal UPSERT_RESPONSE, upsert(client)
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
