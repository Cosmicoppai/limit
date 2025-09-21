# frozen_string_literal: true

require "test_helper"

class TestTokenBucket < Minitest::Test
  # Token bucket config:
  # - capacity: 3 tokens
  # - refill_rate: 1 token per second (refill_interval = 1 second)
  LIMITS = { capacity_3_rps1: { bucket_capacity: 3, refill_rate: 1, refill_interval: 1 } }.freeze

  def make_limiter
    calc = lambda do |key|
      plan = key.split(":").last.to_sym rescue :capacity_3_rps1
      LIMITS.fetch(plan, LIMITS[:capacity_3_rps1])
    end

    Limit::TokenBucketRateLimiter.new(identifier_prefix: "tbtest", limit_calculator: calc)
  end

  def unique_key(suffix)
    # Include time to minimize collisions between test runs
    "user_#{suffix}_#{Time.now.to_f}"
  end

  def test_initial_burst_respects_bucket_capacity
    limiter = make_limiter
    key = unique_key("cap") + ":capacity_3_rps1"

    allowed_count = 0
    5.times do
      allowed_count += 1 if limiter.allowed?(key)
    end

    # Capacity is 3, so only 3 should pass initially
    assert_equal 3, allowed_count
  end

  def test_refill_adds_tokens_over_time
    limiter = make_limiter
    key = unique_key("refill") + ":capacity_3_rps1"

    # Exhaust initial capacity of 3
    3.times { assert_equal true, limiter.allowed?(key) }
    assert_equal false, limiter.allowed?(key), "Fourth immediate request should be denied"

    # Wait over 1 second a bit to allow one token to refill
    sleep 1.2

    assert_equal true, limiter.allowed?(key), "One token should be available after ~1s"
    # The next one should still be denied (only one token refilled)
    assert_equal false, limiter.allowed?(key)
  end

  def test_isolation_between_keys
    limiter = make_limiter
    key_a = unique_key("A") + ":capacity_3_rps1"
    key_b = unique_key("B") + ":capacity_3_rps1"

    # Use up all tokens for key_a
    3.times { assert_equal true, limiter.allowed?(key_a) }
    assert_equal false, limiter.allowed?(key_a)

    # key_b should be unaffected and able to use its own capacity
    3.times { assert_equal true, limiter.allowed?(key_b) }
    assert_equal false, limiter.allowed?(key_b)
  end
end
