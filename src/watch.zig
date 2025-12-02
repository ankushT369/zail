const std = @import("std");
const ct = @import("constants.zig");
const util = @import("util.zig");
const pat = @import("pattern.zig");

const linux = std.os.linux;
const fs = std.fs;

// Size of temporary buffer used to read inotify events.
pub const inotifylen = 10 * (@sizeOf(linux.inotify_event) + 256 + 1);

// Max temp path size used when joining directory names during recursion.
pub const MAX_PATH_LEN = 1024;

// Inotify buffer used for reading events from the inotify fd.
pub var inotifybuf: [inotifylen]u8 align(8) = undefined;

/// Basic wrapper around an inotify instance. 
/// Keeps track of watch descriptors and the paths they correspond to.
/// The map owns the stored path strings (allocator-owned null-terminated slices).
pub const Watcher = struct {
    inotify_fd: i32,
 
    // Maps the watch descriptor → null-terminated path string. 
    // We store paths because inotify only gives us the WD back on events.
    watch_map: std.AutoHashMap(i32, [:0]const u8),

    // General purpose allocator for watcher struct.
    allocator: std.mem.Allocator,

    /// Initialize an inotify instance and register a recursive watch
    /// on the given path. The Watcher takes ownership of stored paths.
    pub fn init(allocator: std.mem.Allocator, file_dir: []const u8) !Watcher {
        var ret = linux.inotify_init1(linux.IN.CLOEXEC);
        const inotify_fd: i32 = @intCast(ret);

        var self = Watcher{
            .inotify_fd = inotify_fd,
            .watch_map = std.AutoHashMap(i32, [:0]const u8).init(allocator),
            .allocator = allocator,
        };

        ret = linux.inotify_add_watch(inotify_fd, @ptrCast(file_dir.ptr), ct.MASK); 
        const wd: i32 = @intCast(ret);

        try self.store(wd, file_dir);
        try self.addWatchRecurrsive(file_dir);

        return self;
    }

    /// Free all stored path strings and close the inotify fd.
    /// After calling this, the Watcher must not be used.
    pub fn deinit(self: *Watcher) void {
        var it = self.watch_map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        _ = linux.close(self.inotify_fd);
    }

    // Helper to check whether a directory entry name is not "." or "..".
    // Zig prefers simple helpers for readability instead of inline comparisons.j
    fn is_equal(name: []const u8) bool {
         return !std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..");
    }

    /// Store a watch descriptor → path mapping.
    /// Allocates and duplicates the given path, storing a null-terminated slice.
    /// No-op if wd is negative (invalid WD returned by inotify).
    fn store(self: *Watcher, wd: i32, path: []const u8) !void {
        if (wd >= 0) {
            const stored_path = try self.allocator.allocSentinel(u8, path.len, 0);
            std.mem.copyForwards(u8, stored_path, path);
            try self.watch_map.put(wd, stored_path);
        }
    }

    /// Recursively walk the directory tree starting at `path`
    /// and add inotify watches for every subdirectory.
    /// Errors while scanning a particular directory entry are ignored,
    /// allowing traversal to continue.
    fn addWatchRecurrsive(self: *Watcher, path: []const u8) !void {
        var dir = fs.cwd().openDir(path, .{ .iterate = true }) catch return;
        defer dir.close();

        var buf: [MAX_PATH_LEN]u8 = undefined;

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind == .directory and is_equal(entry.name)) {
                const next_path = util.formatPath(&buf, path, entry.name) catch continue;

                if (pat.checkExcludedPath(next_path)) continue;

                const ret = linux.inotify_add_watch(self.inotify_fd, next_path.ptr, ct.MASK);
                if (ret >= std.math.maxInt(i32)) continue;

                const wd: i32 = @intCast(ret);
                const _path: []const u8 = next_path[0..next_path.len];

                try self.store(wd, _path);
                try self.addWatchRecurrsive(next_path);
            }
        }
    }

    /// Look up the path associated with a watch descriptor.
    /// Returns null if the descriptor is not known.
    pub fn getPath(self: *Watcher, wd: i32) ?[:0]const u8 {
        return self.watch_map.get(wd);
    }
};
