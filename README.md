# zig-clap-template

A template for writing [CLAP](https://github.com/free-audio/clap) audio plugins in Zig. The example is a stereo gain plugin with one automatable parameter.

Needs Zig 0.17 and make. macOS and Linux.

```
make            # build/ZigGain.clap
make test       # unit tests for the DSP code
make install    # ~/Library/Audio/Plug-Ins/CLAP (macOS) or ~/.clap (Linux)
```

## Layout

- `src/plugin.zig` has `Plugin` with `init`, `process` and `deinit`. It knows nothing about CLAP. Write your DSP here.
- `src/clap_entry.zig` exports `clap_entry`, the factory, the audio-ports and params extensions, and forwards host calls into `Plugin`. Edit `descriptor` to rename the plugin.
- `src/clap_c.zig` holds the translated C types and the per-instance `Instance` struct.
- `third_party/clap` is a vendored copy of the CLAP 1.2.10 headers (MIT).

Zig 0.17 removed `@cImport`, so the Makefile runs `zig translate-c` on `src/clap.h` and passes the result in as the `clap` module.

To rename the output, `make NAME=MyPlugin` and change `descriptor.id`/`name` in `clap_entry.zig`.
