const std = @import("std");

const Measurement = struct {
    min: f32,
    max: f32,
    sum: f32,
    count: f32,

    pub fn init(val: f32) Measurement {
        return Measurement{
            .min = val,
            .max = val,
            .sum = val,
            .count = 1,
        };
    }

    pub fn calc(self: *Measurement, in: f32) void {
        self.min = @min(self.min, in);
        self.max = @max(self.max, in);
        self.sum = self.sum + in;
        self.count += 1;
    }
};

fn compList(_: @TypeOf(.{}), lhs: std.ArrayListUnmanaged(u8), rhs: std.ArrayListUnmanaged(u8)) bool {
    return std.mem.order(u8, lhs.items, rhs.items).compare(std.math.CompareOperator.lt);
}

pub fn main() anyerror!void {
    var gp_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gp_alloc.allocator();
    defer _ = gp_alloc.deinit();

    var measurements = std.StringHashMapUnmanaged(Measurement){};
    defer measurements.deinit(allocator);
    var stations = try std.ArrayListUnmanaged(std.ArrayListUnmanaged(u8)).initCapacity(allocator, @sizeOf(std.ArrayListUnmanaged(u8)) * 10000);
    defer stations.deinit(allocator);

    var args = std.process.args();
    _ = args.skip();
    const file_path = args.next().?;
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const buffer_size = 4096;
    var buffer: [buffer_size * 2]u8 = undefined;
    @memset(&buffer, 0);
    const line_buffer: *[buffer_size]u8 = buffer[4096..];

    const file_reader = file.reader();
    var buf_reader = std.io.BufferedReader(buffer_size, @TypeOf(file_reader)){ .unbuffered_reader = file_reader };

    var start: usize = 0;
    while (true) {
        const bytes_read = try buf_reader.read(line_buffer);
        var lines = std.mem.splitAny(u8, buffer[buffer_size - start .. buffer_size + bytes_read], "\n");
        const last_line = while (lines.next()) |line| {
            if (line.len == 0) break "";
            if (lines.peek() == null and bytes_read == buffer_size) break line;
            var it = std.mem.splitAny(u8, line, ";");
            const key = it.next().?;
            const val = try std.fmt.parseFloat(f32, it.next().?);

            if (measurements.getPtr(key)) |m| {
                m.*.calc(val);
            } else {
                var station = try std.ArrayListUnmanaged(u8).initCapacity(allocator, key.len);
                try station.appendSlice(allocator, key);
                const measurement = Measurement.init(val);
                try measurements.putNoClobber(allocator, station.items, measurement);
                try stations.append(allocator, station);
            }
        } else "";
        if (bytes_read < buffer_size) break;
        std.mem.copyForwards(u8, &buffer, line_buffer);
        start = last_line.len;
    }

    const list = try stations.toOwnedSlice(allocator);
    defer allocator.free(list);
    std.mem.sort(std.ArrayListUnmanaged(u8), list, .{}, comptime compList);

    const writer = std.io.getStdOut().writer();
    try writer.print("{{", .{});
    for (list) |*key| {
        const entry = measurements.getEntry(key.*.items).?;
        try writer.print("{s}={d:.1}/{d:.1}/{d:.1}, ", .{ entry.key_ptr.*, entry.value_ptr.*.min, entry.value_ptr.*.sum / entry.value_ptr.*.count, entry.value_ptr.*.max });
    }
    try writer.print("}}", .{});

    for (list) |*key| {
        key.*.deinit(allocator);
    }
}
