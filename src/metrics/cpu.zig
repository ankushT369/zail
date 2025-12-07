const std = @import("std");

const cstat: []const u8 = "/proc/stat";

const MAX_CORES = 512;

const CpuInfo = struct {
    user: u64,
    nice: u64,
    system: u64,
    idle: u64,
    iowait: u64,
    irq: u64,
    softirq: u64,
    steal: u64,
    guest: u64,
    guest_nice: u64,

    fn init() CpuInfo {
        return .{
            .user = 0,
            .nice = 0,
            .system = 0,
            .idle = 0,
            .iowait = 0,
            .irq = 0,
            .softirq = 0,
            .steal = 0,
            .guest = 0,
            .guest_nice = 0,
        };
    }
};

const CpuStat = struct {
    nos_core: u8,
    core_arr: [MAX_CORES]CpuInfo,

    ctxt: u64,
    btime: u64,
    processes: u64,
    procs_running: u64,
    procs_blocked: u64,

    fn init() CpuStat {
        var core_arr: [MAX_CORES]CpuInfo = undefined;
        for (&core_arr) |*core| {
            core.* = CpuInfo.init();
        }

        return .{
            .nos_core = 0,
            .core_arr = core_arr,
            
            .ctxt = 0,
            .btime = 0,
            .processes = 0,
            .procs_running = 0,
            .procs_blocked = 0,
        };
    }
};


pub const CpuMetrics = struct {
    cmet: CpuStat,

    pub fn init() CpuMetrics {
        return .{
            .cmet = CpuStat.init(),
        }; 
    }

    pub fn parse(self: *CpuMetrics) !void {
        const file = try std.fs.cwd().openFile(cstat, .{});
        defer file.close();

        self.cmet.nos_core = 0;
        
        var buffer: [8192]u8 = undefined;
        const bytes_read = try file.readAll(&buffer);
        const content = buffer[0..bytes_read];
        
        var lines = std.mem.splitSequence(u8, content, "\n");

        var cpu_index: u8 = 0;
        
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            
            var tokens = std.mem.tokenizeAny(u8, line, " ");
            const cpu_label = tokens.next() orelse continue;
            
            if (std.mem.startsWith(u8, cpu_label, "cpu")) {
                var values: [10]u64 = undefined;
                var count: usize = 0;
                
                while (tokens.next()) |token| {
                    if (count >= values.len) break;
                    values[count] = std.fmt.parseUnsigned(u64, token, 10) catch 0;
                    count += 1;
                }

                if (cpu_index < MAX_CORES) {
                    self.cmet.core_arr[cpu_index].user = values[0];
                    self.cmet.core_arr[cpu_index].nice = values[1];
                    self.cmet.core_arr[cpu_index].system = values[2];
                    self.cmet.core_arr[cpu_index].idle = values[3];
                    self.cmet.core_arr[cpu_index].iowait = values[4];
                    self.cmet.core_arr[cpu_index].irq = values[5];
                    self.cmet.core_arr[cpu_index].softirq = values[6];
                    self.cmet.core_arr[cpu_index].steal = values[7];
                    self.cmet.core_arr[cpu_index].guest = values[8];
                    self.cmet.core_arr[cpu_index].guest_nice = values[9];
                    cpu_index += 1;
                }
                
            } else if (std.mem.eql(u8, cpu_label, "ctxt")) {
                if (tokens.next()) |token| {
                    self.cmet.ctxt = std.fmt.parseUnsigned(u64, token, 10) catch 0;
                }
            } else if (std.mem.eql(u8, cpu_label, "btime")) {
                if (tokens.next()) |token| {
                    self.cmet.btime = std.fmt.parseUnsigned(u64, token, 10) catch 0;
                }
            } else if (std.mem.eql(u8, cpu_label, "processes")) {
                if (tokens.next()) |token| {
                    self.cmet.processes = std.fmt.parseUnsigned(u64, token, 10) catch 0;
                }
            } else if (std.mem.eql(u8, cpu_label, "procs_running")) {
                if (tokens.next()) |token| {
                    self.cmet.procs_running = std.fmt.parseUnsigned(u64, token, 10) catch 0;
                }
            } else if (std.mem.eql(u8, cpu_label, "procs_blocked")) {
                if (tokens.next()) |token| {
                    self.cmet.procs_blocked = std.fmt.parseUnsigned(u64, token, 10) catch 0;
                }
            }
        }

        self.cmet.nos_core = cpu_index - 1;
    }

    // DEBUG
    pub fn printStats(self: *const CpuMetrics) void {
        std.debug.print("\n=== CPU Statistics ===\n", .{});
        std.debug.print("Number of cores: {}\n", .{self.cmet.nos_core});
        std.debug.print("Context switches: {}\n", .{self.cmet.ctxt});
        std.debug.print("Boot time: {}\n", .{self.cmet.btime});
        std.debug.print("Processes created: {}\n", .{self.cmet.processes});
        std.debug.print("Processes running: {}\n", .{self.cmet.procs_running});
        std.debug.print("Processes blocked: {}\n", .{self.cmet.procs_blocked});

        std.debug.print("\n=== Per Core Statistics ===\n", .{});
        for (0..self.cmet.nos_core) |i| {
            if (i != 0) {
                const core = self.cmet.core_arr[i];
                std.debug.print("CPU{}: user={} nice={} system={} idle={} iowait={} irq={} softirq={} steal={} guest={} guest_nice={}\n",
                    .{ i - 1, core.user, core.nice, core.system, core.idle, core.iowait,
                       core.irq, core.softirq, core.steal, core.guest, core.guest_nice });
            } else {
                const core = self.cmet.core_arr[i];
                std.debug.print("CPU: user={} nice={} system={} idle={} iowait={} irq={} softirq={} steal={} guest={} guest_nice={}\n",
                    .{core.user, core.nice, core.system, core.idle, core.iowait,
                       core.irq, core.softirq, core.steal, core.guest, core.guest_nice });
            }
        }
    }
};
