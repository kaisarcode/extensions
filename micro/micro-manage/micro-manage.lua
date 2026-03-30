
VERSION = "0.1.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local mbuf = import("micro/buffer")
local os = import("os")
local filepath = import("path/filepath")
local strings = import("strings")

local PLUGIN = "micro-manage"

local fifo_job = nil
local fifo_path = nil
local pending = ""

local function bool_ok(v)
    return v ~= nil and v ~= false
end

local function shell_quote(s)
    s = tostring(s or "")
    s = s:gsub("'", [['"'"']])
    return "'" .. s .. "'"
end

local function get_runtime_dir()
    local d = os.Getenv("XDG_RUNTIME_DIR")
    if d ~= nil and d ~= "" then
        return d
    end
    return "/tmp"
end

local function get_session()
    local s = config.GetGlobalOption(PLUGIN .. ".session")
    s = tostring(s or "")
    if s == "" then
        s = "default"
    end
    return s
end

local function get_fifo_path()
    local root = get_runtime_dir()
    return root .. "/micro-manage-" .. get_session() .. ".fifo"
end

local function norm_path(p)
    if p == nil then
        return ""
    end

    p = tostring(p)
    if p == "" then
        return ""
    end

    local abs, err = filepath.Abs(p)
    if err == nil and abs ~= nil and abs ~= "" then
        p = abs
    end

    local clean = filepath.Clean(p)
    if clean ~= nil and clean ~= "" then
        p = clean
    end

    return p
end

local function all_bufpanes()
    local out = {}
    local tabs = micro.Tabs()
    if tabs == nil or tabs.List == nil then
        return out
    end

    local tablist = tabs.List
    for ti = 1, #tablist do
        local tab = tablist[ti]
        if tab ~= nil and tab.Panes ~= nil then
            local panes = tab.Panes
            for pi = 1, #panes do
                local pane = panes[pi]
                out[#out + 1] = {
                    tab_index = ti,
                    pane_index = pi,
                    tab = tab,
                    pane = pane,
                }
            end
        end
    end

    return out
end

local function pane_path(pane)
    if pane == nil or pane.Buf == nil then
        return ""
    end
    return norm_path(pane.Buf.Path or "")
end

local function find_pane_by_path(path)
    local want = norm_path(path)
    if want == "" then
        return nil
    end

    local panes = all_bufpanes()
    for _, item in ipairs(panes) do
        if pane_path(item.pane) == want then
            return item
        end
    end

    return nil
end

local function focus_item(item)
    if item == nil then
        return false
    end

    local tabs = micro.Tabs()
    if tabs == nil then
        return false
    end

    tabs:SetActive(item.tab_index - 1)
    if item.tab ~= nil then
        item.tab:SetActive(item.pane_index - 1)
    end
    return true
end

local function active_pane()
    return micro.CurPane()
end

local function open_in_new_tab(path)
    local cur = active_pane()
    if cur == nil then
        return false
    end

    cur:AddTab()

    local pane = active_pane()
    if pane == nil then
        return false
    end

    local buf = nil
    local err = nil

    local _, staterr = os.Stat(path)
    if staterr == nil then
        buf, err = mbuf.NewBufferFromFile(path)
        if err ~= nil or buf == nil then
            micro.InfoBar():Error("micro-manage: open failed: " .. tostring(err))
            return false
        end
    else
        buf = mbuf.NewBuffer("", path)
    end

    pane:OpenBuffer(buf)
    return true
end

local function do_open(path)
    local item = find_pane_by_path(path)
    if item ~= nil then
        return focus_item(item)
    end

    return open_in_new_tab(norm_path(path))
end

local function with_target(path, fn_name, fn)
    local item = find_pane_by_path(path)
    if item == nil then
        micro.InfoBar():Error("micro-manage: file not open: " .. tostring(path))
        return false
    end

    focus_item(item)

    local ok, err = pcall(fn, item.pane)
    if not ok then
        micro.InfoBar():Error("micro-manage: " .. fn_name .. " failed: " .. tostring(err))
        return false
    end

    return true
end

local function do_save(path)
    return with_target(path, "save", function(pane)
        pane:Save()
    end)
end

local function do_reload(path)
    return with_target(path, "reload", function(pane)
        pane:ReOpen()
    end)
end

local function do_close(path)
    return with_target(path, "close", function(pane)
        pane:Quit()
    end)
end

local function do_undo(path)
    return with_target(path, "undo", function(pane)
        pane:Undo()
    end)
end

local function do_redo(path)
    return with_target(path, "redo", function(pane)
        pane:Redo()
    end)
end

local function dispatch(action, path)
    action = tostring(action or "")
    path = norm_path(path)

    if action == "open" then
        return do_open(path)
    elseif action == "save" then
        return do_save(path)
    elseif action == "reload" then
        return do_reload(path)
    elseif action == "close" then
        return do_close(path)
    elseif action == "undo" then
        return do_undo(path)
    elseif action == "redo" then
        return do_redo(path)
    end

    micro.InfoBar():Error("micro-manage: unknown action: " .. action)
    return false
end

local function handle_line(line)
    line = tostring(line or "")
    if line == "" then
        return
    end

    local idx = strings.Index(line, ":")
    if idx == nil or idx < 0 then
        micro.InfoBar():Error("micro-manage: invalid command: " .. line)
        return
    end

    local action = string.sub(line, 1, idx)
    local path = string.sub(line, idx + 2)

    if action == "" or path == "" then
        micro.InfoBar():Error("micro-manage: invalid command: " .. line)
        return
    end

    dispatch(action, path)
end

local function consume_output(out)
    if out == nil or out == "" then
        return
    end

    pending = pending .. tostring(out)

    while true do
        local nl = string.find(pending, "\n", 1, true)
        if nl == nil then
            break
        end

        local line = string.sub(pending, 1, nl - 1)
        pending = string.sub(pending, nl + 1)
        line = line:gsub("\r$", "")
        handle_line(line)
    end
end

local function stop_fifo_job()
    if fifo_job ~= nil then
        shell.JobStop(fifo_job)
        fifo_job = nil
    end
end

local function remove_fifo()
    if fifo_path ~= nil and fifo_path ~= "" then
        os.Remove(fifo_path)
    end
end

local function start_fifo_job()
    stop_fifo_job()

    fifo_path = get_fifo_path()
    local root = get_runtime_dir()
    local cmd =
        "mkdir -p " .. shell_quote(root) .. " && " ..
        "rm -f " .. shell_quote(fifo_path) .. " && " ..
        "mkfifo " .. shell_quote(fifo_path) .. " && " ..
        "while true; do cat < " .. shell_quote(fifo_path) .. "; done"

    fifo_job = shell.JobStart(
        cmd,
        function(out, userargs)
            consume_output(out)
        end,
        function(out, userargs)
            if out ~= nil and out ~= "" then
                micro.InfoBar():Error("micro-manage: " .. tostring(out))
            end
        end,
        function(out, userargs)
        end
    )
end

function init()
    config.RegisterGlobalOption(PLUGIN, "session", "default")
    start_fifo_job()
end

function deinit()
    stop_fifo_job()
    remove_fifo()
end
