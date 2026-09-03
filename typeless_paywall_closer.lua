-- typeless_paywall_closer.lua
-- Auto-dismisses ONE specific Typeless alert: the floating-bar card titled
-- "Upgrade for enhanced accuracy". Nothing else in Typeless is touched.
--
-- How it works
--   1. Attach to the Typeless process (bundle id now.typeless.desktop).
--   2. Ask Chromium to expose its accessibility tree (AXManualAccessibility).
--   3. Poll the small floating-bar window every 0.5 s (Chromium delivers no
--      usable AX notifications for content changes, verified 2026-09-03; the
--      observer is kept only as a bonus) and walk it looking for an
--      AXStaticText whose value equals the target title.
--   4. Climb to the enclosing tooltip card (AXSubrole AXUserInterfaceTooltip),
--      pick the unnamed small AXButton inside it (the X icon) and AXPress it.
--
-- Debug helpers (Hammerspoon console, or `hs -c '...'` from a shell):
--   typeless.dump()      -- print the AX tree of every small Typeless window
--   typeless.scan("me")  -- run one scan now
--   typeless.config      -- tweak thresholds live

local ax = hs.axuielement
local M = {}

M.config = {
  bundleID      = "now.typeless.desktop",
  -- Matched after lower-casing and whitespace normalisation. Exact match only.
  targetTitles  = { "upgrade for enhanced accuracy" },
  pollInterval  = 0.5,   -- seconds; primary trigger (Chromium posts no AX notifications for content changes)
  debounce      = 0.15,  -- seconds; coalesce bursts of AX notifications
  maxDepth      = 40,
  maxNodes      = 2500,  -- per window, per scan
  maxWindowWidth = 900,  -- floating bar is 750 wide; the settings hub is at least 988 wide and is skipped
  maxButtonSide = 40,    -- the X icon is 16px; anything bigger is a text/CTA button
  pressCooldown = 2.0,   -- seconds between presses
  clickFallback = true,  -- synthesise a click if AXPress is refused
  logLevel      = "info",
}

local log = hs.logger.new("typeless", M.config.logLevel)
M.log = log  -- typeless.log.setLogLevel("debug") to trace scans

local state = {
  app = nil, appEl = nil, observer = nil, timer = nil, debounceTimer = nil,
  appWatcher = nil, watched = {}, lastPressAt = 0, trusted = false,
}

-- ---------------------------------------------------------------- helpers

local function normalize(s)
  if type(s) ~= "string" then return "" end
  s = s:lower():gsub("%s+", " ")
  return s:match("^%s*(.-)%s*$") or ""
end

local function attr(el, name)
  if not el then return nil end
  local ok, v = pcall(function() return el:attributeValue(name) end)
  if ok then return v end
  return nil
end

local function frameOf(el)
  local f = attr(el, "AXFrame")
  if type(f) == "table" and f.w then return f end
  local p, s = attr(el, "AXPosition"), attr(el, "AXSize")
  if type(p) == "table" and type(s) == "table" then
    return { x = p.x, y = p.y, w = s.w, h = s.h }
  end
  return nil
end

local function fmtFrame(f)
  if not f then return "?" end
  return string.format("%.0f,%.0f %.0fx%.0f", f.x, f.y, f.w, f.h)
end

local function isTargetTitle(text)
  local n = normalize(text)
  if n == "" then return false end
  for _, t in ipairs(M.config.targetTitles) do
    if n == t then return true end
  end
  return false
end

local function buttonName(btn)
  local parts = {}
  for _, a in ipairs({ "AXTitle", "AXDescription", "AXValue", "AXHelp" }) do
    local v = attr(btn, a)
    if type(v) == "string" and normalize(v) ~= "" then parts[#parts + 1] = normalize(v) end
  end
  return table.concat(parts, " | ")
end

-- Depth-first walk with a node budget. visit(el, depth) returns true to stop early.
-- Returns the number of nodes visited.
local function walk(root, visit)
  local budget = M.config.maxNodes
  local function rec(el, depth)
    if budget <= 0 or depth > M.config.maxDepth then return false end
    budget = budget - 1
    if visit(el, depth) then return true end
    local kids = attr(el, "AXChildren")
    if type(kids) == "table" then
      for _, k in ipairs(kids) do
        if rec(k, depth + 1) then return true end
      end
    end
    return false
  end
  rec(root, 0)
  return M.config.maxNodes - budget
end

local function isSmallWindow(win)
  local f = frameOf(win)
  if not f then return true end
  return f.w <= M.config.maxWindowWidth
end

-- ------------------------------------------------------------- matching

-- From the title text node, climb to the tooltip card. Fall back to the
-- grandparent (the Stack that holds title, description and the X button).
local function alertContainer(textEl)
  local el, fallback = textEl, nil
  for i = 1, 8 do
    el = attr(el, "AXParent")
    if not el then break end
    if i == 2 then fallback = el end
    if attr(el, "AXSubrole") == "AXUserInterfaceTooltip" then return el, "tooltip" end
  end
  return fallback, "grandparent"
end

local function isCloseName(name)
  if name == "" then return true end
  if name:find("close", 1, true) or name:find("dismiss", 1, true) then return true end
  return false
end

-- Pick the X button: unnamed (or named close/dismiss), small, nearest the
-- top-right corner of the card. Text buttons such as "Upgrade" never qualify.
local function pickCloseButton(container)
  local candidates = {}
  walk(container, function(el)
    if attr(el, "AXRole") == "AXButton" then
      candidates[#candidates + 1] = { el = el, name = buttonName(el), frame = frameOf(el) }
    end
    return false
  end)
  local cf = frameOf(container)
  local best, bestScore
  for _, c in ipairs(candidates) do
    local f = c.frame
    local small = f and f.w <= M.config.maxButtonSide and f.h <= M.config.maxButtonSide
    if small and isCloseName(c.name) then
      local score = 0
      if cf and f then score = (f.x - cf.x) - (f.y - cf.y) end
      if not best or score > bestScore then best, bestScore = c, score end
    end
  end
  return best, candidates
end

local function press(c, how)
  local now = hs.timer.secondsSinceEpoch()
  if now - state.lastPressAt < M.config.pressCooldown then
    log.d("press suppressed by cooldown")
    return false
  end
  state.lastPressAt = now
  local ok, res = pcall(function() return c.el:performAction("AXPress") end)
  if ok and res then
    log.i(string.format("closed paywall card via AXPress (container=%s, button=%s)", how, fmtFrame(c.frame)))
    return true
  end
  if M.config.clickFallback and c.frame then
    local center = { x = c.frame.x + c.frame.w / 2, y = c.frame.y + c.frame.h / 2 }
    local saved = hs.mouse.absolutePosition()
    hs.eventtap.leftClick(center, 0)
    hs.mouse.absolutePosition(saved)
    log.i(string.format("closed paywall card via synthetic click at %.0f,%.0f", center.x, center.y))
    return true
  end
  log.w("AXPress refused and click fallback disabled; card left open")
  return false
end

function M.scan(reason)
  if not state.appEl then return end
  local wins = attr(state.appEl, "AXWindows") or {}
  for _, win in ipairs(wins) do
    if isSmallWindow(win) then
      local titleEl
      local visited = walk(win, function(el)
        if attr(el, "AXRole") == "AXStaticText" and isTargetTitle(attr(el, "AXValue")) then
          titleEl = el
          return true
        end
        return false
      end)
      log.d(string.format("scan[%s] window %s visited=%d hit=%s", tostring(reason),
        fmtFrame(frameOf(win)), visited, tostring(titleEl ~= nil)))
      if titleEl then
        local container, how = alertContainer(titleEl)
        if not container then
          log.w("target title found but no container; skipping")
        else
          local best, all = pickCloseButton(container)
          if best then
            press(best, how)
          else
            local names = {}
            for _, c in ipairs(all) do names[#names + 1] = "[" .. c.name .. " " .. fmtFrame(c.frame) .. "]" end
            log.w("target card found but no close button matched; buttons: " .. table.concat(names, " "))
          end
        end
      end
    end
  end
end

-- ------------------------------------------------------------ lifecycle

local APP_NOTIFS = { "AXWindowCreated", "AXFocusedWindowChanged", "AXApplicationShown" }
local WIN_NOTIFS = { "AXResized", "AXMoved", "AXLayoutChanged", "AXCreated",
                     "AXValueChanged", "AXLiveRegionChanged", "AXTitleChanged" }

local function scheduleScan(reason)
  if state.debounceTimer then state.debounceTimer:stop() end
  state.debounceTimer = hs.timer.doAfter(M.config.debounce, function() M.scan(reason) end)
end

local function watchWindow(win)
  if not state.observer then return end
  for _, w in ipairs(state.watched) do
    if w == win then return end
  end
  state.watched[#state.watched + 1] = win
  for _, n in ipairs(WIN_NOTIFS) do
    pcall(function() state.observer:addWatcher(win, n) end)
  end
end

local function detach()
  if state.observer then pcall(function() state.observer:stop() end) end
  if state.debounceTimer then state.debounceTimer:stop() end
  state.observer, state.debounceTimer = nil, nil
  state.app, state.appEl, state.watched, state.trusted = nil, nil, {}, false
end

local function attach()
  local apps = hs.application.applicationsForBundleID(M.config.bundleID)
  local app = apps and apps[1]
  if not app then return false end
  if state.app and state.observer and state.app:pid() == app:pid() then return true end
  detach()
  state.app = app
  state.appEl = ax.applicationElement(app)
  if not state.appEl then
    log.w("could not get application element (accessibility permission missing?)")
    state.app = nil
    return false
  end
  -- Chromium/Electron only expose web content to AX clients that ask for it.
  pcall(function() state.appEl:setAttributeValue("AXManualAccessibility", true) end)

  state.observer = ax.observer.new(app:pid())
  state.observer:callback(function(_, el, notif, _)
    if notif == "AXWindowCreated" then watchWindow(el) end
    scheduleScan(notif)
  end)
  for _, n in ipairs(APP_NOTIFS) do
    pcall(function() state.observer:addWatcher(state.appEl, n) end)
  end
  for _, w in ipairs(attr(state.appEl, "AXWindows") or {}) do watchWindow(w) end
  state.observer:start()
  state.trusted = hs.accessibilityState()
  log.i("attached to Typeless pid " .. app:pid() .. (state.trusted and "" or " (no Accessibility permission yet)"))
  scheduleScan("attach")
  return true
end

local function tick()
  -- Permission granted after we attached: rebuild the observer so watchers actually register.
  if state.observer and not state.trusted and hs.accessibilityState() then
    log.i("Accessibility permission granted; re-attaching")
    detach()
  end
  if not state.observer then
    attach()
    return
  end
  for _, w in ipairs(attr(state.appEl, "AXWindows") or {}) do watchWindow(w) end
  M.scan("poll")
end

function M.start()
  if not hs.accessibilityState() then
    log.w("Hammerspoon lacks Accessibility permission; prompting")
    hs.accessibilityState(true)
  end
  if state.appWatcher then return M end
  state.appWatcher = hs.application.watcher.new(function(_, event, app)
    if not app or app:bundleID() ~= M.config.bundleID then return end
    if event == hs.application.watcher.launched then
      hs.timer.doAfter(2, attach)
    elseif event == hs.application.watcher.terminated then
      detach()
    end
  end)
  state.appWatcher:start()
  state.timer = hs.timer.doEvery(M.config.pollInterval, tick)
  attach()
  log.i("typeless paywall closer started")
  return M
end

function M.stop()
  if state.appWatcher then state.appWatcher:stop() end
  if state.timer then state.timer:stop() end
  state.appWatcher, state.timer = nil, nil
  detach()
  log.i("typeless paywall closer stopped")
  return M
end

-- Print the AX tree of every small Typeless window (for verifying the card layout).
function M.dump(maxDepth)
  if not hs.accessibilityState() then
    print("Hammerspoon has no Accessibility permission yet: System Settings > Privacy & Security > Accessibility > enable Hammerspoon")
    return
  end
  if not state.appEl and not attach() then
    print("Typeless is not running or not reachable")
    return
  end
  local wins = attr(state.appEl, "AXWindows") or {}
  if #wins == 0 then print("Typeless exposes no windows right now") end
  local saved = M.config.maxDepth
  M.config.maxDepth = maxDepth or saved
  for i, win in ipairs(wins) do
    local f = frameOf(win)
    print(string.format("== window %d  title=%q  subrole=%s  frame=%s  %s", i,
      tostring(attr(win, "AXTitle")), tostring(attr(win, "AXSubrole")), fmtFrame(f),
      isSmallWindow(win) and "" or "(large: skipped by scan)"))
    if isSmallWindow(win) then
      walk(win, function(el, depth)
        local role = tostring(attr(el, "AXRole"))
        local sub = attr(el, "AXSubrole")
        local bits = {}
        for _, a in ipairs({ "AXTitle", "AXDescription", "AXValue" }) do
          local v = attr(el, a)
          if type(v) == "string" and v ~= "" then bits[#bits + 1] = a:sub(3) .. "=" .. string.format("%q", v:sub(1, 60)) end
        end
        print(string.rep("  ", depth) .. role .. (sub and ("/" .. sub) or "") .. " [" .. fmtFrame(frameOf(el)) .. "] " .. table.concat(bits, " "))
        return false
      end)
    end
  end
  M.config.maxDepth = saved
end

return M
