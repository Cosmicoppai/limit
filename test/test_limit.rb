# frozen_string_literal: true

require "test_helper"

class TestLimit < Minitest::Test
  SITE_LIMITS = {
    x: { max_requests: 10, "window_seconds": 5 }, # 10 req / 5 sec
    y: { max_requests: 100, "window_seconds": 60 }, # 100 req / min
    z: { max_requests: 500, "window_seconds": 3600 }, # 500 req / hour
    default: { max_requests: 10, "window_seconds": 60 },
  }.freeze

  def test_that_it_has_a_version_number
    refute_nil ::Limit::VERSION
  end

  def test_rolling_window_rate_limiter

    sync_limit_calculator = lambda do |key| # key:- "user_id:site_name" [example]
      pms_name = key.split(':').last.to_sym
      SITE_LIMITS.fetch(pms_name, :default)
    end

    rate_limiter = RollingWindowRateLimiter.new(identifier_prefix: 'access', limit_calculator: sync_limit_calculator,
                                                host: '127.0.0.1', port: 6379, password: 'abcd1234')

    #----------------------------------------------------------- ❣️

    key = '007:x'
    success_count = 0
    a = Time.now
    11.times do # 11th request will fail
      allowed = rate_limiter.allowed?(key)
      success_count += 1 if allowed
    end

    sleep 5 - (Time.now - a) + 0.5  # wait until next window
    allowed = rate_limiter.allowed?(key) # request will be allowed
    success_count += 1 if allowed

    assert_equal 11, success_count
  end
end
