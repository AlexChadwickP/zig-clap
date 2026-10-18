//! The CLAP glue: exports `clap_entry`, the plugin factory, and the callbacks
//! that forward into `Plugin`. Edit `descriptor` to rename the plugin.

const std = @import("std");
const clap = @import("clap_c.zig");
const Plugin = @import("plugin.zig").Plugin;

const c = clap.c;
const Instance = clap.Instance;

const allocator = std.heap.c_allocator;

const param_gain: c.clap_id = 0;

const features = [_:null]?[*:0]const u8{
    c.CLAP_PLUGIN_FEATURE_AUDIO_EFFECT,
    c.CLAP_PLUGIN_FEATURE_UTILITY,
};

const descriptor: c.clap_plugin_descriptor_t = .{
    .clap_version = c.CLAP_VERSION,
    .id = "com.example.zig-gain",
    .name = "Zig Gain",
    .vendor = "Example",
    .url = "",
    .manual_url = "",
    .support_url = "",
    .version = "0.1.0",
    .description = "A simple gain plugin written in Zig",
    .features = @ptrCast(&features),
};

// Factory ---------------------------------------------------------------

const factory: c.clap_plugin_factory_t = .{
    .get_plugin_count = factoryCount,
    .get_plugin_descriptor = factoryDescriptor,
    .create_plugin = factoryCreate,
};

fn factoryCount(_: [*c]const c.clap_plugin_factory_t) callconv(.c) u32 {
    return 1;
}

fn factoryDescriptor(_: [*c]const c.clap_plugin_factory_t, index: u32) callconv(.c) [*c]const c.clap_plugin_descriptor_t {
    return if (index == 0) &descriptor else null;
}

fn factoryCreate(
    _: [*c]const c.clap_plugin_factory_t,
    host: [*c]const c.clap_host_t,
    plugin_id: [*c]const u8,
) callconv(.c) [*c]const c.clap_plugin_t {
    if (host == null or plugin_id == null) return null;
    if (!std.mem.eql(u8, std.mem.span(plugin_id), std.mem.span(descriptor.id))) return null;

    const inst = allocator.create(Instance) catch return null;
    inst.* = .{
        .clap_plugin = .{
            .desc = &descriptor,
            .plugin_data = inst,
            .init = pluginInit,
            .destroy = pluginDestroy,
            .activate = pluginActivate,
            .deactivate = pluginDeactivate,
            .start_processing = pluginStartProcessing,
            .stop_processing = pluginStopProcessing,
            .reset = pluginReset,
            .process = pluginProcess,
            .get_extension = pluginGetExtension,
            .on_main_thread = pluginOnMainThread,
        },
        .host = host,
    };
    return &inst.clap_plugin;
}

// Plugin callbacks --------------------------------------------------------

fn instance(plugin: [*c]const c.clap_plugin_t) *Instance {
    return @ptrCast(@alignCast(plugin.*.plugin_data.?));
}

fn pluginInit(plugin: [*c]const c.clap_plugin_t) callconv(.c) bool {
    instance(plugin).implementation = Plugin.init();
    return true;
}

fn pluginDestroy(plugin: [*c]const c.clap_plugin_t) callconv(.c) void {
    const inst = instance(plugin);
    if (inst.implementation) |*p| p.deinit();
    allocator.destroy(inst);
}

fn pluginActivate(_: [*c]const c.clap_plugin_t, _: f64, _: u32, _: u32) callconv(.c) bool {
    return true;
}

fn pluginDeactivate(_: [*c]const c.clap_plugin_t) callconv(.c) void {}

fn pluginStartProcessing(_: [*c]const c.clap_plugin_t) callconv(.c) bool {
    return true;
}

fn pluginStopProcessing(_: [*c]const c.clap_plugin_t) callconv(.c) void {}

fn pluginReset(_: [*c]const c.clap_plugin_t) callconv(.c) void {}

fn pluginOnMainThread(_: [*c]const c.clap_plugin_t) callconv(.c) void {}

fn pluginProcess(plugin: [*c]const c.clap_plugin_t, process: [*c]const c.clap_process_t) callconv(.c) c.clap_process_status {
    const p = &(instance(plugin).implementation orelse return c.CLAP_PROCESS_ERROR);
    const proc = process.*;

    // Parameter changes are applied at the start of the block, not at their
    // sample offset. Good enough for a gain; a smoother plugin would split
    // the block at each event's `header.time`.
    applyParamEvents(p, proc.in_events);

    if (proc.audio_inputs_count == 0 or proc.audio_outputs_count == 0) return c.CLAP_PROCESS_CONTINUE;

    const in = proc.audio_inputs[0];
    const out = proc.audio_outputs[0];
    const frames: usize = proc.frames_count;
    const channels = @min(in.channel_count, out.channel_count);

    // 32-bit only; audio-ports does not advertise CLAP_AUDIO_PORT_SUPPORTS_64BITS.
    if (in.data32 == null or out.data32 == null) return c.CLAP_PROCESS_ERROR;

    for (0..channels) |ch| {
        p.process(in.data32[ch][0..frames], out.data32[ch][0..frames]);
    }
    return c.CLAP_PROCESS_CONTINUE;
}

fn applyParamEvents(p: *Plugin, events: [*c]const c.clap_input_events_t) void {
    if (events == null) return;
    const size = events.*.size.?(events);
    for (0..size) |i| {
        const header = events.*.get.?(events, @intCast(i));
        if (header.*.space_id != c.CLAP_CORE_EVENT_SPACE_ID) continue;
        if (header.*.type != c.CLAP_EVENT_PARAM_VALUE) continue;

        const ev: *const c.clap_event_param_value_t = @ptrCast(@alignCast(header));
        if (ev.param_id == param_gain) p.setGainDb(@floatCast(ev.value));
    }
}

fn pluginGetExtension(_: [*c]const c.clap_plugin_t, id: [*c]const u8) callconv(.c) ?*const anyopaque {
    const name = std.mem.span(id);
    if (std.mem.eql(u8, name, &c.CLAP_EXT_AUDIO_PORTS)) return &audio_ports;
    if (std.mem.eql(u8, name, &c.CLAP_EXT_PARAMS)) return &params;
    return null;
}

// Audio ports: one stereo in, one stereo out, processed in place -------------

const audio_ports: c.clap_plugin_audio_ports_t = .{
    .count = audioPortsCount,
    .get = audioPortsGet,
};

fn audioPortsCount(_: [*c]const c.clap_plugin_t, _: bool) callconv(.c) u32 {
    return 1;
}

fn audioPortsGet(_: [*c]const c.clap_plugin_t, index: u32, _: bool, info: [*c]c.clap_audio_port_info_t) callconv(.c) bool {
    if (index != 0) return false;
    info.* = .{
        .id = 0,
        .flags = c.CLAP_AUDIO_PORT_IS_MAIN,
        .channel_count = 2,
        .port_type = &c.CLAP_PORT_STEREO,
        .in_place_pair = c.CLAP_INVALID_ID,
    };
    copyZ(&info.*.name, "Main");
    return true;
}

// Parameters: a single gain knob in dB ---------------------------------------

const params: c.clap_plugin_params_t = .{
    .count = paramsCount,
    .get_info = paramsGetInfo,
    .get_value = paramsGetValue,
    .value_to_text = paramsValueToText,
    .text_to_value = paramsTextToValue,
    .flush = paramsFlush,
};

fn paramsCount(_: [*c]const c.clap_plugin_t) callconv(.c) u32 {
    return 1;
}

fn paramsGetInfo(_: [*c]const c.clap_plugin_t, index: u32, info: [*c]c.clap_param_info_t) callconv(.c) bool {
    if (index != 0) return false;
    info.* = .{
        .id = param_gain,
        .flags = c.CLAP_PARAM_IS_AUTOMATABLE,
        .min_value = Plugin.min_gain_db,
        .max_value = Plugin.max_gain_db,
        .default_value = 0.0,
    };
    copyZ(&info.*.name, "Gain");
    return true;
}

fn paramsGetValue(plugin: [*c]const c.clap_plugin_t, id: c.clap_id, out: [*c]f64) callconv(.c) bool {
    if (id != param_gain) return false;
    const p = &(instance(plugin).implementation orelse return false);
    out.* = p.gainDb();
    return true;
}

fn paramsValueToText(_: [*c]const c.clap_plugin_t, id: c.clap_id, value: f64, buf: [*c]u8, cap: u32) callconv(.c) bool {
    if (id != param_gain or cap == 0) return false;
    const out = buf[0..cap];
    const text = std.fmt.bufPrint(out[0 .. cap - 1], "{d:.1} dB", .{value}) catch return false;
    out[text.len] = 0;
    return true;
}

fn paramsTextToValue(_: [*c]const c.clap_plugin_t, id: c.clap_id, text: [*c]const u8, out: [*c]f64) callconv(.c) bool {
    if (id != param_gain) return false;
    // Accept "3", "3.5" or "3.5 dB".
    const s = std.mem.trim(u8, std.mem.span(text), " ");
    const number = if (std.mem.endsWith(u8, s, "dB")) std.mem.trim(u8, s[0 .. s.len - 2], " ") else s;
    out.* = std.fmt.parseFloat(f64, number) catch return false;
    return true;
}

fn paramsFlush(plugin: [*c]const c.clap_plugin_t, in: [*c]const c.clap_input_events_t, _: [*c]const c.clap_output_events_t) callconv(.c) void {
    const p = &(instance(plugin).implementation orelse return);
    applyParamEvents(p, in);
}

fn copyZ(dest: []u8, src: []const u8) void {
    const n = @min(src.len, dest.len - 1);
    @memcpy(dest[0..n], src[0..n]);
    dest[n] = 0;
}

// Entry point ---------------------------------------------------------------

fn entryInit(_: [*c]const u8) callconv(.c) bool {
    return true;
}

fn entryDeinit() callconv(.c) void {}

fn entryGetFactory(factory_id: [*c]const u8) callconv(.c) ?*const anyopaque {
    if (factory_id == null) return null;
    if (std.mem.eql(u8, std.mem.span(factory_id), &c.CLAP_PLUGIN_FACTORY_ID)) return &factory;
    return null;
}

export const clap_entry: c.clap_plugin_entry_t = .{
    .clap_version = c.CLAP_VERSION,
    .init = entryInit,
    .deinit = entryDeinit,
    .get_factory = entryGetFactory,
};
