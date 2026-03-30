# micro-manage

Control a running `micro` instance from another process.

`micro-manage` listens on a FIFO and maps simple file-oriented commands to the
corresponding action inside `micro`, such as opening, saving, reloading,
closing, undoing, or redoing.

It is meant for workflows where `micro` stays open as the editor while an
external script, watcher, or agent needs to trigger actions in that session.

## Overview

The plugin currently supports these commands:

- `open:/path/to/file`
- `save:/path/to/file`
- `reload:/path/to/file`
- `close:/path/to/file`
- `undo:/path/to/file`
- `redo:/path/to/file`

Each command targets a file by path. The plugin resolves the matching internal
buffer or pane inside `micro`.

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
- If the file does not exist yet, open it anyway as a new file associated with
    that path.

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
${XDG_RUNTIME_DIR:-/tmp}/micro-manage-<session>.fifo
```

The default session name is:

```text
default
```

So the default FIFO path is:

```text
${XDG_RUNTIME_DIR:-/tmp}/micro-manage-default.fifo
```

## Starting micro

Default session:

```bash
micro
```

Named sessions can be set on the fly through an environment variable:

```bash
MICRO_MANAGE_SESSION=agent micro
```

If the environment variable is not set, the plugin uses `default`.

With the environment variable set, the FIFO becomes:

```text
${XDG_RUNTIME_DIR:-/tmp}/micro-manage-agent.fifo
```

## Sending Commands

Write commands directly to the FIFO.

Open a file in the default session:

```bash
printf '%s\n' 'open:/tmp/test.txt' > "${XDG_RUNTIME_DIR:-/tmp}/micro-manage-default.fifo"
```

Reload the same file:

```bash
printf '%s\n' 'reload:/tmp/test.txt' > "${XDG_RUNTIME_DIR:-/tmp}/micro-manage-default.fifo"
```

Use a named session:

```bash
printf '%s\n' 'open:/home/user/project/main.go' > "${XDG_RUNTIME_DIR:-/tmp}/micro-manage-agent.fifo"
```

## Installation

Repository layout:

```text
micro-manage.lua
repo.json
README.md
test.sh
```

## Design Notes

The goal is to keep the entry point simple and stable so other tools can
communicate with it however they prefer:

- Direct shell commands
- Watchers
- Automation scripts
- LLM-driven workflows
- Wrappers built on top of the FIFO

## Intended Use

Typical flow:

1. An external process edits files.
2. A watcher or script decides when to notify `micro`.
3. `micro-manage` receives commands through the FIFO.
4. `micro` reflects the state of those files.

This makes `micro` useful as a lightweight real-time viewer and operator
surface for externally managed file changes.

---

**Author:** KaisarCode

**Email:** <kaisar@kaisarcode.com>

**Website:** [https://kaisarcode.com](https://kaisarcode.com)

**License:** [GNU GPL v3.0](https://www.gnu.org/licenses/gpl-3.0.html)

© 2026 KaisarCode
