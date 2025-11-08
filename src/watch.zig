const std = @import("std");
const linux = std.os.linux;

pub const inotify_buffer_size = 10 * (@sizeOf(linux.inotify_event) + 256 + 1);
pub const MAX_PATH_LEN = 1024;

// Inotify Buffer for reading events
pub var inotify_buffer: [inotify_buffer_size]u8 align(8) = undefined;

pub const Watcher = struct {
    inotify_fd: i32,
    watch_map: std.AutoHashMap(i32, [:0]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, file_dir: []const u8) !Watcher {
        var ret = linux.inotify_init1(linux.IN.CLOEXEC);
        const inotify_fd: i32 = @intCast(ret);

        var self = Watcher{
            .inotify_fd = inotify_fd,
            .watch_map = std.AutoHashMap(i32, [:0]const u8).init(allocator),
            .allocator = allocator,
        };

        ret = linux.inotify_add_watch(inotify_fd, @ptrCast(file_dir.ptr), linux.IN.MOVED_TO | linux.IN.DELETE | linux.IN.CREATE | linux.IN.MOVED_FROM);
        const wd: i32 = @intCast(ret);

        if (wd >= 0) {
            const stored_path = try self.allocator.allocSentinel(u8, file_dir.len, 0);
            std.mem.copyForwards(u8, stored_path, file_dir);
            try self.watch_map.put(wd, stored_path);
        }        
        
        try self.addWatchRecurrsive(file_dir);

        return self;
    }

    pub fn addWatchRecurrsive(self: *Watcher, path: []const u8) !void {
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
        defer dir.close();

        var buf: [MAX_PATH_LEN]u8 = undefined;

        var iter = dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind == .directory and !std.mem.eql(u8, entry.name, ".") and !std.mem.eql(u8, entry.name, "..")) {
                const next_path = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{path, entry.name}) catch continue;

                const ret = linux.inotify_add_watch(self.inotify_fd, next_path, linux.IN.MOVED_TO | linux.IN.DELETE | linux.IN.CREATE | linux.IN.MOVED_FROM);
                const wd: i32 = @intCast(ret);

                if (wd >= 0) {
                    const stored_path = try self.allocator.allocSentinel(u8, next_path.len, 0);
                    std.mem.copyForwards(u8, stored_path, next_path);
                    try self.watch_map.put(wd, stored_path);
                }

                try self.addWatchRecurrsive(next_path);
            }
            else if (entry.kind == .file) {
                const next_path = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{path, entry.name}) catch continue;

                const ret = linux.inotify_add_watch(self.inotify_fd, next_path, linux.IN.MODIFY | linux.IN.CLOSE_WRITE | linux.IN.MOVE_SELF | linux.IN.DELETE_SELF);
                const wd: i32 = @intCast(ret);

                if (wd >= 0) {
                    const stored_path = try self.allocator.allocSentinel(u8, next_path.len, 0);
                    std.mem.copyForwards(u8, stored_path, next_path);
                    try self.watch_map.put(wd, stored_path);
                }
            }
        }
    }

    pub fn deinit(self: *Watcher) void {
        var it = self.watch_map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        _ = linux.close(self.inotify_fd);
    }

    pub fn getPath(self: *Watcher, wd: i32) ?[:0]const u8 {
        return self.watch_map.get(wd);
    }
};
