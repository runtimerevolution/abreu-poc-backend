require 'redis'

REDIS = Redis.new(url: ENV['REDISCLOUD_URL'])
