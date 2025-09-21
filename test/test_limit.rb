# frozen_string_literal: true

require "test_helper"

class TestLimit < Minitest::Test
  SITE_LIMITS = {
    x: { max_requests: 10, "window_seconds": 5 }, # 10 req / 5 sec
    y: { max_requests: 100, "window_seconds": 60 }, # 100 req / min
    z: { max_requests: 500, "window_seconds": 3600 }, # 500 req / hour
    default: { max_requests: 10, "window_seconds": 60 },
  }.freeze

  def access_limit_calculator
    lambda do |key| # key:- "user_id:site_name" [example]
      plan = key.split(':').last.to_sym rescue :default
      SITE_LIMITS.fetch(plan, SITE_LIMITS[:default])
    end
  end

  def unique_key(prefix)
    "#{prefix}_#{Time.now.to_f}"
  end

  def sleep_until_next_fixed_window(window_seconds)
    now = Time.now
    remaining = window_seconds - (now.to_i % window_seconds)
    sleep(remaining + 0.5)
  end

  def test_that_it_has_a_version_number
    refute_nil ::Limit::VERSION
  end

  def test_rolling_window_rate_limiter
    rate_limiter = Limit::RollingWindowRateLimiter.new(identifier_prefix: 'access', limit_calculator: access_limit_calculator)

    key = '007:x'
    success_count = 0
    a = Time.now
    11.times do # 11th request will fail
      allowed = rate_limiter.allowed?(key)
      success_count += 1 if allowed
    end

    sleep 5 - (Time.now - a) + 0.5  # wait until the next window
    allowed = rate_limiter.allowed?(key) # request will be allowed
    success_count += 1 if allowed

    assert_equal 11, success_count
  end

  def test_rolling_window_isolation_between_keys
    limiter = Limit::RollingWindowRateLimiter.new(identifier_prefix: 'rw', limit_calculator: access_limit_calculator)
    key_a = unique_key('userA') + ':x'
    key_b = unique_key('userB') + ':x'

    # Use up allowance for key_a
    10.times { assert_equal true, limiter.allowed?(key_a) }
    assert_equal false, limiter.allowed?(key_a)

    # key_b should still have its own allowance
    10.times { assert_equal true, limiter.allowed?(key_b) }
    assert_equal false, limiter.allowed?(key_b)
  end

  def test_rolling_window_different_plans
    limiter = Limit::RollingWindowRateLimiter.new(identifier_prefix: 'rw2', limit_calculator: access_limit_calculator)
    key_small = unique_key('small') + ':x' # 10 per 5s
    key_large = unique_key('large') + ':y' # 100 per 60s

    # a small plan should cap at 10 within the window
    allowed_small = 0
    20.times { allowed_small += 1 if limiter.allowed?(key_small) }
    assert_equal 10, allowed_small

    # a large plan allows far more than 10 immediately
    allowed_large = 0
    20.times { allowed_large += 1 if limiter.allowed?(key_large) }
    assert_operator allowed_large, :>=, 15
  end

  def test_rolling_window_raises_on_invalid_limit_data
    bad_calc = lambda { |_key| { max_requests: 0, window_seconds: -1 } }
    limiter = Limit::RollingWindowRateLimiter.new(identifier_prefix: 'rw3', limit_calculator: bad_calc)
    assert_raises(ArgumentError) { limiter.allowed?(unique_key('bad') + ':x') }
  end

  # FixedWindow tests
  def test_fixed_window_basic_and_reset
    limiter = Limit::FixedWindowRateLimiter.new(identifier_prefix: 'fw', limit_calculator: access_limit_calculator)
    key = unique_key('fwuser') + ':x' # 10 per 5s

    allowed = 0
    12.times { allowed += 1 if limiter.allowed?(key) }
    assert_equal 10, allowed, 'Only 10 should be allowed within the fixed window'

    # Wait until the next aligned fixed window begins
    sleep_until_next_fixed_window(5)

    # After the window reset, should allow again
    10.times { assert_equal true, limiter.allowed?(key) }
  end

  def test_fixed_window_isolation_between_keys
    limiter = Limit::FixedWindowRateLimiter.new(identifier_prefix: 'fw2', limit_calculator: access_limit_calculator)
    key_a = unique_key('A') + ':x'
    key_b = unique_key('B') + ':x'

    10.times { assert_equal true, limiter.allowed?(key_a) }
    assert_equal false, limiter.allowed?(key_a)

    # key_b unaffected
    10.times { assert_equal true, limiter.allowed?(key_b) }
    assert_equal false, limiter.allowed?(key_b)
  end
end
