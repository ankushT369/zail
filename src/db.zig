const std = @import("std");

// Import SQLite C API
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub fn call() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db: ?*c.sqlite3 = null;

    // Open database
    const rc = c.sqlite3_open("test.db", &db);
    if (rc != c.SQLITE_OK) {
        std.debug.print("Cannot open database: {s}\n", .{c.sqlite3_errmsg(db)});
        if (db) |db_ptr| _ = c.sqlite3_close(db_ptr);
        return error.DatabaseOpenFailed;
    }

    // Close DB safely at the end
    defer {
        if (db) |db_ptr| {
            _ = c.sqlite3_close(db_ptr);
        }
    }

    try createTable(db, allocator);
    try insertData(db, allocator);
    try queryData(db, allocator);
}

pub fn createTable(db: ?*c.sqlite3, _allocator: std.mem.Allocator) !void {
    _ = _allocator;

    const sql =
        \\CREATE TABLE IF NOT EXISTS file_positions (
        \\    wd INTEGER PRIMARY KEY,
        \\    path TEXT NOT NULL,
        \\    last_pos INTEGER NOT NULL,
        \\    curr_pos INTEGER NOT NULL
        \\)
    ;

    var err_msg: [*c]u8 = null;
    const rc = c.sqlite3_exec(db, sql, null, null, &err_msg);

    if (rc != c.SQLITE_OK) {
        std.debug.print("SQL error: {s}\n", .{err_msg});
        c.sqlite3_free(err_msg);
        return error.SqlExecutionFailed;
    }
}

pub fn insertData(db: ?*c.sqlite3, _allocator: std.mem.Allocator) !void {
    _ = _allocator;

    const sql = "INSERT INTO file_positions (wd, path, last_pos, curr_pos) VALUES (?, ?, ?, ?)";
    var stmt: ?*c.sqlite3_stmt = null;

    const rc = c.sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) return error.StmtPrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    const fileData = [_]struct { 
        wd: c_int, 
        path: []const u8, 
        last_pos: c_int, 
        curr_pos: c_int 
    }{
        .{ .wd = 1, .path = "/home/user/documents/file1.txt", .last_pos = 0, .curr_pos = 1024 },
        .{ .wd = 2, .path = "/home/user/downloads/file2.pdf", .last_pos = 512, .curr_pos = 2048 },
        .{ .wd = 3, .path = "/var/log/app.log", .last_pos = 1024, .curr_pos = 4096 },
    };

    for (fileData) |data| {
        _ = c.sqlite3_bind_int(stmt, 1, data.wd);
        _ = c.sqlite3_bind_text(stmt, 2, data.path.ptr, @intCast(data.path.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_int(stmt, 3, data.last_pos);
        _ = c.sqlite3_bind_int(stmt, 4, data.curr_pos);

        const step_rc = c.sqlite3_step(stmt);
        if (step_rc != c.SQLITE_DONE) {
            std.debug.print("Insert failed: {}\n", .{step_rc});
            return error.InsertFailed;
        }

        _ = c.sqlite3_reset(stmt);
    }
}

pub fn queryData(db: ?*c.sqlite3, _allocator: std.mem.Allocator) !void {
    _ = _allocator;

    const sql = "SELECT wd, path, last_pos, curr_pos FROM file_positions";
    var stmt: ?*c.sqlite3_stmt = null;

    const rc = c.sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) return error.StmtPrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    std.debug.print("File Positions:\n", .{});

    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        const wd = c.sqlite3_column_int(stmt, 0);
        const path_ptr = c.sqlite3_column_text(stmt, 1);
        const last_pos = c.sqlite3_column_int(stmt, 2);
        const curr_pos = c.sqlite3_column_int(stmt, 3);

        const path_len = c.sqlite3_column_bytes(stmt, 1);

        std.debug.print("  WD: {}, Path: {s}, Last Pos: {}, Current Pos: {}\n", .{
            wd,
            path_ptr[0..@intCast(path_len)],
            last_pos,
            curr_pos,
        });
    }
}

// Additional utility functions for your use case
pub fn updatePosition(db: ?*c.sqlite3, wd: c_int, new_curr_pos: c_int) !void {
    const sql = "UPDATE file_positions SET last_pos = curr_pos, curr_pos = ? WHERE wd = ?";
    var stmt: ?*c.sqlite3_stmt = null;

    const rc = c.sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) return error.StmtPrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int(stmt, 1, new_curr_pos);
    _ = c.sqlite3_bind_int(stmt, 2, wd);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) {
        std.debug.print("Update failed: {}\n", .{step_rc});
        return error.UpdateFailed;
    }
}

pub fn getPosition(db: ?*c.sqlite3, wd: c_int) !struct { last_pos: c_int, curr_pos: c_int } {
    const sql = "SELECT last_pos, curr_pos FROM file_positions WHERE wd = ?";
    var stmt: ?*c.sqlite3_stmt = null;

    const rc = c.sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) return error.StmtPrepareFailed;
    defer _ = c.sqlite3_finalize(stmt);

    _ = c.sqlite3_bind_int(stmt, 1, wd);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc == c.SQLITE_ROW) {
        return .{
            .last_pos = c.sqlite3_column_int(stmt, 0),
            .curr_pos = c.sqlite3_column_int(stmt, 1),
        };
    } else {
        return error.RecordNotFound;
    }
}
