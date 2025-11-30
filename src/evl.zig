const std = @import("std");
const ct = @import("constants.zig");

const linux = std.os.linux;

pub const Ev = struct {
    epfd: i32,
    events: [ct.MAX_EVENTS]linux.epoll_event,

    // Create the epoll instance used to wait on the inotify fd.
    // Storage for incoming events from epoll_wait and
    // register the inotify fd so epoll notifies us when something changes.
    pub fn init(fd: i32) !Ev {
        // TODO: Handle Error
        const epfd = linux.epoll_create1(linux.EPOLL.CLOEXEC);
        const epollfd: i32 = @intCast(epfd);

        //const events: [ct.MAX_EVENTS]linux.epoll_event = undefined;
        var ev: linux.epoll_event = .{
            .events = linux.EPOLL.IN,
            .data = .{ .fd = fd },
        };

        // TODO: Handle Error
        _ = linux.epoll_ctl(epollfd, linux.EPOLL.CTL_ADD, fd, &ev);

        return .{
            .epfd = epollfd,
            .events = undefined,
        };
    }

    pub fn deinit(self: *Ev) void {
        _ = linux.close(self.epfd);
    }

    pub fn wait(self: *Ev) usize {
        // `-1` means “block forever”.
        return linux.epoll_wait(self.epfd, &self.events, ct.MAX_EVENTS, -1);
    }

    pub fn iter(self: *Ev, count: usize) []linux.epoll_event {
        return self.events[0..count];
    }
};

