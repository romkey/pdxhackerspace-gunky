ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    def with_overridden_class_method(klass, method_name, replacement)
      original_method = klass.method(method_name)
      klass.define_singleton_method(method_name, &replacement)
      yield
    ensure
      klass.define_singleton_method(method_name, original_method)
    end

    def with_overridden_instance_method(klass, method_name, replacement)
      original_method = klass.instance_method(method_name)
      klass.define_method(method_name, &replacement)
      yield
    ensure
      klass.define_method(method_name, original_method)
    end
  end
end
