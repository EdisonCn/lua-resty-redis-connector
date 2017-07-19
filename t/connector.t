use Test::Nginx::Socket 'no_plan';
use Cwd qw(cwd);

my $pwd = cwd();

our $HttpConfig = qq{
lua_package_path "$pwd/lib/?.lua;;";

init_by_lua_block {
    require("luacov.runner").init()
}
};

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_NGINX_REDIS_PORT} ||= 6379;

no_long_string();
run_tests();

__DATA__

=== TEST 1: basic connect
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua_block {
        local rc = require("resty.redis.connector").new({
            port = $TEST_NGINX_REDIS_PORT
        })

        local redis = assert(rc:connect(params),
            "connect should return positively")

        assert(redis:set("dog", "an animal"),
            "redis:set should return positively")

        redis:close()
    }
}
--- request
GET /t
--- no_error_log
[error]


=== TEST 2: try_hosts
--- http_config eval: $::HttpConfig
--- config
location /t {
    lua_socket_log_errors off;
    content_by_lua_block {
        local rc = require("resty.redis.connector").new({
            connect_timeout = 100,
        })

        local hosts = {
            { host = "127.0.0.1", port = 1 },
            { host = "127.0.0.1", port = 2 },
            { host = "127.0.0.1", port = $TEST_NGINX_REDIS_PORT },
        }

        local redis, err, previous_errors = rc:try_hosts(hosts)
        assert(redis and not err,
            "try_hosts should return a connection and no error")

        assert(previous_errors[1] == "connection refused",
            "previous_errors[1] should be 'connection refused'")
        assert(previous_errors[2] == "connection refused",
            "previous_errors[2] should be 'connection refused'")

        assert(redis:set("dog", "an animal"),
            "redis connection should be working")

        redis:close()

        local hosts = {
            { host = "127.0.0.1", port = 1 },
            { host = "127.0.0.1", port = 2 },
        }

        local redis, err, previous_errors = rc:try_hosts(hosts)
        assert(not redis and err == "no hosts available",
            "no available hosts should return an error")

        assert(previous_errors[1] == "connection refused",
            "previous_errors[1] should be 'connection refused'")
        assert(previous_errors[2] == "connection refused",
            "previous_errors[2] should be 'connection refused'")
    }
}
--- request
GET /t
--- no_error_log
[error]


=== TEST 3: connect_to_host
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua_block {
        local rc = require("resty.redis.connector").new()

        local host = { host = "127.0.0.1", port = $TEST_NGINX_REDIS_PORT }

        local redis, err = rc:connect_to_host(host)
        assert(redis and not err,
            "connect_to_host should return positively")

        assert(redis:set("dog", "an animal"),
            "redis connection should be working")

        redis:close()
    }
}
--- request
GET /t
--- no_error_log
[error]


=== TEST 4: connect_to_host options ignore defaults
--- http_config eval: $::HttpConfig
--- config
location /t {
    content_by_lua_block {
        local rc = require("resty.redis.connector").new({
            port = $TEST_NGINX_REDIS_PORT,
            db = 2,
        })

        local redis, err = assert(rc:connect_to_host({
            host = "127.0.0.1",
            db = 1,
            port = $TEST_NGINX_REDIS_PORT
        }), "connect_to_host should return positively")

        assert(redis:set("dog", "an animal") == "OK",
            "set should return 'OK'")

        redis:select(2)
        assert(redis:get("dog") == ngx.null,
            "dog should not exist in db 2")

        redis:select(1)
        assert(redis:get("dog") == "an animal",
            "dog should be 'an animal' in db 1")

        redis:close()
    }
}
--- request
GET /t
--- no_error_log
[error]


=== TEST 5: Test set_keepalive method
--- http_config eval: $::HttpConfig
--- config
location /t {
    lua_socket_log_errors Off;
    content_by_lua_block {
        local rc = require("resty.redis.connector").new()

        local redis = assert(rc:connect(),
            "rc:connect should return positively")
        local ok, err = rc:set_keepalive(redis)
        assert(not err, "set_keepalive error should be nil")

        local ok, err = redis:set("foo", "bar")
        assert(not ok, "ok should be nil")
        assert(string.find(err, "closed"), "error should contain 'closed'")

        local redis = assert(rc:connect(), "connect should return positively")
        assert(redis:subscribe("channel"), "subscribe should return positively")

        local ok, err = rc:set_keepalive(redis)
        assert(not ok, "ok should be nil")
        assert(string.find(err, "subscribed state"),
            "error should contain 'subscribed state'")

    }
}
--- request
GET /t
--- no_error_log
[error]
