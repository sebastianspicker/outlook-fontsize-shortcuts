local ax = require("outlook_font.ax")

local M = {}

local BUNDLE_ID = "com.microsoft.Outlook"

local MSG_NO_AX = "Cannot access Outlook UI. Check Accessibility permissions and restart Hammerspoon."
local MSG_WINDOW_TIMEOUT = "Timed out waiting for the settings window. If Outlook's Settings window is already open, "
    .. "close it and try again; otherwise increase delays.timeout in outlook-font.json."
local MSG_PANE_TIMEOUT = "Timed out waiting for the General pane. "
    .. "Try increasing delays.timeout in outlook-font.json."
local MSG_NO_SLIDER = "Font size slider not found in Preferences. Outlook's UI may have changed."
local MSG_SLIDER_RANGE = "Cannot read slider range. Outlook's UI may have changed."
local MSG_SLIDER_SET = "Could not move the font size slider. Check Accessibility permissions."
local MSG_AT_MAX = "Text is already at the largest size."
local MSG_AT_MIN = "Text is already at the smallest size."
local MSG_NO_GENERAL = "'General' tile not found in settings. Outlook's UI may have changed."
local MSG_NO_BUTTONS = "Size buttons not found in settings. Outlook's UI may have changed."
local MSG_BUTTON_PRESS = "Could not click the size button. Outlook's UI may have changed."

function M.find_app(deps, cfg)
    -- 1) Try by bundle ID (most robust)
    local app = deps.application.get(BUNDLE_ID)
    if app then
        return app
    end

    -- 2) Fallback to names
    for _, name in ipairs(cfg.appNames or {}) do
        app = deps.application.find(name)
        if app then
            return app
        end
    end
    return nil
end

function M.ax_app(deps, app)
    local pid = app and app.pid and app:pid() or nil
    if not pid then
        return nil
    end
    return deps.axuielement.applicationElement(pid)
end

local function get_windows(ax_app)
    if not ax_app then
        return {}
    end
    local ok, value = pcall(function()
        return ax_app:attributeValue("AXWindows")
    end)
    if ok and value then
        return value
    end
    return {}
end

-- Returns the windows in current_windows that are not in prev_windows (AX elements compare with ==).
local function find_new_windows(prev_windows, current_windows)
    local found = {}
    for _, w in ipairs(current_windows or {}) do
        local known = false
        for _, p in ipairs(prev_windows or {}) do
            if w == p then
                known = true
                break
            end
        end
        if not known then
            table.insert(found, w)
        end
    end
    return found
end

local function has_any_text(win, labels)
    return ax.find_role_or_static_text(win, nil, labels) ~= nil
end

-- True if window looks like Settings/Preferences: slider, personal-settings header, or size label.
-- One tree walk per candidate; only windows that appeared after opening Settings are checked.
local function looks_like_settings(win, cfg)
    if not win then
        return false
    end
    local labels = {}
    for _, list in ipairs({ cfg.headerLabels or {}, cfg.labelTexts or {} }) do
        table.move(list, 1, #list, #labels + 1, labels)
    end
    return ax.find_role_or_static_text(win, "AXSlider", labels) ~= nil
end

-- hs.axuielement's performAction returns the element on success, false on
-- kAXErrorCannotComplete (which includes timeouts), and nil + error otherwise.
local function press(elem)
    if not elem then
        return false
    end
    local ok, result = pcall(function()
        return elem:performAction("AXPress")
    end)
    return ok and result ~= nil and result ~= false
end

-- Closes `win` itself; a keystroke would hit whatever window has focus, even in another app.
local function close_window(deps, app, win)
    local btn = win:attributeValue("AXCloseButton")
    if btn and btn:performAction("AXPress") then
        return
    end
    local ax_app = M.ax_app(deps, app)
    if ax_app and ax_app:attributeValue("AXFocusedWindow") == win then
        deps.eventtap.keyStroke({ "cmd" }, "w", nil, app)
    end
end

-- Performs ONE attempt and calls cb(ok, err, retryable, at_limit) exactly once.
-- at_limit is true when the size control was already at its limit (nothing changed).
function M.attempt(deps, cfg, app, isPlus, cb)
    local finished = false
    local win = nil
    local mutated = false

    local function finish(ok, err, retryable, at_limit)
        if finished then
            return
        end
        finished = true
        cb(ok, err, retryable, at_limit)
    end

    -- Closes the settings window (only once one was found); never throws.
    local function close()
        if win then
            pcall(close_window, deps, app, win)
        end
    end

    local function fail(err, retryable, at_limit)
        if finished then
            return
        end
        close()
        finish(false, tostring(err), (retryable and not mutated) or false, at_limit or false)
    end

    local function succeed()
        if finished then
            return
        end
        close()
        finish(true)
    end

    -- Wraps a callback so any thrown error reaches cb (retryable only before mutation).
    -- Errors raised after cb already ran (i.e. by cb itself) are re-raised so they
    -- surface in the Hammerspoon console instead of vanishing.
    local function guarded(fn)
        return function(...)
            local ok, err = pcall(fn, ...)
            if not ok then
                if finished then
                    error(err, 0)
                end
                fail(err, true)
            end
        end
    end

    -- Polls check() until truthy; calls on_ready(), or on_timeout() once the timeout elapsed.
    local function wait_for(check, on_ready, on_timeout)
        local start_time = deps.timer.secondsSinceEpoch()
        local timed_out = false
        local poll_err = nil
        deps.timer.waitUntil(
            function()
                local ok, result = pcall(function()
                    if deps.timer.secondsSinceEpoch() - start_time > cfg.delays.timeout then
                        timed_out = true
                        return true
                    end
                    return check()
                end)
                if not ok then
                    poll_err = result
                    return true
                end
                return result
            end,
            guarded(function()
                if poll_err ~= nil then
                    error(poll_err, 0)
                end
                if timed_out then
                    on_timeout()
                else
                    on_ready()
                end
            end),
            cfg.delays.waitInterval
        )
    end

    local function legacy_step()
        local slider = ax.find_first_by_role(win, "AXSlider")
        if not slider then
            error(MSG_NO_SLIDER, 0)
        end
        local val = slider:attributeValue("AXValue")
        local minv = slider:attributeValue("AXMinValue")
        local maxv = slider:attributeValue("AXMaxValue")
        if val == nil or minv == nil or maxv == nil then
            error(MSG_SLIDER_RANGE, 0)
        end
        -- Legacy Outlook slider uses integer steps (Standard/Large/Larger)
        local newv = isPlus and math.min(val + 1, maxv) or math.max(val - 1, minv)
        if newv == val then
            fail(isPlus and MSG_AT_MAX or MSG_AT_MIN, false, true)
            return
        end
        mutated = true
        if not slider:setAttributeValue("AXValue", newv) then
            error(MSG_SLIDER_SET, 0)
        end
        succeed()
    end

    local function press_size_button()
        local buttons = ax.find_button_group_near_labels(win, cfg.labelTexts)
        if not buttons then
            error(MSG_NO_BUTTONS, 0)
        end
        local btn = ax.button_by_size_label(buttons, cfg.overlayText.larger, cfg.overlayText.smaller, isPlus)
        if not btn then
            btn = isPlus and buttons[#buttons] or buttons[1]
        end
        if btn:attributeValue("AXEnabled") == false then
            -- A disabled size button means the text is already at that limit.
            fail(isPlus and MSG_AT_MAX or MSG_AT_MIN, false, true)
            return
        end
        -- Once pressed, never retry: false (kAXErrorCannotComplete, e.g. a timeout) or an error
        -- does not prove the press failed, and a retry could change the size twice.
        mutated = true
        local ok, result = pcall(function()
            return btn:performAction("AXPress")
        end)
        if not ok or not result then
            error(MSG_BUTTON_PRESS, 0)
        end
        succeed()
    end

    local function new_outlook_step()
        local pressed = false
        local header
        for _, hl in ipairs(cfg.headerLabels or {}) do
            header = ax.find_static_text(win, hl)
            if header then
                break
            end
        end
        if header then
            local parent = header:attributeValue("AXParent")
            local siblings = parent and parent:attributeValue("AXChildren") or {}
            local header_idx
            for i, v in ipairs(siblings) do
                if v == header then
                    header_idx = i
                    break
                end
            end
            local general = header_idx and header_idx > 1 and siblings[header_idx - 1] or nil
            pressed = press(general)
        end
        if not pressed then
            for _, label in ipairs(cfg.generalLabels or {}) do
                local label_node = ax.find_static_text(win, label)
                if label_node then
                    local btn = ax.find_ancestor_by_role(label_node, "AXButton") or label_node
                    if press(btn) then
                        pressed = true
                        break
                    end
                end
            end
        end
        if not pressed and not has_any_text(win, cfg.labelTexts) then
            error(MSG_NO_GENERAL, 0)
        end

        wait_for(
            function()
                return has_any_text(win, cfg.labelTexts)
            end,
            press_size_button,
            function()
                fail(MSG_PANE_TIMEOUT, false)
            end
        )
    end

    local function run_step(legacy)
        if legacy then
            legacy_step()
        else
            new_outlook_step()
        end
    end

    local function try_select_menu(menu_path)
        local ok, selected = pcall(function()
            return app:selectMenuItem(menu_path)
        end)
        return ok and selected == true
    end

    local function body()
        local ax_app = M.ax_app(deps, app)
        if not ax_app then
            fail(MSG_NO_AX, false)
            return
        end

        local before = get_windows(ax_app)

        -- The menu that opened the window tells New from Legacy. Translated menus match neither
        -- name; then ⌘, (the same key in every language) opens settings and a slider means Legacy.
        local legacy
        if try_select_menu(cfg.settingsMenu) then
            legacy = false
        elseif try_select_menu(cfg.preferencesMenu) then
            legacy = true
        else
            deps.eventtap.keyStroke({ "cmd" }, ",", nil, app)
        end

        local candidate
        wait_for(function()
            for _, w in ipairs(find_new_windows(before, get_windows(ax_app))) do
                if looks_like_settings(w, cfg) then
                    candidate = w
                    return true
                end
            end
            return false
        end, function()
            win = candidate
            if legacy == nil then
                legacy = ax.find_first_by_role(win, "AXSlider") ~= nil
            end
            run_step(legacy)
        end, function()
            fail(MSG_WINDOW_TIMEOUT, false)
        end)
    end

    guarded(body)()
end

return M
