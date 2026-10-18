-- ref: https://qiita.com/naoya@github/items/81027083aeb70b309c14

-- ===== Utility functions =====
local function keyCode(key, modifiers)
   modifiers = modifiers or {}
   return function()
      hs.eventtap.event.newKeyEvent(modifiers, string.lower(key), true):post()
      hs.timer.usleep(1000)
      hs.eventtap.event.newKeyEvent(modifiers, string.lower(key), false):post()
   end
end

-- Own registry of created hotkeys, so enable/disable doesn't rely on the
-- undocumented internals of hs.hotkey.getHotkeys().
local hotkeys = {}

local function remapKey(modifiers, key, action)
   table.insert(hotkeys, hs.hotkey.bind(modifiers, key, action, nil, action))
end

local function setHotkeysEnabled(enabled)
   for _, hk in ipairs(hotkeys) do
      if enabled then hk:enable() else hk:disable() end
   end
end

local function isRemapTarget(appName)
   -- The terminal gets the real keys: Emacs-style bindings are handled by
   -- zsh/nvim themselves, and remapping there would break them.
   return appName ~= "Ghostty"
end

-- ===== Global Emacs-style remaps =====
-- NOTE: keybindings below are documented in KEYBINDINGS.md (repo root) —
-- update it when they change.
remapKey({"alt"}, "b", keyCode("left", {"alt"}))
remapKey({"alt"}, "f", keyCode("right", {"alt"}))
remapKey({"ctrl"}, "w", keyCode("delete", {"alt"}))
remapKey({"ctrl"}, "/", keyCode("z", {"cmd"}))

-- ===== App watcher =====
local function handleGlobalAppEvent(name, event, _)
   if event == hs.application.watcher.activated then
      setHotkeysEnabled(isRemapTarget(name))
   end
end

-- Watchers must live in globals: a local would be garbage-collected and the
-- watcher would silently stop firing.
appWatcher = hs.application.watcher.new(handleGlobalAppEvent)
appWatcher:start()

-- Apply the right state for whichever app is frontmost right now — the watcher
-- only fires on the next activation, and a config reload can happen while the
-- terminal is already focused.
local frontmost = hs.application.frontmostApplication()
setHotkeysEnabled(not frontmost or isRemapTarget(frontmost:name()))

-- Auto-reload this config whenever a file in ~/.hammerspoon changes.
configWatcher = hs.pathwatcher.new(hs.configdir, hs.reload)
configWatcher:start()
hs.alert.show("Hammerspoon config loaded")
