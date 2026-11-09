-- Plain-Lua tests with fake accessibility elements. Run from the repo root: lua test/attempt_test.lua
package.path = "./?.lua;" .. package.path
local ax = require("outlook_font.ax")
local outlook = require("outlook_font.outlook")
local config = require("outlook_font.config")

local function el(attrs, children)
    local e = { attrs = attrs, pressed = 0 }
    e.attrs.AXChildren = children or {}
    for _, c in ipairs(e.attrs.AXChildren) do
        c.attrs.AXParent = e
    end
    function e:attributeValue(k)
        return self.attrs[k]
    end
    function e:performAction()
        self.pressed = self.pressed + 1
        if self.onPress then
            return self.onPress()
        end
        return self
    end
    function e:setAttributeValue(k, v)
        if self.onSet then
            return self.onSet(k, v)
        end
        return self
    end
    return e
end

-- Fresh deps/app per test. `window` is added to AXWindows only once settings are opened.
-- Like real Outlook, only "Preferences…" exists for a window with a slider (Legacy) and only
-- "Settings…" otherwise (New). opts: existing = windows already open, menu = the one menu item
-- that exists (overrides that rule), menu_fails = no menu item matches (the window then appears
-- on cmd+, instead), focused = AXFocusedWindow of the app.
local function setup(window, opts)
    opts = opts or {}
    local now = 0
    local keys, targets = {}, {}
    local menu = opts.menu
    if menu == nil then
        menu = (window and ax.find_first_by_role(window, "AXSlider")) and "Preferences…" or "Settings…"
    end
    local axapp = el({ AXWindows = {}, AXFocusedWindow = opts.focused })
    local function open_window()
        if not window then
            return
        end
        local all = {}
        for _, w in ipairs(opts.existing or {}) do
            table.insert(all, w)
        end
        table.insert(all, window)
        axapp.attrs.AXWindows = all -- new table: `before` snapshot must not change
    end
    axapp.attrs.AXWindows = opts.existing or {}
    local deps = {
        timer = {
            secondsSinceEpoch = function()
                return now
            end,
            waitUntil = function(pred, act)
                while not pred() do
                    now = now + 0.05
                end
                act()
            end,
            doAfter = function(_, fn)
                fn()
            end,
        },
        eventtap = {
            keyStroke = function(mods, key, _, target)
                table.insert(keys, table.concat(mods, "+") .. "+" .. key)
                table.insert(targets, target)
                if key == "," then
                    open_window()
                end
            end,
        },
        keys = keys,
        targets = targets,
    }
    deps.axuielement = {
        applicationElement = function()
            return axapp
        end,
    }
    local app = {
        pid = function()
            return 1
        end,
        selectMenuItem = function(_, path)
            if opts.menu_fails or path[#path] ~= menu then
                return false
            end
            open_window()
            return true
        end,
    }
    return deps, config.defaults(), app
end

local function run(deps, cfg, app, is_plus)
    local res
    outlook.attempt(deps, cfg, app, is_plus, function(ok, err, retry, at_limit)
        res = { ok = ok, err = err, retry = retry, at_limit = at_limit }
    end)
    assert(res, "callback was not called")
    return res
end

local function slider_window(slider)
    return el({ AXRole = "AXWindow", AXTitle = "Outlook Preferences" }, { slider })
end

local function new_window(smaller, larger)
    return el({ AXRole = "AXWindow", AXTitle = "Settings" }, {
        el({ AXRole = "AXGroup" }, {
            el({ AXRole = "AXStaticText", AXValue = "Text display size" }),
            smaller,
            larger,
        }),
    })
end

local tests = {}

function tests.slider_ax_error_is_not_retryable()
    local slider = el({ AXRole = "AXSlider", AXValue = 1, AXMinValue = 0, AXMaxValue = 2 })
    slider.onSet = function()
        return nil
    end
    local deps, cfg, app = setup(slider_window(slider))
    local r = run(deps, cfg, app, true)
    assert(r.ok == false, "expected failure")
    assert(not r.retry, "AX error must not be retryable")
end

function tests.button_ax_error_is_not_retryable()
    local smaller = el({ AXRole = "AXButton", AXTitle = "Smaller" })
    local larger = el({ AXRole = "AXButton", AXTitle = "Larger" })
    larger.onPress = function()
        return nil
    end
    local deps, cfg, app = setup(new_window(smaller, larger))
    local r = run(deps, cfg, app, true)
    assert(r.ok == false, "expected failure")
    assert(not r.retry, "AX error must not be retryable")
end

-- hs.axuielement returns false for kAXErrorCannotComplete, which includes a timeout after which
-- the press may still land; retrying could change the size twice.
function tests.button_cannot_complete_is_not_retryable()
    local smaller = el({ AXRole = "AXButton", AXTitle = "Smaller" })
    local larger = el({ AXRole = "AXButton", AXTitle = "Larger" })
    larger.onPress = function()
        return false
    end
    local deps, cfg, app = setup(new_window(smaller, larger))
    local r = run(deps, cfg, app, true)
    assert(r.ok == false, "expected failure")
    assert(not r.retry, "a press that could not complete must not be retried")
end

function tests.legacy_slider_increase()
    local slider = el({ AXRole = "AXSlider", AXValue = 1, AXMinValue = 0, AXMaxValue = 2 })
    local set_to
    slider.onSet = function(_, v)
        set_to = v
        return slider
    end
    local deps, cfg, app = setup(slider_window(slider))
    local r = run(deps, cfg, app, true)
    assert(r.ok == true, tostring(r.err))
    assert(set_to == 2, "slider set to " .. tostring(set_to))
end

function tests.new_outlook_increase_presses_larger_only()
    local smaller = el({ AXRole = "AXButton", AXTitle = "Smaller" })
    local larger = el({ AXRole = "AXButton", AXTitle = "Larger" })
    local deps, cfg, app = setup(new_window(smaller, larger))
    local r = run(deps, cfg, app, true)
    assert(r.ok == true, tostring(r.err))
    assert(larger.pressed == 1 and smaller.pressed == 0, "wrong buttons pressed")
end

local function size_buttons()
    return el({ AXRole = "AXButton", AXTitle = "Smaller" }), el({ AXRole = "AXButton", AXTitle = "Larger" })
end

local function make_slider(value)
    return el({ AXRole = "AXSlider", AXValue = value, AXMinValue = 0, AXMaxValue = 2 })
end

function tests.mail_window_is_never_acted_on()
    local delete = el({ AXRole = "AXButton", AXTitle = "Delete" })
    local reply = el({ AXRole = "AXButton", AXTitle = "Reply" })
    local inbox = el({ AXRole = "AXWindow", AXTitle = "Inbox" }, {
        el({ AXRole = "AXStaticText", AXValue = "Tip: change the Text display size in Settings" }),
        delete,
        reply,
    })
    local deps, cfg, app = setup(nil, { existing = { inbox } })
    local r = run(deps, cfg, app, true)
    assert(r.ok == false, "expected failure")
    assert(delete.pressed == 0 and reply.pressed == 0, "mail window was acted on")
    assert(#deps.keys == 0, "unexpected keystrokes: " .. table.concat(deps.keys, ","))
    assert(r.err:find("Timed out", 1, true), r.err)
end

function tests.closes_found_window_with_its_close_button()
    local smaller, larger = size_buttons()
    local win = new_window(smaller, larger)
    local close_btn = el({ AXRole = "AXButton" })
    win.attrs.AXCloseButton = close_btn
    local deps, cfg, app = setup(win)
    local r = run(deps, cfg, app, true)
    assert(r.ok == true, tostring(r.err))
    assert(close_btn.pressed == 1, "close button pressed " .. close_btn.pressed .. " times")
    assert(#deps.keys == 0, "unexpected keystrokes: " .. table.concat(deps.keys, ","))
end

function tests.no_close_button_unfocused_sends_no_keystroke()
    local smaller, larger = size_buttons()
    local deps, cfg, app = setup(new_window(smaller, larger))
    local r = run(deps, cfg, app, true)
    assert(r.ok == true, tostring(r.err))
    assert(#deps.keys == 0, "unexpected keystrokes: " .. table.concat(deps.keys, ","))
end

function tests.no_close_button_focused_sends_cmd_w()
    local smaller, larger = size_buttons()
    local win = new_window(smaller, larger)
    local deps, cfg, app = setup(win, { focused = win })
    local r = run(deps, cfg, app, true)
    assert(r.ok == true, tostring(r.err))
    assert(#deps.keys == 1 and deps.keys[1] == "cmd+w", "keystrokes: " .. table.concat(deps.keys, ","))
    assert(deps.targets[1] == app, "cmd+w must be sent to Outlook, not the front app")
end

function tests.close_button_failure_falls_back_to_focused_cmd_w()
    local smaller, larger = size_buttons()
    local win = new_window(smaller, larger)
    local close_btn = el({ AXRole = "AXButton" })
    close_btn.onPress = function()
        return false
    end
    win.attrs.AXCloseButton = close_btn
    local deps, cfg, app = setup(win, { focused = win })
    local r = run(deps, cfg, app, true)
    assert(r.ok == true, tostring(r.err))
    assert(close_btn.pressed == 1, "close button not tried")
    assert(#deps.keys == 1 and deps.keys[1] == "cmd+w", "keystrokes: " .. table.concat(deps.keys, ","))
end

function tests.translated_menu_falls_back_to_cmd_comma()
    local smaller, larger = size_buttons()
    local deps, cfg, app = setup(new_window(smaller, larger), { menu_fails = true })
    local r = run(deps, cfg, app, true)
    assert(r.ok == true, tostring(r.err))
    assert(deps.keys[1] == "cmd+,", "keystrokes: " .. table.concat(deps.keys, ","))
    assert(deps.targets[1] == app, "cmd+, must be sent to Outlook, not the front app")
    assert(larger.pressed == 1 and smaller.pressed == 0, "wrong buttons pressed")
end

function tests.cmd_comma_with_slider_window_uses_legacy_step()
    local slider = make_slider(0)
    local set_to
    slider.onSet = function(_, v)
        set_to = v
        return slider
    end
    local deps, cfg, app = setup(slider_window(slider), { menu_fails = true })
    local r = run(deps, cfg, app, true)
    assert(r.ok == true, tostring(r.err))
    assert(deps.keys[1] == "cmd+,", "keystrokes: " .. table.concat(deps.keys, ","))
    assert(set_to == 1, "slider set to " .. tostring(set_to))
end

function tests.settings_menu_decides_new_even_with_a_slider()
    local smaller, larger = size_buttons()
    local slider = make_slider(0)
    local set_called = false
    slider.onSet = function()
        set_called = true
        return slider
    end
    local win = new_window(smaller, larger)
    table.insert(win.attrs.AXChildren, slider)
    local deps, cfg, app = setup(win, { menu = "Settings…" })
    local r = run(deps, cfg, app, true)
    assert(r.ok == true, tostring(r.err))
    assert(larger.pressed == 1 and not set_called, "Settings… must take the New Outlook step")
end

function tests.new_outlook_disabled_button_reports_limit()
    local smaller, larger = size_buttons()
    larger.attrs.AXEnabled = false
    local deps, cfg, app = setup(new_window(smaller, larger))
    local r = run(deps, cfg, app, true)
    assert(larger.pressed == 0, "disabled button must not be pressed")
    assert(r.ok == false and not r.retry and r.at_limit == true, "expected non-retryable at_limit failure")
    assert(r.err:find("largest", 1, true), r.err)
end

function tests.only_new_windows_are_considered()
    local old_smaller, old_larger = size_buttons()
    local smaller, larger = size_buttons()
    local old = new_window(old_smaller, old_larger)
    local deps, cfg, app = setup(new_window(smaller, larger), { existing = { old } })
    local r = run(deps, cfg, app, true)
    assert(r.ok == true, tostring(r.err))
    assert(larger.pressed == 1, "new window's button not pressed")
    assert(old_larger.pressed == 0 and old_smaller.pressed == 0, "pre-existing window was acted on")
end

function tests.legacy_at_max_reports_limit()
    local slider = make_slider(2)
    local set_called = false
    slider.onSet = function()
        set_called = true
        return slider
    end
    local deps, cfg, app = setup(slider_window(slider))
    local r = run(deps, cfg, app, true)
    assert(not set_called, "setAttributeValue must not be called at the limit")
    assert(r.ok == false and not r.retry and r.at_limit == true, "expected non-retryable at_limit failure")
    assert(r.err:find("largest", 1, true), r.err)
end

function tests.config_sanitize()
    local cfg = config.sanitize({ appNames = { "X" } })
    assert(#cfg.appNames == 1 and cfg.appNames[1] == "X", "appNames must be replaced")

    local defaults = config.defaults()
    cfg = config.sanitize({ overlayText = {} })
    assert(cfg.overlayText.larger == defaults.overlayText.larger, "overlayText default lost")

    local warnings
    cfg, warnings = config.sanitize({ overlayDuration = "long" })
    assert(cfg.overlayDuration == 1.2, "overlayDuration not reset")
    assert(#warnings == 1, "expected exactly one warning, got " .. #warnings)
end

-- Runs fn with io.open replaced by stub, so tests never touch the real filesystem.
local function with_open(stub, fn)
    local real_open = io.open
    io.open = stub -- luacheck: ignore 122
    local ok, err = pcall(fn)
    io.open = real_open -- luacheck: ignore 122
    assert(ok, err)
end

function tests.config_load_keeps_decoder_message()
    local cfg, problems
    with_open(function()
        return {
            read = function()
                return '{ "showOverlay": false, }'
            end,
            close = function() end,
        }
    end, function()
        cfg, problems = config.load({
            path = "/fake/outlook-font.json",
            decode = function()
                error("Badly formed object around character 17")
            end,
        })
    end)
    assert(cfg == nil and problems[1], "expected a problem")
    assert(problems[1].message:find("Badly formed object", 1, true), problems[1].message)
end

local function count(t)
    return #t
end

function tests.config_invalid_toggle_resets_with_one_warning()
    local defaults = config.defaults()
    local cfg, warnings = config.sanitize({
        hotkeys = {
            increase = { mods = { "cmd" }, key = "g" },
            decrease = { mods = { "cmd" }, key = "k" },
            toggle = { mods = "ctrl", key = "t" },
        },
    })
    assert(cfg.hotkeys.toggle.key == defaults.hotkeys.toggle.key and #cfg.hotkeys.toggle.mods == 3, "toggle not reset")
    assert(cfg.hotkeys.increase.mods[1] == "cmd", "valid increase was changed")
    assert(count(warnings) == 1, "expected exactly one warning, got " .. count(warnings))
end

function tests.config_rejects_non_positive_timings()
    local cfg, warnings = config.sanitize({ delays = { waitInterval = 0 } })
    assert(cfg.delays.waitInterval == 0.05 and count(warnings) == 1, "waitInterval " .. cfg.delays.waitInterval)
    cfg = config.sanitize({ delays = { timeout = -1 } })
    assert(cfg.delays.timeout == 3, "timeout " .. cfg.delays.timeout)
    cfg = config.sanitize({ retry = { interval = -1 } })
    assert(cfg.retry.interval == 0.2, "interval " .. cfg.retry.interval)
    cfg, warnings = config.sanitize({ retry = { interval = 0 } })
    assert(cfg.retry.interval == 0 and count(warnings) == 0, "zero retry interval must be allowed")
end

function tests.config_load_strips_comments_and_keeps_strings()
    local opened, received
    local raw = table.concat({
        "{ // line comment",
        '  "a": "http://example.com", /* block comment */',
        '  "b": "Taille d\'affichage"',
        "}",
    }, "\n")
    with_open(function(path)
        opened = path
        return {
            read = function()
                return raw
            end,
            close = function() end,
        }
    end, function()
        config.load({
            path = "/fake/dir/outlook-font.json",
            decode = function(text)
                received = text
                return {}
            end,
        })
    end)
    assert(opened == "/fake/dir/outlook-font.json", "opened " .. tostring(opened))
    assert(received:find('"http://example.com"', 1, true), received)
    assert(received:find('"Taille d\'affichage"', 1, true), received)
    assert(not received:find("comment", 1, true), received)
end

-- Builds a fake `hs`, installs it as a global and loads outlook-font.lua fresh.
local function load_of(opts)
    opts = opts or {}
    local now = 0
    local hs = { configdir = "/fake/hs", notifications = {}, bound = {} }
    local axapp = el({ AXWindows = {} })
    hs.axapp = axapp
    hs.app = {
        pid = function()
            return 1
        end,
        activate = function() end,
        isFrontmost = function()
            return true
        end,
        selectMenuItem = function(_, path)
            return opts.on_menu ~= nil and opts.on_menu(axapp, path) == true
        end,
    }
    hs.application = {
        get = function()
            return hs.app
        end,
        find = function() end,
    }
    hs.axuielement = {
        applicationElement = function()
            return axapp
        end,
    }
    hs.canvas = {}
    hs.eventtap = { keyStroke = function() end }
    hs.hotkey = {
        bind = function(_, key)
            if key == "+" then
                error("Invalid key: +")
            end
            table.insert(hs.bound, key)
        end,
    }
    hs.json = { decode = function() end }
    hs.notify = {
        new = function(t)
            table.insert(hs.notifications, t.informativeText)
            return { send = function() end }
        end,
    }
    hs.screen = {}
    hs.timer = {
        secondsSinceEpoch = function()
            return now
        end,
        waitUntil = function(pred, act)
            while not pred() do
                now = now + 0.05
            end
            act()
        end,
        doAfter = function(_, fn)
            fn()
        end,
    }
    _G.hs = hs
    package.loaded["outlook-font"] = nil
    return require("outlook-font"), hs
end

function tests.bind_hotkeys_survives_invalid_key()
    local of, hs = load_of()
    local ok, err = pcall(of.bindHotkeys, {
        increase = { mods = { "cmd" }, key = "+" },
        decrease = { mods = { "cmd" }, key = "k" },
        toggle = { mods = { "cmd" }, key = "t" },
    })
    assert(ok, err)
    assert(table.concat(hs.bound, ",") == "k,t", "bound: " .. table.concat(hs.bound, ","))
    assert(#hs.notifications == 1 and hs.notifications[1]:find("increase", 1, true), table.concat(hs.notifications))
end

function tests.bind_hotkeys_reports_missing_binding()
    local of, hs = load_of()
    of.bindHotkeys({ decrease = { mods = { "cmd" }, key = "k" } })
    assert(table.concat(hs.bound, ",") == "k", "bound: " .. table.concat(hs.bound, ","))
    assert(#hs.notifications == 1 and hs.notifications[1]:find("increase hotkey needs", 1, true), hs.notifications[1])
end

function tests.loadconfig_reads_from_hs_configdir()
    local of
    local opened
    of = load_of()
    with_open(function(path)
        opened = path
        return nil
    end, function()
        of.loadConfig()
    end)
    assert(opened == "/fake/hs/outlook-font.json", "opened " .. tostring(opened))
end

-- Hammerspoon stops a timer when its userdata is garbage-collected, so a pending doAfter must stay referenced.
function tests.pending_timer_survives_garbage_collection()
    local of, hs = load_of()
    with_open(function()
        return nil
    end, of.loadConfig)
    local collected = false
    hs.timer.doAfter = function()
        return setmetatable({}, {
            __gc = function()
                collected = true
            end,
        })
    end
    assert(of.adjustTextSize(true, function() end))
    collectgarbage()
    collectgarbage()
    assert(not collected, "pending doAfter timer was garbage-collected")
end

function tests.retryable_failure_retries_then_succeeds()
    local slider = make_slider(nil) -- no AXValue on the first attempt: a retryable error
    local set_to
    slider.onSet = function(_, v)
        set_to = v
        return slider
    end
    local menus = 0
    local of, hs = load_of({
        on_menu = function(axapp, path)
            if path[#path] ~= "Preferences…" then
                return false
            end
            menus = menus + 1
            if menus == 2 then
                slider.attrs.AXValue = 1
            end
            axapp.attrs.AXWindows = { slider_window(slider) }
            return true
        end,
    })
    with_open(function()
        return nil
    end, of.loadConfig)
    of.cfg.showOverlay = false

    local calls, result = 0, nil
    assert(of.adjustTextSize(true, function(ok)
        calls = calls + 1
        result = ok
    end))
    assert(menus == 2, "expected one retry, menus opened " .. menus)
    assert(calls == 1 and result == true, "callback calls " .. calls .. ", result " .. tostring(result))
    assert(set_to == 2 and #hs.notifications == 0, table.concat(hs.notifications, "|"))
    assert(of.adjustTextSize(true, function() end), "busy must be cleared after the retry succeeded")
end

function tests.toggle_at_limit_flips_direction()
    local slider = make_slider(2)
    local set_to
    slider.onSet = function(_, v)
        set_to = v
        slider.attrs.AXValue = v
        return slider
    end
    local of, hs = load_of({
        on_menu = function(axapp, path)
            if path[#path] ~= "Preferences…" then
                return false
            end
            axapp.attrs.AXWindows = { slider_window(slider) }
            return true
        end,
    })
    with_open(function()
        return nil
    end, function()
        of.loadConfig()
    end)
    of.cfg.showOverlay = false

    local result
    assert(of.toggleTextSize(function(ok)
        result = ok
    end))
    assert(result == false and of.toggleState == true, "first press should hit the limit")
    assert(hs.notifications[#hs.notifications]:find("largest", 1, true), table.concat(hs.notifications, "|"))
    assert(set_to == nil, "slider must not be set at the limit")

    assert(of.toggleTextSize(function(ok)
        result = ok
    end))
    assert(result == true and set_to == 1, "second press should decrease, set_to " .. tostring(set_to))
end

local names = {}
for name in pairs(tests) do
    table.insert(names, name)
end
table.sort(names)

local failed = 0
for _, name in ipairs(names) do
    local ok, err = pcall(tests[name])
    if ok then
        print("ok " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(err))
    end
end
os.exit(failed == 0 and 0 or 1)
