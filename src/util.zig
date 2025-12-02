// Utility functions
const std = @import("std");

// String operation utility
pub fn formatPath(buf: []u8, path: []const u8, filename: []const u8) ![:0]u8 {
    return std.fmt.bufPrintZ(buf, "{s}/{s}", .{path, filename});
}

pub fn compareString(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn comparePrefixString(a: []const u8, b: []const u8) bool {
    return std.mem.startsWith(u8, a, b);
}
