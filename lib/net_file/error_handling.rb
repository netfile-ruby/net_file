# frozen_string_literal: true

module NetFile
  module ErrorHandling
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
        request: parse(faraday_error.response&.dig(:request, :body)),
        response: parse(faraday_error.response_body)
      )
    end

    # Error bodies aren't guaranteed to be JSON (e.g. a gateway's HTML error
    # page), so keep the raw string rather than fail while building the error.
    def parse(body)
      return nil if body.to_s.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end
  end
end
