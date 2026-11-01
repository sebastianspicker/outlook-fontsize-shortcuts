-- ~/.hammerspoon/outlook-font.lua
--[[
outlook-font: Hammerspoon module that changes the "Text display size" of New and
Legacy Outlook for Mac.

This file is the public API (`require("outlook-font")`) and the runtime policy:
config loading, the busy guard, retries, toggle state and user feedback.
Outlook UI automation lives in outlook_font/outlook.lua, configuration in
outlook_font/config.lua, notifications and the overlay in outlook_font/feedback.lua.
It only runs inside Hammerspoon: the hs.* modules are read when it loads.
--]]

local config = require("outlook_font.config")
local feedback = require("outlook_font.feedback")
local outlook = require("outlook_font.outlook")

local M = {}

-- Public state. `cfg` is replaced by loadConfig(); `toggleState` is the direction
-- of the last successful change, or of the last press that hit a size limit
-- (true = larger).
M.cfg = config.defaults()
M.toggleState = false

local deps = {
    application = hs.application,
    axuielement = hs.axuielement,
    canvas = hs.canvas,
    eventtap = hs.eventtap,
    hotkey = hs.hotkey,
    json = hs.json,
    notify = hs.notify,
    screen = hs.screen,
    timer = hs.timer,
}
local fb = feedback.new(deps)
local config_loaded = false
local busy = false

local function notify(title, message)
    fb.notify(title, message)
end
M.notify = notify

local function show_overlay(isPlus)
    if not M.cfg.showOverlay then
        return
    end
    fb.overlay(isPlus and M.cfg.overlayText.larger or M.cfg.overlayText.smaller, M.cfg.overlayDuration)
end

--------------------------------------------------------------------------------
-- Config
--------------------------------------------------------------------------------
-- Loads the config file once; later calls are no-ops (use hs.reload() to re-read).
function M.loadConfig()
    if config_loaded then
        return
    end
    config_loaded = true

    local cfg, problems = config.load({
        path = hs.configdir .. "/outlook-font.json",
        decode = deps.json.decode,
    })
    if cfg then
        M.cfg = cfg
    end
    for _, problem in ipairs(problems) do
        notify(problem.title, problem.message)
    end
end

--------------------------------------------------------------------------------
-- Text size changes
--------------------------------------------------------------------------------
-- Runs the synchronous part of adjustTextSize with `busy` already set.
local function start_change(isPlus, callback)
    M.loadConfig()

    local app = outlook.find_app(deps, M.cfg)
    if not app then
        notify("Outlook Not Found", "Launch Outlook and try again.")
        busy = false
        return false
    end

    if not outlook.ax_app(deps, app) then
        notify(
            "Accessibility Required",
            "Grant access in System Settings → Privacy & Security → Accessibility, then restart Hammerspoon."
        )
        busy = false
        return false
    end

    local completed = false
    local function done(ok)
        if completed then
            return
        end
        completed = true
        busy = false
        if type(callback) == "function" then
            callback(ok)
        end
    end

    local function run_attempt(attempt)
        local started, err = pcall(outlook.attempt, deps, M.cfg, app, isPlus, function(ok, message, retryable, at_limit)
            if ok then
                M.toggleState = isPlus
                -- The size already changed; a broken overlay must not turn this into a failure.
                pcall(show_overlay, isPlus)
                done(true)
            elseif retryable and attempt <= M.cfg.retry.attempts then
                -- shortcut: assumes the window closed by the failed attempt is gone after retry.interval;
                -- if retries end in "Timed out", wait for it to disappear before retrying.
                deps.timer.doAfter(M.cfg.retry.interval, function()
                    run_attempt(attempt + 1)
                end)
            elseif at_limit then
                -- Flip the toggle so the next toggle goes the other way instead of hitting the same limit.
                M.toggleState = isPlus
                notify("Outlook Font", message)
                done(false)
            else
                notify("Outlook Font", message)
                done(false)
            end
        end)
        if not started then
            notify("Outlook Font", tostring(err))
            done(false)
        end
    end

    app:activate()
    deps.timer.doAfter(M.cfg.delays.activate, function()
        run_attempt(1)
    end)
    return true
end

-- Starts an asynchronous change. Returns false (without calling `callback`) when it
-- cannot start: another change is running, Outlook is not found, or Accessibility
-- access is not granted. Otherwise returns true and calls
-- `callback(ok)` exactly once when the change finished.
function M.adjustTextSize(isPlus, callback)
    if busy then
        return false
    end
    busy = true

    local ok, started = pcall(start_change, isPlus, callback)
    if not ok then
        -- An unexpected error before the change started must not leave every later
        -- request ignored until Hammerspoon reloads; the error still propagates.
        busy = false
        error(started, 0)
    end
    return started
end

-- Changes the size in the opposite direction of the last successful change.
function M.toggleTextSize(callback)
    return M.adjustTextSize(not M.toggleState, callback)
end

--------------------------------------------------------------------------------
-- Hotkeys
--------------------------------------------------------------------------------
-- mapping = { increase = {mods, key}, decrease = {mods, key}, toggle = {mods, key} | false | nil,
--             onComplete = function(ok, direction) } with direction "increase" | "decrease" | "toggle".
-- A binding Hammerspoon rejects (e.g. an unknown key name) is reported and skipped.
function M.bindHotkeys(mapping)
    local hotkey = deps.hotkey
    if type(mapping) ~= "table" then
        notify("Outlook Font", "Hotkey configuration error: mapping must be a table. Check init.lua.")
        return
    end

    local onComplete = type(mapping.onComplete) == "function" and mapping.onComplete or nil
    local function reporter(direction)
        return function(ok)
            if onComplete then
                onComplete(ok, direction)
            end
        end
    end

    local function bind(name, binding, fn)
        if type(binding) ~= "table" then
            notify("Outlook Font", "The " .. name .. " hotkey needs .mods and .key. Check init.lua.")
            return
        end
        local ok, err = pcall(hotkey.bind, binding.mods, binding.key, fn)
        if not ok then
            notify("Outlook Font", "Could not bind the " .. name .. " hotkey: " .. tostring(err))
        end
    end

    bind("increase", mapping.increase, function()
        M.adjustTextSize(true, reporter("increase"))
    end)
    bind("decrease", mapping.decrease, function()
        M.adjustTextSize(false, reporter("decrease"))
    end)
    if mapping.toggle then
        bind("toggle", mapping.toggle, function()
            M.toggleTextSize(reporter("toggle"))
        end)
    end
end

return M
