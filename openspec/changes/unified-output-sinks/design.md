## Context

libvips exposes each encoder as a filename saver, a buffer saver, and a target
saver (`*_save_target`). The first two are wrappers over the third, but the
project's shims passed different option sets to them.

## Decisions

### Always save to a target

One call per format, `*_save_target`, with every codec option. The sink is a
`VipsTarget`: `vips_target_new_to_memory` for `data()`, and a custom target for
files. This removes the chance of drift between sinks structurally rather than
by keeping two shims in sync, and is the layer a later bounded stream adapter
(#46) can reuse.

### A Hokusai-owned file target

`vips_target_new_to_file` reports failures only as libvips text, which would
force either guessing encode versus I/O from English or collapsing both into
`encode`. A custom target that writes with `open`/`write` records `errno` for the
first failure, so `io(.write)` is exact. It also lets Hokusai count bytes written
and control cleanup.

- Lazy open: the destination is not touched if the pipeline fails before it
  produces output.
- Cleanup: a failure after output began removes the file, but only a regular
  file the sink opened itself. Devices and pipes (for example `/dev/full`) are
  never unlinked.
- In-place write rather than temp-file-and-rename: it keeps the existing
  semantics for symlinks, permissions, and hard links.

### Take the memory buffer by ownership transfer

After a saver ends its memory target the bytes live in the target's `blob`.
The shim detaches the blob's free function as libvips' own buffer savers do and
`Data(bytesNoCopy:)` takes the pointer with a `g_free` deallocator. That avoids
the second copy the old path made.

### Not done here

PDF/Cairo streaming (#44), public stream sinks (#46), `OutputInfo` additions,
and the `Encoder` value that replaces the closed `OutputFormat` enum (#51).
