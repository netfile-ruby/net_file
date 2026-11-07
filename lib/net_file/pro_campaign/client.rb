# frozen_string_literal: true

module NetFile
  module ProCampaign
    # Client for NetFile's Pro Campaign Account API. Authenticate in one of
    # three ways:
    #
    #   Client.new(api_key: "...", api_secret: "...")
    #     Creates a bearer token and keeps it in memory, refreshing it once
    #     when NetFile responds with a 401.
    #
    #   Client.new(token: "...")
    #     Uses the caller's bearer token. A rejected token raises
    #     NetFile::AuthenticationError.
    #
    #   Client.new(token_provider: provider)
    #     Calls provider.fetch for a bearer token, and
    #     provider.fetch(refresh: true) once when NetFile responds with a 401.
    #
    # Endpoint methods take the request body as documented by NetFile
    # (string keys, camelCase field names) and return the parsed response.
    # An upsert returns 200 even when items fail, so callers should check
    # "committed" and each item's "action". The fetch methods return the
    # record's non-null fields as a hash, or nil when no record has the id.
    class Client
      include ErrorHandling

      BASE_URL = "https://netfile.com/go/v2/api/pro-campaign-account"

      def initialize(api_key: nil, api_secret: nil, token: nil, token_provider: nil)
        key_pair = (api_key || api_secret) ? [api_key, api_secret] : nil
        modes = [key_pair, token, token_provider].compact
        if modes.size != 1 || key_pair&.include?(nil)
          raise ArgumentError, "pass api_key and api_secret, token, or token_provider"
        end

        @token = token
        @token_provider = token_provider || (Auth.new(api_key: api_key, api_secret: api_secret) if key_pair)
      end

      def upsert_entity(account, payload)
        request(:post, "#{account}/upsert/entity", body: payload)
      end

      def upsert_activity(account, payload)
        request(:post, "#{account}/upsert/activity", body: payload)
      end

      def fetch_entity(account, id)
        fetch_by_id("#{account}/query/entity", id)
      end

      def fetch_activity(account, id)
        fetch_by_id("#{account}/query/activity", id)
      end

      private

      def fetch_by_id(path, id)
        # NetFile only honors this indexed filter format; others are silently
        # ignored and return every record.
        params = { "filters[0].field" => "id", "filters[0].operator" => "Eq", "filters[0].value" => id.to_s }
        request(:get, path, params: params)["items"].first
      end

      def request(method, path, body: nil, params: nil)
        send_request(method, path, body, params, @token || @token_provider.fetch)
      rescue AuthenticationError => e
        raise unless e.status == 401 && @token_provider

        send_request(method, path, body, params, @token_provider.fetch(refresh: true))
      end

      def send_request(method, path, body, params, token)
        connection = Faraday.new(BASE_URL) do |f|
          f.request :authorization, "Bearer", token
          f.request :json
          # Declared before raise_error so errors carry the raw, unparsed body.
          f.response :json
          f.response :raise_error
        end
        url = "#{BASE_URL}/#{path}"
        url += "?#{URI.encode_www_form(params)}" if params
        with_errors(url, "NetFile rejected the bearer token") do
          connection.run_request(method, path, body, nil) { |req| req.params.update(params) if params }.body
        end
      end
    end
  end
end
