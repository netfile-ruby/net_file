# frozen_string_literal: true

require "simplecov"
SimpleCov.start { skip "/test/" }

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "net_file"

require "minitest/autorun"
require "webmock/minitest"

# WebMock's default notation rewrites keys like "filters[0].field" and collapses repeated keys.
WebMock::Config.instance.query_values_notation = :flat_array

class Minitest::Test
  def self.test(name, &block)
    method_name = "test_#{name.gsub(/\s+/, "_")}"
    raise "#{method_name} is already defined in #{self}" if method_defined?(method_name)

    define_method(method_name, &block)
  end
end
