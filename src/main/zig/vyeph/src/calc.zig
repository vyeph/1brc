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

    const buffer_size = 2048;
    var line_buffer: [buffer_size]u8 = undefined;

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var counter: u64 = 0;
    while (try in_stream.readUntilDelimiterOrEof(&line_buffer, '\n')) |line| {
        if (counter % 50000000 == 0) {
            std.debug.print("Line entries read : {d}/1000000000\n", .{counter});
        }
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
        counter += 1;
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
