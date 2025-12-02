const std = @import("std");
const ct = @import("constants.zig");

const linux = std.os.linux;

pub const Evl = struct {
    epfd: i32,
    events: [ct.MAX_EVENTS]linux.epoll_event,

    // Create the epoll instance used to wait on the inotify fd.
    // Storage for incoming events from epoll_wait and
    // register the inotify fd so epoll notifies us when something changes.
    pub fn init() !Evl {
        // TODO: Handle Error
        const epfd = linux.epoll_create1(linux.EPOLL.CLOEXEC);
        const epollfd: i32 = @intCast(epfd);

        return .{
            .epfd = epollfd,
            .events = undefined,
        };
    }

    pub fn add(self: *Evl, fd: i32) void {
        //const events: [ct.MAX_EVENTS]linux.epoll_event = undefined;
        var ev: linux.epoll_event = .{
            .events = linux.EPOLL.IN,
            .data = .{ .fd = fd },
        };

        // TODO: Handle Error
        _ = linux.epoll_ctl(self.epfd, linux.EPOLL.CTL_ADD, fd, &ev);
    }

    pub fn deinit(self: *Evl) void {
        _ = linux.close(self.epfd);
    }

    pub fn wait(self: *Evl) usize {
        // `-1` means “block forever”.
        return linux.epoll_wait(self.epfd, &self.events, ct.MAX_EVENTS, -1);
    }

    pub fn iter(self: *Evl, count: usize) []linux.epoll_event {
        return self.events[0..count];
    }
};
