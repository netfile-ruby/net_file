# frozen_string_literal: true

require "test_helper"

class TestAuth < Minitest::Test
  CREATE_URL = "https://netfile.com/go/v2/create-bearer-token"
  TEST_URL = "https://netfile.com/go/v2/test-bearer-token"

  def setup
    @auth = NetFile::Auth.new(api_key: "key", api_secret: "secret")
  end

  test "create_token returns token" do
    stub_request(:post, CREATE_URL)
      .with(basic_auth: ["key", "secret"])
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { access_token: "abc", token_type: "Bearer", expires_in: 3600 }.to_json
      )

    token = @auth.create_token

    assert_equal NetFile::Token.new(access_token: "abc", token_type: "Bearer", expires_in: 3600), token
  end

  test "create_token raises authentication error on bad credentials" do
    stub_request(:post, CREATE_URL).to_return(status: 403)

    error = assert_raises(NetFile::AuthenticationError) { @auth.create_token }
    assert_equal CREATE_URL, error.url
    assert_equal 403, error.status
    assert_nil error.request
    assert_nil error.response
  end

  test "create_token raises authentication error on missing credentials" do
    stub_request(:post, CREATE_URL).to_return(status: 401)

    assert_raises(NetFile::AuthenticationError) { @auth.create_token }
  end

  test "create_token raises server error on 5xx" do
    stub_request(:post, CREATE_URL).to_return(
      status: 503,
      headers: { "Content-Type" => "application/json" },
      body: '{"message":"down"}'
    )

    error = assert_raises(NetFile::ServerError) { @auth.create_token }
    assert_equal 503, error.status
    assert_equal '{"message":"down"}', error.response
  end

  test "create_token raises server error on timeout" do
    stub_request(:post, CREATE_URL).to_timeout

    error = assert_raises(NetFile::ServerError) { @auth.create_token }
    assert_equal CREATE_URL, error.url
    assert_nil error.status
  end

  test "create_token raises client error on other failures" do
    stub_request(:post, CREATE_URL).to_return(status: 404)

    error = assert_raises(NetFile::ClientError) { @auth.create_token }
    assert_instance_of NetFile::ClientError, error
  end

  test "test_token returns true for valid token" do
    stub_request(:get, TEST_URL)
      .with(headers: { "Authorization" => "Bearer abc" })
      .to_return(status: 200)

    assert_equal true, @auth.test_token("abc")
  end

  test "test_token raises authentication error for invalid token" do
    stub_request(:get, TEST_URL).to_return(status: 401)

    assert_raises(NetFile::AuthenticationError) { @auth.test_token("bad") }
  end

  test "fetch reuses the token until asked to refresh" do
    responses = %w[t1 t2].map do |token|
      { status: 200, headers: { "Content-Type" => "application/json" },
        body: { access_token: token, token_type: "Bearer", expires_in: 3600 }.to_json }
    end
    stub_request(:post, CREATE_URL).to_return(*responses)

    assert_equal %w[t1 t1 t2], [@auth.fetch, @auth.fetch, @auth.fetch(refresh: true)]
  end
end
