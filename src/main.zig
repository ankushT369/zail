const std = @import("std");

const wt = @import("watch.zig");
const fp = @import("filepos.zig");
const ct = @import("constants.zig");

const linux = std.os.linux;

pub fn main() !void {
    // Minimal inotify implementation
    var watch = try wt.Watcher.init(ct.file_dir);
    defer watch.deinit();

    // Get file stats
    var conf = try fp.FilePos.init(ct.file_path);

    // Inotify Buffer for reading events
    var inotify_buffer: [wt.inotify_buffer_size]u8 align(8) = undefined;

    var content_buffer: [ct.BUFFER_SIZE]u8 = undefined;

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
                const len = linux.read(watch.inotify_fd, &inotify_buffer, wt.inotify_buffer_size); 

                var ptr: usize = 0;
                while(ptr < len) {
                    const event = @as(*const linux.inotify_event, @alignCast(@ptrCast(&inotify_buffer[ptr])));
                    if (event.mask & (linux.IN.MODIFY | linux.IN.CLOSE_WRITE) != 0) {
                        _ = try conf.readNewContent(&content_buffer);
                    }
                    
                    ptr += @sizeOf(linux.inotify_event) + event.len;
                }
            }
        }
    }

}
