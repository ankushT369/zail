// constants
const std = @import("std");
const linux = std.os.linux;

pub const file_path = "/var/log/syslog";
pub const dir = "/var/log";
pub const MIN_BUFFER_SIZE = 262144;
pub const BUFFER_SIZE = 1048576;
pub const MAX_EVENTS = 1000;
pub const MAX_PATH_LEN = 1024;

pub var content_buffer: [BUFFER_SIZE]u8 = undefined;

pub const CACHE_SIZE: usize = 100;

pub const MASK = (linux.IN.MOVED_TO | linux.IN.DELETE | linux.IN.CREATE | linux.IN.MOVED_FROM | linux.IN.MODIFY | linux.IN.CLOSE_WRITE | linux.IN.MOVE_SELF | linux.IN.DELETE_SELF);
