# frozen_string_literal: true

module NetFile
  class Error < StandardError; end

  class ClientError < Error
    attr_reader :url, :status, :request, :response

    def initialize(message: "Error communicating with NetFile", url: nil, status: nil, request: nil, response: nil)
      super(message)
      @url = url
      @status = status
      @request = request
      @response = response
    end
  end

  class AuthenticationError < ClientError; end
  class ServerError < ClientError; end
end
