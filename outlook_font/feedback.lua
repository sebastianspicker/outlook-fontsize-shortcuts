local M = {}

local DEFAULT_DURATION = 1.2

-- Creates a feedback object (notifications and a debounced overlay).
-- deps holds the hs modules notify, canvas, screen and timer.
function M.new(deps)
    -- Single overlay instance for debounce (reuse one canvas, reset timer on rapid calls)
    local canvas_ref = nil
    local timer_ref = nil

    local fb = {}

    local function dismiss_canvas()
        if canvas_ref then
            local c = canvas_ref
            canvas_ref = nil
            pcall(function()
                c:hide()
            end)
            pcall(function()
                c:delete()
            end)
        end
    end

    function fb.notify(title, message)
        local t = (title ~= nil and tostring(title)) or ""
        local m = (message ~= nil and tostring(message)) or ""
        deps.notify
            .new({
                title = t,
                informativeText = m,
                autoWithdraw = true,
                withdrawAfter = 3,
            })
            :send()
    end

    -- Shows a brief overlay; debounced (single canvas, timer reset on rapid calls).
    function fb.overlay(text, duration)
        if type(text) ~= "string" then
            text = ""
        end

        -- Debounce: cancel previous timer and remove previous canvas
        if timer_ref then
            pcall(function()
                timer_ref:stop()
            end)
            timer_ref = nil
        end
        dismiss_canvas()

        local main = deps.screen.mainScreen()
        if not main then
            return
        end
        local screen = main:fullFrame()
        local width, height = math.min(300, screen.w * 0.5), 60
        local x = screen.x + (screen.w - width) / 2
        local y = screen.y + (screen.h - height) / 2

        local c = deps.canvas.new({ x = x, y = y, w = width, h = height })
        if not c then
            return
        end

        canvas_ref = c
        c[1] = {
            type = "rectangle",
            action = "fill",
            frame = { x = 0, y = 0, w = 1, h = 1 },
            fillColor = { white = 0.1, alpha = 0.8 },
            roundedRectRadii = { xRadius = 12, yRadius = 12 },
            strokeColor = { white = 1, alpha = 0.9 },
            strokeWidth = 2,
        }
        c[2] = {
            type = "text",
            text = text,
            frame = { x = 0, y = 0, w = 1, h = 1 },
            textColor = { white = 1 },
            textSize = 28,
            textFont = "Helvetica Bold",
            alignment = "center",
        }
        c:show()

        local seconds = (type(duration) == "number" and duration > 0) and duration or DEFAULT_DURATION
        timer_ref = deps.timer.doAfter(seconds, function()
            dismiss_canvas()
            timer_ref = nil
        end)
    end

    return fb
end

return M
