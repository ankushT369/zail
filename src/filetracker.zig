const std = @import("std");
const ct = @import("constants.zig");
const tp = @import("types.zig");

const fs = std.fs;

const INODE = tp.INODE;
const DEV = tp.DEV;
const UID = tp.UID;

const c = @cImport({
    @cInclude("sys/stat.h");
});

/// FilePos is an identity of an opened file it stores the inode, dev_id,
/// last_pos(last position), curr_pos(current position), file object and 
/// file path.
pub const FilePos = struct {
    // file inode
    inode: INODE,
    // device ID
    dev_id: DEV,
    // last known size
    last_pos: u64,
    // current size
    curr_pos: u64,
    file: fs.File,
    file_path: []const u8,

    /// Initialize tracking for a single file.
    /// - Duplicates the file path into allocator-owned memory.
    /// - Opens the file for reading.
    /// - Reads inode from Zig stat and dev_id from C stat.
    /// - Seeks to the end so we only read new content later.
    fn init(path: []const u8, allocator: std.mem.Allocator) !FilePos {
        // Duplicate path into heap memory (to store long-term)
        const path_copy = try allocator.dupe(u8, path);

        // Open file
        const file = try fs.cwd().openFile(path, .{});

        // Get Zig stat (inode & size)
        const st = try file.stat();

        const inode: INODE = try getFileInode(path);
        const dev_id: DEV = try getDeviceID(path_copy);

        // Seek to end
        try file.seekTo(st.size);

        return .{
            .inode = inode,
            .dev_id = dev_id, 
            .last_pos = st.size,
            .curr_pos = st.size,
            .file = file,
            .file_path = path_copy,
        };
    }

    /// Release all resources for this FilePos.
    /// Closes the open file and frees the path string.
    fn deinit(self: *FilePos, allocator: std.mem.Allocator) void {
        self.file.close();
        allocator.free(self.file_path);
    }

    // Get file inode
    fn getFileInode(path: []const u8 ) !INODE {
        const st = try fs.cwd().statFile(path);
        return st.size;
    }

    // Get dev_id via C stat
    fn getDeviceID(path: []u8) !DEV {
        var st_c: c.struct_stat = undefined;
        if (c.stat(@ptrCast(path.ptr), &st_c) != 0) {
            return error.StatFailed;
        }
        return st_c.st_dev;
    }

    /// Query the current file size. Useful to detect if more data
    /// has been appended since last read.
    fn getFileCurrPos(self: *FilePos) !u64 {
        const st = try fs.cwd().statFile(self.file_path);
        return st.size;
    }

    /// Compute how many new bytes appeared since the last read.
    /// If the file shrank (truncate/rotate), this returns zero.
    fn bytesWritten(self: *FilePos) u64 {
        return if (self.curr_pos > self.last_pos)
            self.curr_pos - self.last_pos
        else
            0;
    }

    /// Read only the newly appended part of the file into the buffer.
    /// - Updates curr_pos and last_pos accordingly.
    /// - Returns an empty slice if nothing new was written.
    /// - Never reads more than `buf.len`.
    ///
    /// This function assumes the file is append-only or periodically truncated.
    pub fn readNewContent(self: *FilePos, buf: []u8) ![]const u8 {
        self.curr_pos = try self.getFileCurrPos();

        const written = self.bytesWritten();
        if (written == 0) return buf[0..0];
        //if (written < ct.MIN_BUFFER_SIZE) return buf[0..0];

        const read_size = @min(written, buf.len);

        try self.file.seekTo(self.last_pos);
        const n = try self.file.read(buf[0..read_size]);

        self.last_pos = self.curr_pos;
        return buf[0..n];
    }
};

/// Tracks multiple FilePos instances.
/// fp_maps stores the UID(inode + dev_id) → FilePos instance.
/// has a stable identity even if the path changes or is opened
/// through different symlink locations.
///
/// FileTracker owns all FilePos objects stored inside it.
pub const FileTracker = struct {
    allocator: std.mem.Allocator,
    fp_map: std.AutoHashMap(UID, FilePos),

    /// Create an empty tracker. Caller must call `deinit`
    /// to close all tracked files and free paths.
    pub fn init(allocator: std.mem.Allocator) !FileTracker {
        return .{
            .allocator = allocator,
            .fp_map = std.AutoHashMap(u128, FilePos).init(allocator),
        };
    }
    /// Free every FilePos stored inside the fp_map and destroy the fp_map.
    /// After this, the tracker must not be used.
    pub fn deinit(self: *FileTracker) void {
        var it = self.fp_map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.fp_map.deinit();
    }

    pub fn makeKey(dev_id: u64, inode: u64) u128 {
        return (@as(u128, dev_id) << 64) | @as(u128, inode);
    }

    /// Start tracking a file if it isn't already being tracked.
    /// If we already have a FilePos for this (dev_id, inode),
    /// return the existing one.
    ///
    /// Otherwise:
    ///   - Run stat to extract inode/dev
    ///   - Create a new FilePos (opens the file + duplicates path)
    ///   - Store it in the map
    ///   - Return pointer to stored FilePos
    ///
    /// Returns a stable pointer that remains valid until `deinit`.
    pub fn track(self: *FileTracker, path: []const u8) !*FilePos {
        // Stat first to get inode/dev before doing anything expensive
        const st = try fs.cwd().statFile(path);

        var st_c: c.struct_stat = undefined;
        if (c.stat(@ptrCast(path.ptr), &st_c) != 0) {
            return error.StatFailed;
        }

        const key = FileTracker.makeKey(st_c.st_dev, st.inode);

        if (self.fp_map.getPtr(key)) |existing| {
            // File already tracked
            return existing;
        }

        // Create new FilePos
        const fp = try FilePos.init(path, self.allocator);

        // Insert into fp_map
        try self.fp_map.put(key, fp);

        // Return pointer to it
        return self.fp_map.getPtr(key).?;
    }
};
