const std = @import("std");
const ct = @import("constants.zig");

pub const FilePos = struct {
    last_pos: u64,
    curr_pos: u64,
    file_path: []const u8,
    file: std.fs.File,

    pub fn init(path: [*:0]const u8) !FilePos {
        const file = try std.fs.cwd().openFile(std.mem.span(path), .{});
        const stat = try file.stat();

        try file.seekTo(stat.size);

        return FilePos{
            .last_pos = stat.size,
            .curr_pos = stat.size,
            .file_path = std.mem.span(path),
            .file = file,
        };
    }

    pub fn deinit(self: *FilePos) void {
        self.file.close();
    }

    pub fn getFileCurrPos(self: *FilePos) !u64 {
        const stat = try std.fs.cwd().statFile(self.file_path);
        return stat.size;
    }

    pub fn getFileSize(self: *FilePos) !u64 {
        const stat = try std.fs.cwd().statFile(self.file_path);
        return stat.size;
    }

    pub fn getBytesWritten(self: *const FilePos) u64 {
        return if (self.curr_pos > self.last_pos) self.curr_pos - self.last_pos else 0;
    }

    pub fn updateFilePos(self: *FilePos) !void {
        self.last_pos = self.curr_pos; 
    }

    pub fn readNewContent(self: *FilePos, buffer: []u8) ![]const u8 {
        self.curr_pos = try self.getFileCurrPos();
        const bytes_to_read = self.getBytesWritten();

        if (bytes_to_read == 0) return buffer[0..0];
        
        if (bytes_to_read < ct.MIN_BUFFER_SIZE) return buffer[0..0];

        const read_size = @min(bytes_to_read, buffer.len);

        //SAFEST: Use direct file reading without reader
        //Seek to where the new content starts
        try self.file.seekTo(self.last_pos);
        
        //Read directly from the file
        const bytes_read = try self.file.read(buffer[0..read_size]);
        try self.updateFilePos();
        return buffer[0..bytes_read];
    }

};
