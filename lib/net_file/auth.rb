# frozen_string_literal: true

module NetFile
  # Obtains and verifies bearer tokens for the NetFile v2 APIs, using an API key
  # and secret generated in NetFile's "API Keys" menu.
  #
  #   auth = NetFile::Auth.new(api_key: "...", api_secret: "...")
  #   token = auth.create_token            # => NetFile::Token
  #   auth.test_token(token.access_token)  # => true
  #
  # Tokens expire after `token.expires_in` seconds (currently 3600). Refreshing
  # them is left to the caller.
  #
  # Both methods raise a NetFile::ClientError (carrying url, status, request
  # and response) or one of its subclasses:
  # - NetFile::AuthenticationError when NetFile rejects the credentials or token
  # - NetFile::ServerError on a 5xx, connection failure, or timeout
  # - NetFile::ClientError on any other failed response
  class Auth
    BASE_URL = "https://netfile.com/go/v2"

    def initialize(api_key:, api_secret:)
      @api_key = api_key
      @api_secret = api_secret
    end

    def create_token
      connection = Faraday.new(BASE_URL) do |f|
        f.request :authorization, :basic, @api_key, @api_secret
        # Declared before raise_error so errors carry the raw, unparsed body.
        f.response :json
        f.response :raise_error
      end
      body = with_errors("#{BASE_URL}/create-bearer-token", "NetFile rejected the API key or secret") do
        connection.post("create-bearer-token").body
      end
      Token.new(
        access_token: body["access_token"],
        token_type: body["token_type"],
        expires_in: body["expires_in"]
      )
    end

    def test_token(token)
      connection = Faraday.new(BASE_URL) do |f|
        f.request :authorization, "Bearer", token
        f.response :raise_error
      end
      with_errors("#{BASE_URL}/test-bearer-token", "NetFile rejected the bearer token") do
        connection.get("test-bearer-token")
      end
      true
    end

    private

    def with_errors(url, auth_message)
      yield
    rescue Faraday::UnauthorizedError, Faraday::ForbiddenError => e
      raise client_error(AuthenticationError, e, url, "#{auth_message} (#{e.response_status})")
    rescue Faraday::ServerError, Faraday::ConnectionFailed, Faraday::TimeoutError => e
      raise client_error(ServerError, e, url, "NetFile request failed: #{e.message}")
    rescue Faraday::Error => e
      raise client_error(ClientError, e, url, "NetFile request failed: #{e.message}")
    end

    def client_error(error_class, faraday_error, url, message)
      error_class.new(
        message: message,
        url: url,
        status: faraday_error.response_status,
        request: presence(faraday_error.response&.dig(:request, :body)),
        response: presence(faraday_error.response_body)
      )
    end

    def presence(value)
      value unless value.to_s.empty?
    end
  end
end
