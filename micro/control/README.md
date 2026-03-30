# control

External control interface for `micro`.

`control` exposes a small command surface through a FIFO so an external process can operate on files opened in a running `micro` instance.

This is useful when `micro` acts as a lightweight visual surface while another tool, script, watcher, or agent edits files independently.

## Overview

The plugin currently supports these commands:

- `open:/path/to/file`
- `save:/path/to/file`
- `reload:/path/to/file`
- `close:/path/to/file`
- `undo:/path/to/file`
- `redo:/path/to/file`

Each command targets a file by path. The plugin resolves the matching internal buffer or pane inside `micro`.

## Command Format

Send one command per line:

```text
action:/path/to/file
```

Examples:

```text
open:/home/user/project/main.go
reload:/home/user/project/main.go
save:/home/user/project/main.go
close:/home/user/project/main.go
undo:/home/user/project/main.go
redo:/home/user/project/main.go
```

## Command Semantics

### `open:/path`

- If the file is already open, focus it.
- If it is not open, open it in a new tab.
- If the file does not exist yet, open it anyway as a new file associated with that path.

### `save:/path`

- Save the corresponding open file.

### `reload:/path`

- Reload the file from disk.
- Intended to reflect external changes immediately in the editor view.

### `close:/path`

- Close the corresponding file.
- This does not terminate the whole `micro` instance.

### `undo:/path`

- Run undo on the corresponding file.

### `redo:/path`

- Run redo on the corresponding file.

## Session Model

Each running `micro` instance exposes its own FIFO.

The FIFO name is derived from the configured session name:

```text
${XDG_RUNTIME_DIR:-/tmp}/micro-control-<session>.fifo
```

The default session name is:

```text
default
```

So the default FIFO path is:

```text
${XDG_RUNTIME_DIR:-/tmp}/micro-control-default.fifo
```

## Starting micro

Default session:

```bash
micro
```

Named session:

```bash
micro -control.session agent
```

Another named session:

```bash
micro -control.session review
```

## Sending Commands

Write commands directly to the FIFO.

Open a file in the default session:

```bash
printf '%s\n' 'open:/tmp/test.txt' > "${XDG_RUNTIME_DIR:-/tmp}/micro-control-default.fifo"
```

Reload the same file:

```bash
printf '%s\n' 'reload:/tmp/test.txt' > "${XDG_RUNTIME_DIR:-/tmp}/micro-control-default.fifo"
```

Use a named session:

```bash
printf '%s\n' 'open:/home/user/project/main.go' > "${XDG_RUNTIME_DIR:-/tmp}/micro-control-agent.fifo"
```

## Installation

Expected layout:

```text
~/.config/micro/plug/control/control.lua
~/.config/micro/plug/control/repo.json
```

## Testing

There is one test script in the repository:

```bash
./test.sh
```

Start `micro` first:

```bash
micro
```

Then run `./test.sh`.

The script waits for the FIFO and walks through `open`, `reload`, `undo`, `redo`, `save`, and `close`. It exits with success when the sequence was sent correctly, or with failure if the plugin FIFO is not available.

## Design Notes

`control` is intentionally minimal.

It does not expose internal `micro` identifiers through the external interface. The public interface uses file paths only, and the plugin resolves the corresponding internal buffer or pane on its own.

The goal is to keep the entry point simple and stable so other tools can communicate with it however they prefer:

- Direct shell commands
- Watchers
- Automation scripts
- LLM-driven workflows
- Wrappers built on top of the FIFO

## Intended Use

Typical flow:

1. An external process edits files.
2. A watcher or script decides when to notify `micro`.
3. `control` receives commands through the FIFO.
4. `micro` reflects the state of those files.

This makes `micro` useful as a lightweight real-time viewer and operator surface for externally managed file changes.

## Limitations

The current scope is intentionally narrow:

- One FIFO per running `micro` session
- One command per line
- Path-based targeting only
- No wrapper CLI included yet
- No higher-level protocol yet

## Future Direction

More commands can be added later depending on what `micro` supports cleanly.

For now, the plugin focuses on a simple file-oriented external control surface.
