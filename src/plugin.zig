const std = @import("std");

/// The DSP half of the plugin. Nothing in here knows about CLAP, so it can be
/// unit tested with plain slices. Swap this out to build a different plugin.
pub const Plugin = struct {
    /// Gain in decibels. Read and written through `gainDb`/`setGainDb` because
    /// the host thread and the audio thread both touch it.
    gain_db: f32 = 0.0,

    pub const min_gain_db: f32 = -60.0;
    pub const max_gain_db: f32 = 12.0;

    pub fn init() Plugin {
        return .{};
    }

    /// Process one channel. `input` and `output` must be the same length and
    /// may be the same memory (hosts are allowed to process in place).
    pub fn process(self: *Plugin, input: []const f32, output: []f32) void {
        const gain = std.math.pow(f32, 10.0, self.gainDb() / 20.0);
        for (input, output) |sample, *out| {
            out.* = sample * gain;
        }
    }

    pub fn deinit(self: *Plugin) void {
        _ = self;
    }

    pub fn gainDb(self: *const Plugin) f32 {
        return @atomicLoad(f32, &self.gain_db, .monotonic);
    }

    pub fn setGainDb(self: *Plugin, db: f32) void {
        const clamped = std.math.clamp(db, min_gain_db, max_gain_db);
        @atomicStore(f32, &self.gain_db, clamped, .monotonic);
    }
};

test "0 dB leaves samples alone" {
    const input = [_]f32{ 1.0, -0.5, 0.25, 0.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };

    var p = Plugin.init();
    defer p.deinit();
    p.process(&input, &output);

    try std.testing.expectEqualSlices(f32, &input, &output);
}

test "+6 dB roughly doubles samples" {
    const input = [_]f32{ 0.5, -0.25 };
    var output = [_]f32{ 0.0, 0.0 };

    var p = Plugin.init();
    defer p.deinit();
    p.setGainDb(6.0206);
    p.process(&input, &output);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0), output[0], 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, -0.5), output[1], 1e-3);
}

test "processing in place works" {
    var buf = [_]f32{ 1.0, 1.0 };

    var p = Plugin.init();
    defer p.deinit();
    p.setGainDb(-20.0);
    p.process(&buf, &buf);

    try std.testing.expectApproxEqAbs(@as(f32, 0.1), buf[0], 1e-4);
}

test "gain is clamped to the parameter range" {
    var p = Plugin.init();
    p.setGainDb(100.0);
    try std.testing.expectEqual(Plugin.max_gain_db, p.gainDb());
}
