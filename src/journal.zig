const std = @import("std");
const c = @cImport({
    @cInclude("systemd/sd-journal.h");
});

const linux = std.os.linux;


pub const Journal = struct {
    journal: ?*c.sd_journal = null,
    jfd: i32,

    pub fn init() !Journal {
        var j: ?*c.sd_journal = null;
        _ = c.sd_journal_open(&j, c.SD_JOURNAL_LOCAL_ONLY);

        _ = c.sd_journal_seek_tail(j);
        _ = c.sd_journal_next(j);

        return .{
            .journal = j,
            .jfd = c.sd_journal_get_fd(j),
        };
    }

    pub fn deinit(self: *Journal) void {
        _ = linux.close(self.jfd);
    }
};
