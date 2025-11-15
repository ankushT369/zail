const std = @import("std");
const ct = @import("constants.zig");
const c = @cImport({
    @cInclude("sys/stat.h");
});


pub const FilePos = struct {
    inode: u64,
    dev_id: u64,
    last_pos: u64,
    curr_pos: u64,
    file: std.fs.File,
    file_path: []const u8,

    fn init(path: []const u8, allocator: std.mem.Allocator) !FilePos {
        // Duplicate path into heap memory (to store long-term)
        const path_copy = try allocator.dupe(u8, path);

        // Open file
        const file = try std.fs.cwd().openFile(path, .{});

        // Get Zig stat (inode & size)
        const st = try file.stat();

        // Get dev_id via C stat
        var st_c: c.struct_stat = undefined;
        if (c.stat(@ptrCast(path_copy.ptr), &st_c) != 0) {
            return error.StatFailed;
        }

        // Seek to end
        try file.seekTo(st.size);

        return .{
            .inode = st.inode,
            .dev_id = st_c.st_dev, 
            .last_pos = st.size,
            .curr_pos = st.size,
            .file = file,
            .file_path = path_copy,
        };
    }

    fn deinit(self: *FilePos, allocator: std.mem.Allocator) void {
        self.file.close();
        allocator.free(self.file_path);
    }

    fn getFileCurrPos(self: *FilePos) !u64 {
        const st = try std.fs.cwd().statFile(self.file_path);
        return st.size;
    }

    fn bytesWritten(self: *FilePos) u64 {
        return if (self.curr_pos > self.last_pos)
            self.curr_pos - self.last_pos
        else
            0;
    }

    pub fn readNewContent(self: *FilePos, buf: []u8) ![]const u8 {
        self.curr_pos = try self.getFileCurrPos();

        const written = self.bytesWritten();
        if (written == 0) return buf[0..0];
        if (written < ct.MIN_BUFFER_SIZE) return buf[0..0];

        const read_size = @min(written, buf.len);

        try self.file.seekTo(self.last_pos);
        const n = try self.file.read(buf[0..read_size]);

        self.last_pos = self.curr_pos;
        return buf[0..n];
    }
};

pub const FileTracker = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap(u128, FilePos),

    pub fn init(allocator: std.mem.Allocator) !FileTracker {
        return .{
            .allocator = allocator,
            .map = std.AutoHashMap(u128, FilePos).init(allocator),
        };
    }

    pub fn deinit(self: *FileTracker) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.map.deinit();
    }

    pub fn makeKey(dev_id: u64, inode: u64) u128 {
        return (@as(u128, dev_id) << 64) | @as(u128, inode);
    }

    pub fn track(self: *FileTracker, path: []const u8) !*FilePos {
        // Stat first to get inode/dev before doing anything expensive
        const st = try std.fs.cwd().statFile(path);

        var st_c: c.struct_stat = undefined;
        if (c.stat(@ptrCast(path.ptr), &st_c) != 0) {
            return error.StatFailed;
        }

        const key = FileTracker.makeKey(st_c.st_dev, st.inode);

        if (self.map.getPtr(key)) |existing| {
            // File already tracked
            return existing;
        }

        // Create new FilePos
        const fp = try FilePos.init(path, self.allocator);

        // Insert into map
        try self.map.put(key, fp);

        // Return pointer to it
        return self.map.getPtr(key).?;
    }
};

