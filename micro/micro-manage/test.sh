#!/bin/bash
# test.sh - Automated test suite for micro-manage
# Summary: Tiered testing for micro-manage plugin session and FIFO behavior.
#
# Author:  KaisarCode
# Website: https://kaisarcode.com
# License: GNU GPL v3.0
set -e

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
APP_ROOT="$SCRIPT_DIR"
PLUGIN_LOAD_DIR=""
TMP_DIR=""
CONFIG_DIR=""
RUNTIME_DIR=""
INPUT_FIFO=""
MICRO_LOG=""
PRIMARY_FILE=""
SECONDARY_FILE=""
CONTROL_FIFO=""
MICRO_PID=""
TEST_SESSION="micro-manage-test"

# Prints failure details to standard output.
# @param message Error description.
# @return 1 on failure.
fail() {
    printf "\033[31m[FAIL]\033[0m %s\n" "$1"
    if [ -n "${MICRO_LOG:-}" ] && [ -s "$MICRO_LOG" ]; then
        printf '\nMicro log:\n'
        sed -n '1,160p' "$MICRO_LOG"
    fi
    exit 1
}

# Prints success details to standard output.
# @param message Success description.
# @return 0 on success.
pass() {
    printf "\033[32m[PASS]\033[0m %s\n" "$1"
}

# Cleans temporary resources and stops the test micro process.
# @return 0 on success.
cleanup() {
    if [ -n "${MICRO_PID:-}" ] && kill -0 "$MICRO_PID" 2>/dev/null; then
        printf '\x11' >&3 2>/dev/null || true
        sleep 1
        kill "$MICRO_PID" 2>/dev/null || true
        wait "$MICRO_PID" 2>/dev/null || true
    fi

    exec 3>&- 2>/dev/null || true
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

# Verifies that a required command is available.
# @param name Command name.
# @return 0 when the command exists.
require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "$1 not found"
}

# Waits until a FIFO path becomes available.
# @param path FIFO path.
# @return 0 when the FIFO exists.
wait_for_path() {
    local path="$1"
    local tries=200

    while [ "$tries" -gt 0 ]; do
        if [ -p "$path" ]; then
            return 0
        fi
        if [ -n "${MICRO_PID:-}" ] && ! kill -0 "$MICRO_PID" 2>/dev/null; then
            fail "micro exited before creating $path"
        fi
        sleep 0.05
        tries=$((tries - 1))
    done

    fail "timed out waiting for $path"
}

# Sends keyboard input to the micro PTY.
# @param text Text to write.
# @return 0 on success.
send_keys() {
    printf '%s' "$1" >&3 || fail "could not send keyboard input"
    sleep 0.3
}

# Sends one command to the control FIFO.
# @param command Control command.
# @return 0 on success.
send_command() {
    printf '%s\n' "$1" > "$CONTROL_FIFO" || fail "could not send control command: $1"
    sleep 0.3
}

# Reads a file if it exists.
# @param path File path.
# @return 0 on success.
read_file() {
    local path="$1"
    if [ -f "$path" ]; then
        cat "$path"
    fi
}

# Verifies that a file eventually matches an expected value.
# @param path File path.
# @param expected Expected content.
# @param label Validation label.
# @return 0 on success.
expect_file() {
    local path="$1"
    local expected="$2"
    local label="$3"
    local tries=80
    local actual=""

    while [ "$tries" -gt 0 ]; do
        actual="$(read_file "$path")"
        if [ "$actual" = "$expected" ]; then
            return 0
        fi
        if [ -n "${MICRO_PID:-}" ] && ! kill -0 "$MICRO_PID" 2>/dev/null; then
            fail "micro exited during: $label"
        fi
        sleep 0.05
        tries=$((tries - 1))
    done

    fail "$label: expected [$expected], got [$actual]"
}

# Starts a temporary micro instance with the micro-manage plugin loaded.
# @return 0 on success.
start_micro() {
    mkdir -p "$CONFIG_DIR/plug" "$RUNTIME_DIR" "$PLUGIN_LOAD_DIR"
    ln -s "$APP_ROOT/micro-manage.lua" "$PLUGIN_LOAD_DIR/micromanage.lua"
    cat > "$PLUGIN_LOAD_DIR/repo.json" <<'EOF'
[
    {
        "Name": "micromanage",
        "Description": "Temporary load alias for micro-manage tests",
        "Website": "https://kaisarcode.com",
        "Tags": ["micro-manage", "fifo", "automation"],
        "Versions": [
            {
                "Version": "1.0.0",
                "Url": "local",
                "Require": {
                    "micro": ">=2.0.0"
                }
            }
        ]
    }
]
EOF
    cat > "$CONFIG_DIR/settings.json" <<EOF
{
    "micro-manage.session": "$TEST_SESSION"
}
EOF
    : > "$PRIMARY_FILE"
    mkfifo "$INPUT_FIFO"

    setsid bash -c "script -q -c \"env TERM=xterm MICRO_TRUECOLOR=0 XDG_RUNTIME_DIR='$RUNTIME_DIR' micro -config-dir '$CONFIG_DIR' '$PRIMARY_FILE'\" /dev/null < '$INPUT_FIFO' > '$MICRO_LOG' 2>&1" &
    MICRO_PID="$!"

    exec 3> "$INPUT_FIFO"
}

# Prepares environment and verifies required local tools.
# @return 0 on success.
test_setup() {
    TMP_DIR="$(mktemp -d)"
    CONFIG_DIR="$TMP_DIR/config"
    RUNTIME_DIR="$TMP_DIR/runtime"
    PLUGIN_LOAD_DIR="$CONFIG_DIR/plug/micromanage"
    INPUT_FIFO="$TMP_DIR/input.fifo"
    MICRO_LOG="$TMP_DIR/micro.log"
    PRIMARY_FILE="$TMP_DIR/primary.txt"
    SECONDARY_FILE="$TMP_DIR/secondary.txt"
    CONTROL_FIFO="$RUNTIME_DIR/micro-manage-$TEST_SESSION.fifo"

    require_command micro
    require_command script
    require_command setsid
    pass "Environment verified: using $(command -v micro)"
}

# Verifies session bootstrap and FIFO creation.
# @return 0 on success.
test_general() {
    start_micro
    wait_for_path "$CONTROL_FIFO"
    pass "General: control FIFO creation verified."
}

# Verifies command handling against a real micro session.
# @return 0 on success.
test_functional() {
    send_keys 'abc'
    send_command "save:$PRIMARY_FILE"
    expect_file "$PRIMARY_FILE" 'abc' 'save on primary file'
    pass "Functional: Save command verified."

    send_command "undo:$PRIMARY_FILE"
    send_command "save:$PRIMARY_FILE"
    expect_file "$PRIMARY_FILE" '' 'undo on primary file'
    pass "Functional: Undo command verified."

    send_command "redo:$PRIMARY_FILE"
    send_command "save:$PRIMARY_FILE"
    expect_file "$PRIMARY_FILE" 'abc' 'redo on primary file'
    pass "Functional: Redo command verified."

    printf 'disk-state' > "$PRIMARY_FILE"
    send_command "reload:$PRIMARY_FILE"
    send_keys 'y'
    send_command "save:$PRIMARY_FILE"
    expect_file "$PRIMARY_FILE" 'disk-state' 'reload on primary file'
    pass "Functional: Reload command verified."

    send_command "open:$SECONDARY_FILE"
    send_keys 'xyz'
    send_command "save:$SECONDARY_FILE"
    expect_file "$SECONDARY_FILE" 'xyz' 'open new file and save it'
    pass "Functional: Open and save on a new file verified."

    send_command "close:$SECONDARY_FILE"
    printf 'closed' > "$SECONDARY_FILE"
    send_command "save:$SECONDARY_FILE"
    expect_file "$SECONDARY_FILE" 'closed' 'close removed the secondary buffer target'
    pass "Functional: Close command verified."
}

# Entry point for the automated test suite.
# @return 0 on success.
run_tests() {
    trap cleanup EXIT

    test_setup
    test_general
    test_functional
    pass "All tests passed successfully."
}

run_tests
