const std = @import("std");
const wt = @import("watch.zig");
const fp = @import("filetracker.zig");
const ct = @import("constants.zig");
const sig = @import("signal.zig");
const jnl = @import("journal.zig");
const util = @import("util.zig");

const c = @cImport({
    @cInclude("systemd/sd-journal.h");
});
const linux = std.os.linux;

pub fn handleInotifyEvents(watch: *wt.Watcher, tracker: *fp.FileTracker) !void {
    // Read all pending inotify events into the global buffer.
    const len = linux.read(watch.inotify_fd,
        &wt.inotifybuf,
        wt.inotifylen,
    );

    // Walk through the buffer consuming variable-length events.
    var ptr: usize = 0;
    while (ptr < len) {
        const event = @as(
            *const linux.inotify_event,
            @alignCast(@ptrCast(&wt.inotifybuf[ptr])),
        );

        // Only process events matching our mask.
        if (event.mask & ct.MASK != 0) {
            // Look up the directory path associated with this watch descriptor.
            const dir_path = watch.getPath(event.wd).?;

            // Get the file/directory name part.
            const file_name = event.getName().?; // implemented inside watch.zig

            // Construct full path where the event occurred.
            var buffer: [ct.MAX_PATH_LEN]u8 = undefined;
            const full_path = util.formatPath(&buffer, dir_path, file_name) catch {
                return error.PathTooLong;
            };

            // If it's not a file, skip it (optional).
            // const st = std.fs.cwd().statFile(full_path) catch continue;
            // if (st.kind != .file) continue;

            // Get (or create) tracking info for this file.
            const fpos = try tracker.track(full_path);

            // Read only the newly appended part of the file.
            const val = try fpos.readNewContent(&ct.content_buffer);

            // Debug output for now. Replace with real processing soon.
            std.debug.print("val: {s}\n", .{val});
        }

        // Advance to the next inotify event in the buffer.
        ptr += @sizeOf(linux.inotify_event) + event.len;
    }
}

pub fn handleSignalEvents(signal: *sig.Sig) void {
    // later handle
    _ = linux.read(signal.sigfd, sig.sigbuf, sig.siglen);

    if (sig.fdsi.signo == linux.SIG.INT) {
        std.debug.print("Caught SIGINT. Exiting.\n", .{});
    }
    else if (sig.fdsi.signo == linux.SIG.TERM) {
        std.debug.print("Caught SIGTERM. Exiting.\n", .{});
    }

    linux.exit(0);
}

// helper function (later to be updated)
fn jsonEscapeString(str: []const u8) void {
    std.debug.print("\"", .{});
    for (str) |ch| {
        switch (ch) {
            '"' => std.debug.print("\\\"", .{}),
            '\\' => std.debug.print("\\\\", .{}),
            '\x08' => std.debug.print("\\b", .{}),
            '\x0c' => std.debug.print("\\f", .{}),
            '\n' => std.debug.print("\\n", .{}),
            '\r' => std.debug.print("\\r", .{}),
            '\t' => std.debug.print("\\t", .{}),
            else => {
                if (ch < 0x20 or ch == 0x7f) {
                    // ZIG 0.15 FORMAT: no :04, no X width formats
                    std.debug.print("\\u{X}", .{ch});
                } else {
                    std.debug.print("{c}", .{ch});
                }
            },
        }
    }
    std.debug.print("\"", .{});
}

// more clean code needed
pub fn handleJournalEvents(self: *jnl.Journal) void {
    const pr = c.sd_journal_process(@ptrCast(self.journal));

    if (pr == c.SD_JOURNAL_APPEND) {
        while (c.sd_journal_next(@ptrCast(self.journal)) > 0) {
            std.debug.print("\n  {{", .{});

            // timestamp
            var ts: u64 = 0;
            if (c.sd_journal_get_realtime_usec(@ptrCast(self.journal), &ts) >= 0) {
                std.debug.print("\"__REALTIME_TIMESTAMP\": {}", .{ts});
            }

            // fields
            var data_raw: ?*const anyopaque = null;
            var len: usize = 0;

            while (c.sd_journal_enumerate_data(@ptrCast(self.journal), &data_raw, &len) > 0) {
                const buf: [*]const u8 = @ptrCast(data_raw.?);
                const field = buf[0..len];

                if (std.mem.indexOfScalar(u8, field, '=')) |eq_pos| {
                    const key = field[0..eq_pos];
                    const value = field[eq_pos+1..];

                    std.debug.print(", \"{s}\": ", .{key});
                    jsonEscapeString(value);
                }
            }

            std.debug.print("}}\n", .{});
        }
    }
}
