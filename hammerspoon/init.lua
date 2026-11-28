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

-- ===== App toggle =====
-- ⌃3 brings Claude forward and hides it on a second press, matching the
-- Raycast hotkeys on ⌃1/⌃2.
-- Bound with hs.hotkey.bind, not remapKey, so it also works from the terminal.
local claudeBundleID = "com.anthropic.claudefordesktop"
hs.hotkey.bind({"ctrl"}, "3", function()
   local front = hs.application.frontmostApplication()
   -- With no window open, a hide would change nothing on screen, so open one.
   if front and front:bundleID() == claudeBundleID and front:mainWindow() then
      front:hide()
   elseif not hs.application.launchOrFocusByBundleID(claudeBundleID) then
      hs.alert.show("Claude app not found: " .. claudeBundleID)
   end
end)

-- DeepL-style translation shortcuts (hammerspoon/translate.lua).
require("translate")

-- This machine's own additions, kept out of the repo (local.example/). An
-- error there is shown, not raised, so the reload watcher below still starts.
local localConfig = os.getenv("HOME") .. "/.hammerspoon.local"
if hs.fs.attributes(localConfig) then
   local ok, err = pcall(dofile, localConfig)
   if not ok then hs.alert.show("~/.hammerspoon.local: " .. tostring(err)) end
end

-- Auto-reload this config whenever a file in ~/.hammerspoon changes.
configWatcher = hs.pathwatcher.new(hs.configdir, hs.reload)
configWatcher:start()
hs.alert.show("Hammerspoon config loaded")
