local key = KEYS[1]
local window_seconds = tonumber(ARGV[1])
local max_requests = tonumber(ARGV[2])

local time_data = redis.call('TIME')
local curr_micros = tonumber(time_data[1]) * 1000000 + tonumber(time_data[2])
local window_start_micros = curr_micros - (window_seconds * 1000000)

-- uses sorted set
-- https://redis.io/glossary/redis-sorted-sets/
-- Remove old entries
redis.call('ZREMRANGEBYSCORE', key, 0, window_start_micros)

-- Add current request
redis.call('ZADD', key, curr_micros, tostring(curr_micros))

-- Count requests
local count = redis.call('ZCARD', key)

-- Set expiry
redis.call('EXPIRE', key, window_seconds)

if count <= max_requests then
    return 1
else
    return 0
end

