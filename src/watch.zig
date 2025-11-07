const std = @import("std");
const linux = std.os.linux;

pub const inotify_buffer_size = 10 * (@sizeOf(linux.inotify_event) + 256 + 1);
pub const MAX_PATH_LEN = 1024;

pub const Watcher = struct {
    inotify_fd: i32,

    pub fn init(file_dir: []const u8) !Watcher {
        const ret = linux.inotify_init1(linux.IN.CLOEXEC);
        const inotify_fd: i32 = @intCast(ret);

        _ = linux.inotify_add_watch(inotify_fd, @ptrCast(file_dir.ptr), linux.IN.MODIFY | linux.IN.CLOSE_WRITE);

        var self = Watcher{
            .inotify_fd = inotify_fd,
        };

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
                _ = linux.inotify_add_watch(self.inotify_fd, next_path, linux.IN.MODIFY | linux.IN.CLOSE_WRITE);
                try self.addWatchRecurrsive(next_path);
            }
        }
    }

    pub fn deinit(self: *Watcher) void {
        _ = linux.close(self.inotify_fd);
    }
};
