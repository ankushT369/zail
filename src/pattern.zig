const std = @import("std");
const util = @import("util.zig");
const ct = @import("constants.zig");


pub fn checkExcludedPath(path: []const u8) bool {
    return util.comparePrefixString(path, ct.exclude_path);
}
