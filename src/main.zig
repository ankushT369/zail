const std = @import("std");

// This module contains inotify watch instance
const wt = @import("watch.zig");
// Handles the file parsing positions
const fp = @import("filetracker.zig");
// Contains all the predefined constant values
const ct = @import("constants.zig");

const linux = std.os.linux;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create an watch instance initialized with directory path
    var watch = try wt.Watcher.init(allocator, ct.dir);
    defer watch.deinit();

    // Later to be improved
    var tracker = try fp.FileTracker.init(ct.file_path);
    defer tracker.deinit();

    // Epoll configuration
    const epfd = linux.epoll_create1(linux.EPOLL.CLOEXEC);
    const epollfd: i32 = @intCast(epfd);

    var events: [ct.MAX_EVENTS]linux.epoll_event = undefined;
    var ev: linux.epoll_event = undefined;

    ev.events = linux.EPOLL.IN;
    ev.data.fd = watch.inotify_fd;
    _ = linux.epoll_ctl(epollfd, linux.EPOLL.CTL_ADD, watch.inotify_fd, &ev);

    // Event-loop
    while(true) {
        const ready = linux.epoll_wait(epollfd, &events, ct.MAX_EVENTS, -1);

        for (events[0..ready]) |evt| {
            if (evt.data.fd == watch.inotify_fd) {
                const len = linux.read(watch.inotify_fd, &wt.inotify_buffer, wt.inotify_buffer_size); 

                var ptr: usize = 0;
                while(ptr < len) {
                    const event = @as(*const linux.inotify_event, @alignCast(@ptrCast(&wt.inotify_buffer[ptr])));
                    if (event.mask & (linux.IN.MOVED_TO | linux.IN.DELETE | linux.IN.CREATE | linux.IN.MOVED_FROM | linux.IN.MODIFY | linux.IN.CLOSE_WRITE | linux.IN.MOVE_SELF | linux.IN.DELETE_SELF) != 0) {
                        _ = try tracker.readNewContent(&ct.content_buffer);
                    }
                    
                    ptr += @sizeOf(linux.inotify_event) + event.len;
                }
            }
        }
    }

}
