# frozen_string_literal: true

require "test_helper"

class TestErrors < Minitest::Test
  test "client error has a default message" do
    error = NetFile::ClientError.new

    assert_equal "Error communicating with NetFile", error.message
    assert_kind_of NetFile::Error, error
  end
end
