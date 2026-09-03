-- typeless_paywall_closer.lua
-- Auto-dismisses two specific Typeless floating-bar cards, matched by exact
-- title: "Upgrade for enhanced accuracy" and "High demand". Both are paywall
-- nudges with an X in the top-right corner. Nothing else in Typeless is touched.
--
-- How it works
--   1. Attach to the Typeless process (bundle id now.typeless.desktop).
--   2. Ask Chromium to expose its accessibility tree (AXManualAccessibility).
--   3. Poll the small floating-bar window every 0.5 s (Chromium delivers no
--      usable AX notifications for content changes, verified 2026-09-03; the
--      observer is kept only as a bonus) and walk it looking for an
--      AXStaticText whose value equals a target title.
--   4. Climb to the enclosing tooltip card (AXSubrole AXUserInterfaceTooltip),
--      pick the unnamed small AXButton that supports AXPress (the X icon) and
--      press it. Text buttons such as "Upgrade" never qualify.
--
-- Menu bar: a "⌧" item shows status, lets you pause, scan, dump, open the log.
-- Log file: ~/Library/Logs/typeless-paywall-closer/activity.log
--
-- Debug helpers (Hammerspoon console, or `hs -c '...'` from a shell):
--   typeless.dump()      -- print the AX tree of every small Typeless window
--   typeless.scan("me")  -- run one scan now
--   typeless.selfTest()  -- exercise the matcher with synthetic data
--   typeless.config      -- tweak thresholds live

local ax = hs.axuielement
local M = {}

M.config = {
  bundleID      = "now.typeless.desktop",
  -- Matched after lower-casing and whitespace normalisation. Exact match only.
  targetTitles  = { "upgrade for enhanced accuracy", "high demand" },
  pollInterval  = 0.5,   -- seconds; primary trigger (Chromium posts no AX notifications for content changes)
  debounce      = 0.15,  -- seconds; coalesce bursts of AX notifications
  maxDepth      = 40,
  maxNodes      = 2500,  -- per window, per scan
  maxWindowWidth = 900,  -- floating bar is 750 wide; the settings hub is at least 988 wide and is skipped
  maxButtonSide = 40,    -- the X icon is 16px; anything bigger is a text/CTA button
  pressCooldown = 2.0,   -- seconds between presses
  clickFallback = true,  -- synthesise a click if a pressable button still refuses AXPress
  logLevel      = "info",
  logFile       = os.getenv("HOME") .. "/Library/Logs/typeless-paywall-closer/activity.log",
  menubar       = true,
}

local log = hs.logger.new("typeless", M.config.logLevel)
M.log = log  -- typeless.log.setLogLevel("debug") to trace scans

local state = {
  app = nil, appEl = nil, observer = nil, timer = nil, debounceTimer = nil,
  appWatcher = nil, watched = {}, lastPressAt = 0, trusted = false,
  enabled = true, lastAction = nil, closedCount = 0, menubar = nil,
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

local function buttonName(btn)
  local parts = {}
  for _, a in ipairs({ "AXTitle", "AXDescription", "AXValue", "AXHelp" }) do
    local v = attr(btn, a)
    if type(v) == "string" and normalize(v) ~= "" then parts[#parts + 1] = normalize(v) end
  end
  return table.concat(parts, " | ")
end

local function hasPressAction(el)
  local ok, names = pcall(function() return el:actionNames() end)
  if not ok or type(names) ~= "table" then return false end
  for _, n in ipairs(names) do
    if n == "AXPress" then return true end
  end
  return false
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

-- ------------------------------------------------------------ file log

local function ensureLogDir()
  local dir = M.config.logFile:match("^(.*)/[^/]+$")
  if dir and not hs.fs.attributes(dir) then hs.fs.mkdir(dir) end
end

-- Console + persistent file. Debug-level scan traces stay console-only.
local function record(level, msg)
  if level == "w" then log.w(msg) elseif level == "e" then log.e(msg) else log.i(msg) end
  ensureLogDir()
  local f = io.open(M.config.logFile, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S"), " ", level:upper(), " ", msg, "\n")
    f:close()
  end
end

-- ------------------------------------------------- matching (pure functions)

M.matcher = {}

function M.matcher.normalize(s) return normalize(s) end

function M.matcher.isTargetTitle(text)
  local n = normalize(text)
  if n == "" then return false end
  for _, t in ipairs(M.config.targetTitles) do
    if n == t then return true end
  end
  return false
end

function M.matcher.isCloseName(name)
  local n = normalize(name)
  if n == "" or n == "x" or n == "×" then return true end
  if n:find("close", 1, true) or n:find("dismiss", 1, true) then return true end
  return false
end

-- candidates: { {name=, frame={x,y,w,h}, pressable=bool}, ... }
-- Returns the chosen candidate (or nil) and a reason string.
function M.matcher.chooseCloseButton(candidates, containerFrame)
  local best, bestScore
  for _, c in ipairs(candidates) do
    local f = c.frame
    local small = f and f.w <= M.config.maxButtonSide and f.h <= M.config.maxButtonSide
    if c.pressable and small and M.matcher.isCloseName(c.name) then
      -- Prefer the top-right corner of the card: further right and higher up scores more.
      local score = 0
      if containerFrame and f then score = (f.x - containerFrame.x) - (f.y - containerFrame.y) end
      if not best or score > bestScore then best, bestScore = c, score end
    end
  end
  if best then return best, "ok" end
  return nil, "no pressable unnamed small button"
end

-- ---------------------------------------------------------- AX matching

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

local function collectButtons(container)
  local candidates = {}
  walk(container, function(el)
    if attr(el, "AXRole") == "AXButton" then
      candidates[#candidates + 1] = {
        el = el, name = buttonName(el), frame = frameOf(el), pressable = hasPressAction(el),
      }
    end
    return false
  end)
  return candidates
end

local function describeCandidates(all)
  local names = {}
  for _, c in ipairs(all) do
    names[#names + 1] = string.format("[%s %s %s]", c.name == "" and "<unnamed>" or c.name,
      fmtFrame(c.frame), c.pressable and "press" or "no-press")
  end
  return table.concat(names, " ")
end

local function press(c, how, title)
  local now = hs.timer.secondsSinceEpoch()
  if now - state.lastPressAt < M.config.pressCooldown then
    log.d("press suppressed by cooldown")
    return false
  end
  state.lastPressAt = now
  local ok, res = pcall(function() return c.el:performAction("AXPress") end)
  if ok and res then
    state.closedCount = state.closedCount + 1
    state.lastAction = string.format("Closed \"%s\" at %s", title, os.date("%H:%M:%S"))
    record("i", string.format("closed \"%s\" via AXPress (container=%s, button=%s)", title, how, fmtFrame(c.frame)))
    return true
  end
  if M.config.clickFallback and c.frame then
    local center = { x = c.frame.x + c.frame.w / 2, y = c.frame.y + c.frame.h / 2 }
    local saved = hs.mouse.absolutePosition()
    hs.eventtap.leftClick(center, 0)
    hs.mouse.absolutePosition(saved)
    state.closedCount = state.closedCount + 1
    state.lastAction = string.format("Clicked \"%s\" at %s", title, os.date("%H:%M:%S"))
    record("w", string.format("AXPress refused; closed \"%s\" via synthetic click at %.0f,%.0f", title, center.x, center.y))
    return true
  end
  record("w", string.format("AXPress refused for \"%s\" and click fallback disabled; card left open", title))
  return false
end

function M.scan(reason)
  if not state.appEl then return end
  local wins = attr(state.appEl, "AXWindows") or {}
  for _, win in ipairs(wins) do
    if isSmallWindow(win) then
      local titleEl, titleText
      local visited = walk(win, function(el)
        if attr(el, "AXRole") == "AXStaticText" then
          local v = attr(el, "AXValue")
          if M.matcher.isTargetTitle(v) then
            titleEl, titleText = el, v
            return true
          end
        end
        return false
      end)
      log.d(string.format("scan[%s] window %s visited=%d hit=%s", tostring(reason),
        fmtFrame(frameOf(win)), visited, tostring(titleEl ~= nil)))
      if titleEl then
        local container, how = alertContainer(titleEl)
        if not container then
          record("w", "target title found but no container; skipping")
        else
          local all = collectButtons(container)
          local best, why = M.matcher.chooseCloseButton(all, frameOf(container))
          if best then
            press(best, how, titleText)
          else
            record("w", string.format("card \"%s\" found but %s; buttons: %s", titleText, why, describeCandidates(all)))
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
  if not state.enabled then return end
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
    record("w", "could not get application element (accessibility permission missing?)")
    state.app = nil
    return false
  end
  -- Chromium/Electron only expose web content to AX clients that ask for it.
  -- Do NOT set AXEnhancedUserInterface=false afterwards: it is the same switch.
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
  record("i", "attached to Typeless pid " .. app:pid() .. (state.trusted and "" or " (no Accessibility permission yet)"))
  scheduleScan("attach")
  return true
end

local function tick()
  -- Permission granted after we attached: rebuild the observer so watchers actually register.
  if state.observer and not state.trusted and hs.accessibilityState() then
    record("i", "Accessibility permission granted; re-attaching")
    detach()
  end
  if not state.observer then
    attach()
    return
  end
  if not state.enabled then return end
  for _, w in ipairs(attr(state.appEl, "AXWindows") or {}) do watchWindow(w) end
  M.scan("poll")
end

-- -------------------------------------------------------------- menu bar

local function buildMenu()
  local items = {}
  items[#items + 1] = {
    title = state.enabled and "Enabled" or "Paused",
    checked = state.enabled,
    fn = function() M.setEnabled(not state.enabled) end,
  }
  items[#items + 1] = { title = "-" }
  items[#items + 1] = {
    title = hs.accessibilityState() and "Accessibility: granted" or "Accessibility: missing",
    disabled = true,
  }
  items[#items + 1] = {
    title = state.app and ("Typeless: attached (pid " .. state.app:pid() .. ")") or "Typeless: not running",
    disabled = true,
  }
  items[#items + 1] = {
    title = state.lastAction or "No cards closed yet",
    disabled = true,
  }
  if state.closedCount > 0 then
    items[#items + 1] = { title = "Closed this session: " .. state.closedCount, disabled = true }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Scan now", fn = function() M.scan("menu") end }
  items[#items + 1] = { title = "Dump AX tree to console", fn = function() hs.openConsole(); M.dump() end }
  items[#items + 1] = { title = "Open log file", fn = function() ensureLogDir(); hs.open(M.config.logFile) end }
  if not hs.accessibilityState() then
    items[#items + 1] = {
      title = "Open Accessibility settings…",
      fn = function()
        hs.accessibilityState(true)
        hs.urlevent.openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
      end,
    }
  end
  items[#items + 1] = { title = "-" }
  items[#items + 1] = { title = "Reload Hammerspoon", fn = function() hs.reload() end }
  return items
end

local function setupMenubar()
  if not M.config.menubar or state.menubar then return end
  state.menubar = hs.menubar.new()
  if not state.menubar then return end
  state.menubar:setTitle("⌧")
  state.menubar:setTooltip("Typeless paywall closer")
  state.menubar:setMenu(buildMenu)
end

function M.setEnabled(on)
  state.enabled = on and true or false
  record("i", state.enabled and "resumed" or "paused")
  if state.menubar then state.menubar:setTitle(state.enabled and "⌧" or "⌧∙") end
  return M
end

-- ------------------------------------------------------------- self test

-- Exercises the pure matcher with synthetic data. Returns ok, failures.
function M.selfTest()
  local failures = {}
  local function check(name, cond)
    if not cond then failures[#failures + 1] = name end
  end
  local m = M.matcher

  check("title exact",         m.isTargetTitle("Upgrade for enhanced accuracy"))
  check("title whitespace",    m.isTargetTitle("  Upgrade  for\nEnhanced Accuracy "))
  check("title high demand",   m.isTargetTitle("High demand"))
  check("title body rejected", not m.isTargetTitle("Upgrade to Typeless Pro for unlimited words, enhanced accuracy, and priority access during high demand."))
  check("title partial",       not m.isTargetTitle("Upgrade"))
  check("title punctuation",   not m.isTargetTitle("High demand!"))
  check("title empty",         not m.isTargetTitle(""))
  check("title nil",           not m.isTargetTitle(nil))

  check("close empty",   m.isCloseName(""))
  check("close word",    m.isCloseName("Close"))
  check("close dismiss", m.isCloseName("dismiss"))
  check("close x",       m.isCloseName("x"))
  check("close times",   m.isCloseName("×"))
  check("close upgrade", not m.isCloseName("Upgrade"))

  -- Card geometry from the real 2026-09-03 hit: card ~700x350, X at top-right 16x16.
  local card = { x = 380, y = 460, w = 700, h = 350 }
  local xBtn      = { name = "",        frame = { x = 1044, y = 476, w = 16, h = 16 },  pressable = true }
  local upgrade   = { name = "upgrade", frame = { x = 690,  y = 740, w = 120, h = 48 }, pressable = true }
  local bigBlank  = { name = "",        frame = { x = 600,  y = 600, w = 80, h = 80 },  pressable = true }
  local noPress   = { name = "",        frame = { x = 1000, y = 476, w = 16, h = 16 },  pressable = false }
  local lowerX    = { name = "",        frame = { x = 1044, y = 700, w = 16, h = 16 },  pressable = true }

  local best = m.chooseCloseButton({ upgrade, xBtn, bigBlank, noPress }, card)
  check("choose x over others", best == xBtn)
  check("reject upgrade only",  m.chooseCloseButton({ upgrade }, card) == nil)
  check("reject big blank",     m.chooseCloseButton({ bigBlank }, card) == nil)
  check("reject no AXPress",    m.chooseCloseButton({ noPress }, card) == nil)
  check("prefer top-right",     m.chooseCloseButton({ lowerX, xBtn }, card) == xBtn)
  check("empty candidates",     m.chooseCloseButton({}, card) == nil)

  local ok = #failures == 0
  if ok then
    log.i("selfTest: all checks passed")
  else
    record("e", "selfTest FAILED: " .. table.concat(failures, ", "))
  end
  return ok, failures
end

-- ------------------------------------------------------------ start/stop

function M.start()
  if not hs.accessibilityState() then
    record("w", "Hammerspoon lacks Accessibility permission; prompting")
    hs.accessibilityState(true)
  end
  M.selfTest()
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
  setupMenubar()
  attach()
  record("i", "typeless paywall closer started")
  return M
end

function M.stop()
  if state.appWatcher then state.appWatcher:stop() end
  if state.timer then state.timer:stop() end
  if state.menubar then state.menubar:delete() end
  state.appWatcher, state.timer, state.menubar = nil, nil, nil
  detach()
  record("i", "typeless paywall closer stopped")
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
        if role == "AXButton" then bits[#bits + 1] = hasPressAction(el) and "actions=AXPress" or "actions=none" end
        print(string.rep("  ", depth) .. role .. (sub and ("/" .. sub) or "") .. " [" .. fmtFrame(frameOf(el)) .. "] " .. table.concat(bits, " "))
        return false
      end)
    end
  end
  M.config.maxDepth = saved
end

return M
