//! CLAP's C types, translated by `zig translate-c` (see the Makefile), and the
//! per-instance state we hang off `clap_plugin_t.plugin_data`.

const Plugin = @import("plugin.zig").Plugin;

pub const c = @import("clap");

pub const Instance = struct {
    clap_plugin: c.clap_plugin_t,
    host: *const c.clap_host_t,

    /// Null until the host calls `init`, and again after `destroy`.
    implementation: ?Plugin = null,
};
