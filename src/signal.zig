const std = @import("std");
const linux = std.os.linux;

pub var fdsi: linux.signalfd_siginfo = undefined;
pub const sigbuf = @as([*]u8, @ptrCast(&fdsi));
pub const siglen = @sizeOf(linux.signalfd_siginfo);

pub const Sig = struct {
    sigfd: i32,

    pub fn init() !Sig {
        var mask: linux.sigset_t = linux.sigemptyset();
        linux.sigaddset(&mask, linux.SIG.INT);
        linux.sigaddset(&mask, linux.SIG.TERM);

        _ = linux.sigprocmask(linux.SIG.BLOCK, &mask, null);

        const sigfd = linux.signalfd(-1, &mask, linux.SFD.NONBLOCK | linux.SFD.CLOEXEC);

        return .{
            .sigfd = @intCast(sigfd),
        };
    }

    pub fn deinit(self: *Sig) void {
        _ = linux.close(self.sigfd);
    }
};
