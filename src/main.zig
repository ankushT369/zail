// Inotify watcher: responsible for recursive directory watches.
// File position tracker: tracks append-only reads on multiple files.
// Constants (paths, masks, buffer sizes, epoll config, etc.)
const std = @import("std");
const wt = @import("watch.zig");
const fp = @import("filetracker.zig");
const ct = @import("constants.zig");
const util = @import("util.zig");
const evl = @import("evl.zig");
const sig = @import("signal.zig");
const evnt = @import("event.zig");
const j = @import("journal.zig");

const linux = std.os.linux;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Initialize the inotify watcher with the root directory to monitor.
    // This sets up all recursive watches immediately.
    var watch = try wt.Watcher.init(allocator, ct.dir);
    defer watch.deinit();

    // Tracks file offsets so we only read newly appended content.
    // Each file gets a FilePos that persists for the program lifetime.
    var tracker = try fp.FileTracker.init(allocator);
    defer tracker.deinit();

    // Journal file descriptor
    var jnl = try j.Journal.init();
    defer jnl.deinit();

    // Signal configuration
    var signal = try sig.Sig.init();
    defer signal.deinit();

    // Epoll configuration
    var evloop = try evl.Evl.init();
    defer evloop.deinit();

    evloop.add(watch.inotify_fd);
    evloop.add(signal.sigfd);
    evloop.add(jnl.jfd);

    // Event loop
    // This loop runs forever and waits for filesystem changes.
    while (true) {
        // Wait until at least one monitored fd becomes readable.
        const ready = evloop.wait();

        // Iterate all triggered fds.
        for (evloop.iter(ready)) |evt| {
            // The only fd we registered so far is the inotify fd.
            if (evt.data.fd == signal.sigfd) {
                evnt.handleSignalEvents(&signal);
            }
            else if (evt.data.fd == watch.inotify_fd) {
                try evnt.handleInotifyEvents(&watch, &tracker);
            }
            else if (evt.data.fd == jnl.jfd) {
                evnt.handleJournalEvents(&jnl);
            }
        }
    }
}
