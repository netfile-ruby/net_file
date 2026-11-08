# NetFile

A thin Ruby client for NetFile's v2 APIs. It currently covers authentication and the parts of the Pro Campaign Account API needed to write and read entities and transactions (activities).

The client is deliberately a light wrapper around the HTTP endpoints: payloads go to NetFile as-is, and responses come back as parsed hashes (wrapped in a small response object for writes). Mapping your data to NetFile's fields, and deciding what to do with the results, is left to the calling app.

## Installation

The gem isn't published yet. Point your Gemfile to GitHub:

```ruby
gem "net_file", github: "netfile-ruby/net_file"
```

## Quick Start

```ruby
require "net_file"

client = NetFile::ProCampaign::Client.new(api_key: "123", api_secret: "ABC")

result = client.upsert_entity("ACCOUNT", {
  "items" => [{ "uploadId" => "entity-42", "fname" => "Ada", "lname" => "Lee", "city" => "Fresno" }]
})

# check this to confirm the action completed - the API can return 200 and still not
# actually do anything
result.success?                 # => true
result.items[0]["action"]       # => "Insert"
result.items[0]["netFileId"]    # => 11

client.fetch_entity("ACCOUNT", 11)
# => {"id" => 11, "fname" => "Ada", "lname" => "Lee", "city" => "Fresno", ...}

result = client.upsert_activity("ACCOUNT", {
  "items" => [{
    "uploadId" => "txn-7", "rptType" => "A", "entityId" => 11,
    "bankAccount" => -2, "fppcDate" => "2026-11-07", "amount" => 25
  }]
})

if (result.success?)
  result.items[0]["netFileId"]    # => 12

  client.fetch_activity("ACCOUNT", 12)
  # => {"id" => 12, "amount" => 25, ...}
end
```

## Usage

```ruby
require "net_file"
```

### Authentication

Generate an API key and secret in NetFile's "API Keys" menu. `NetFile::Auth` exchanges them for a bearer token, which (currently) expires after an hour. Check `expires_in` to be sure, as this might change in the future:

```ruby
auth = NetFile::Auth.new(api_key: "...", api_secret: "...")

token = auth.create_token  # => NetFile::Token
token.access_token         # => "eyJhbGciOi..."
token.expires_in           # => 3600

auth.test_token(token.access_token)  # => true
```

You can use this to create a token manually, or let the client do this for you behind the scenes (see "Creating a client" below)

### Creating a client

`NetFile::ProCampaign::Client` supports three ways to authenticate, depending on your taste.

1. **API key and secret.** The client will fetch the bearer token and keep it in memory as long as the client is alive, getting a new one if NetFile rejects it with a 401.

```ruby
client = NetFile::ProCampaign::Client.new(api_key: "...", api_secret: "...")
```

Pros: simplest option

Cons: tokens are good for an hour, so if you're creating lots of client instances (e.g. because of multiple background jobs), this will degrade performance as you'll be doing lots of unnecessary round-trips to NetFile

2. **A bearer token.** You create the token, then pass it to the client, which uses it as-is. If NetFile rejects it, the client raises `NetFile::AuthenticationError`:

```ruby
client = NetFile::ProCampaign::Client.new(token: "eyJhbGciOi...")
```

Pros: makes it easy to re-use tokens

Cons: have to monitor for `AuthenticationError` and refresh the token as needed

3. **A token provider.** Use this to manage tokens yourself, for example to share one across processes.

The provider must respond to `fetch(refresh: false)` and return an access token string. On a 401, the client calls `fetch(refresh: true)` once and retries; the provider is responsible for getting a new token.

Here's one way you could create a token provider, using the Rails cache to store a shared token:

```ruby
class CachedTokenProvider
  def initialize()
    @auth = NetFile::Auth.new(api_key: "abc", api_secret: "123")
  end

  def fetch(refresh: false)
    Rails.cache.delete("netfile_token") if refresh
    Rails.cache.fetch("netfile_token", expires_in: 55.minutes) do
      @auth.create_token.access_token
    end
  end
end

provider = CachedTokenProvider.new
client = NetFile::ProCampaign::Client.new(token_provider: provider)
```

Pros: token fetches and refreshes happen automatically

Cons: a little more upfront work to set up

### Writing entities and transactions

`upsert_entity` and `upsert_activity` take a campaign account and the request body as NetFile documents it, with string keys and camelCase field names. Each item is matched to an existing record by `id`, then `xid`, then `uploadId`. An `uploadId` that matches nothing inserts a new record.

```ruby
result = client.upsert_entity("ACCOUNT", {
  "items" => [{ "uploadId" => "entity-42", "fname" => "Ada", "lname" => "Lee", "city" => "Fresno" }]
})

result.success?                 # => true
result.items[0]["action"]       # => "Insert"
result.items[0]["netFileId"]    # => 11

client.upsert_activity("ACCOUNT", {
  "items" => [{
    "uploadId" => "txn-7", "rptType" => "A", "entityId" => 11,
    "bankAccount" => -2, "fppcDate" => "2026-11-07", "amount" => 25
  }]
})
```

Both methods return a `NetFile::ProCampaign::UpsertResponse`:

| Method     | Returns                                               |
| ---------- | ----------------------------------------------------- |
| `url`      | the full URL requested                                |
| `status`   | the HTTP status                                       |
| `success?` | true if the status was 200 and every item was written |
| `request`  | the payload you sent                                  |
| `response` | the full parsed response                              |
| `items`    | the response's `items`, one result per item you sent  |

Things to know about writes:

- **Only the fields you send change.** A field you leave out keeps its stored value; sending `null` or `""` clears it.
- **Failed items don't raise.** An upsert returns HTTP 200 even when items fail, so check `success?` and each item's `action` (`"Insert"`, `"Update"` or `"Failed"`), and see `validationResults` for the reasons.
- **One failure rolls back the batch by default.** Send `"rollbackOnAnyFailure" => false` to write every item that succeeds.
- **Use `netFileId` from the response as `id` on later writes.**

### Fetching records

`fetch_entity` and `fetch_activity` look up one record by its NetFile id. They return its non-null fields as a hash, or `nil` if no record has that id:

```ruby
client.fetch_entity("ACCOUNT", 11)
# => {"id" => 11, "fname" => "Ada", "lname" => "Lee", "city" => "Fresno", ...}

client.fetch_activity("ACCOUNT", 999999)  # => nil
```

### Errors

Every error the gem raises inherits from `NetFile::Error`. A failed request raises `NetFile::ClientError` or one of its subclasses:

| Error                          | Raised when                                                     |
| ------------------------------ | --------------------------------------------------------------- |
| `NetFile::AuthenticationError` | NetFile rejects the credentials or token (401 or 403)           |
| `NetFile::ServerError`         | NetFile returns a 5xx, or the connection fails or times out     |
| `NetFile::ClientError`         | any other failed request, such as a 400 for a malformed request |

Each `ClientError` and its subclasses carry details for debugging:

```ruby
begin
  client.upsert_entity("ACCOUNT", payload)
rescue NetFile::ClientError => e
  e.url       # the full URL requested
  e.status    # HTTP status, or nil if no response was received
  e.request   # the request payload as a hash, or nil if none was sent
  e.response  # the parsed response (a string if it isn't JSON), or nil if empty
end
```

## Development

Run `bin/setup` to install dependencies, then `bundle exec rake test` to run
the tests. A coverage report is written to `coverage/index.html`.
