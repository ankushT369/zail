const std = @import("std");

// Inotify watcher: responsible for recursive directory watches.
const wt = @import("watch.zig");

// File position tracker: tracks append-only reads on multiple files.
const fp = @import("filetracker.zig");

// Constants (paths, masks, buffer sizes, epoll config, etc.)
const ct = @import("constants.zig");

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


    // Epoll configuration
    // Create the epoll instance used to wait on the inotify fd.
    const epfd = linux.epoll_create1(linux.EPOLL.CLOEXEC);
    const epollfd: i32 = @intCast(epfd);

    // Storage for incoming events from epoll_wait.
    var events: [ct.MAX_EVENTS]linux.epoll_event = undefined;
    var ev: linux.epoll_event = undefined;

    // Register the inotify fd so epoll notifies us when something changes.
    ev.events = linux.EPOLL.IN;
    ev.data.fd = watch.inotify_fd;
    _ = linux.epoll_ctl(epollfd, linux.EPOLL.CTL_ADD, watch.inotify_fd, &ev);


    // Event loop
    // This loop runs forever and waits for filesystem changes.
    while (true) {
        // Wait until at least one monitored fd becomes readable.
        // `-1` means “block forever”.
        const ready = linux.epoll_wait(epollfd, &events, ct.MAX_EVENTS, -1);

        // Iterate all triggered fds.
        for (events[0..ready]) |evt| {
            // The only fd we registered so far is the inotify fd.
            if (evt.data.fd == watch.inotify_fd) {

                // Read all pending inotify events into the global buffer.
                const len = linux.read(watch.inotify_fd,
                    &wt.inotify_buffer,
                    wt.inotify_buffer_size,
                );

                // Walk through the buffer consuming variable-length events.
                var ptr: usize = 0;
                while (ptr < len) {
                    const event = @as(
                        *const linux.inotify_event,
                        @alignCast(@ptrCast(&wt.inotify_buffer[ptr])),
                    );

                    // Only process events matching our mask.
                    if (event.mask & ct.MASK != 0) {
                        // Look up the directory path associated with this watch descriptor.
                        const dir_path = watch.getPath(event.wd).?;

                        // Get the file/directory name part.
                        const file_name = event.getName().?; // implemented inside watch.zig

                        // Construct full path where the event occurred.
                        var buffer: [ct.MAX_PATH_LEN]u8 = undefined;
                        const full_path = std.fmt.bufPrintZ(&buffer, "{s}/{s}", .{ dir_path, file_name }) catch {
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
        }
    }
}

