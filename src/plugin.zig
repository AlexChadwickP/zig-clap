const std = @import("std");

const Plugin = struct {
    gain: f32 = 1.0,

    pub fn init() Plugin {
        return .{};
    }

    pub fn process(
        self: *Plugin,
        input: []const f32,
        output: []f32
    ) void {
        for (input, output) |sample, *out| {
            out.* = sample * self.gain;
        }
    }

    pub fn deinit(self: *Plugin) void {
        _ = self;
    }
};

test "gain scales every sample" {
    const input = [_]f32{ 1.0, -0.5, 0.25, 0.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };

    var p = Plugin.init();
    
    p.process(&input, &output);

    const expected = [_]f32{ 1.0, -0.5, 0.25, 0.0 };
    try std.testing.expectEqualSlices(f32, &expected, &output);
}
