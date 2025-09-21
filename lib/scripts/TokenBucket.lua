local key = KEYS[1]
local bucket_capacity = tonumber(ARGV[1])
local refill_rate = tonumber(ARGV[2])
local refill_interval = tonumber(ARGV[3])

local time_data = redis.call('TIME')
local current_time = tonumber(time_data[1]) * 1000000 + tonumber(time_data[2])

local bucket_data = redis.call('HMGET', key, 'tokens', 'last_updated')
local tokens = tonumber(bucket_data[1]) or bucket_capacity
local last_updated = tonumber(bucket_data[2]) or current_time

local elapsed_micros = current_time - last_updated
local elapsed_seconds = elapsed_micros / 1000000
local tokens_to_add = math.floor(elapsed_seconds * refill_rate / refill_interval)
local new_tokens = math.min(bucket_capacity, tokens + tokens_to_add)

if new_tokens > 0 then
redis.call('HMSET', key, 'tokens', new_tokens - 1, 'last_updated', current_time)
redis.call('EXPIRE', key, refill_interval * 2)
return 1
end
return 0