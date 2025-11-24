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

-- remapKey: mods, key, action, [opts]
-- opts:
--   onlyFor = {"AppName1", "AppName2"}  ← 指定アプリのみ有効
--   exceptFor = {"AppName1"}            ← 指定アプリ以外で有効
local function remapKey(modifiers, key, action, opts)
   hs.hotkey.bind(modifiers, key,
      function()
         local app = hs.application.frontmostApplication()
         local name = app and app:name() or ""

         if opts and opts.onlyFor then
            -- 指定アプリ限定
            for _, target in ipairs(opts.onlyFor) do
               if name == target then action(); return end
            end
            hs.eventtap.keyStroke(modifiers, key)
            return
         elseif opts and opts.exceptFor then
            -- 指定アプリを除外
            for _, ex in ipairs(opts.exceptFor) do
               if name == ex then return end
            end
         end

         -- デフォルト動作
         action()
      end,
      nil,
      function() -- repeat時
         local app = hs.application.frontmostApplication()
         local name = app and app:name() or ""

         if opts and opts.onlyFor then
            for _, target in ipairs(opts.onlyFor) do
               if name == target then action(); return end
            end
            hs.eventtap.keyStroke(modifiers, key)
            return
         elseif opts and opts.exceptFor then
            for _, ex in ipairs(opts.exceptFor) do
               if name == ex then return end
            end
         end

         action()
      end
   )
end

local function disableAllHotkeys()
   for _, v in pairs(hs.hotkey.getHotkeys()) do
      v["_hk"]:disable()
   end
end

local function enableAllHotkeys()
   for _, v in pairs(hs.hotkey.getHotkeys()) do
      v["_hk"]:enable()
   end
end

-- ===== App watcher =====
local function handleGlobalAppEvent(name, event, app)
   if event == hs.application.watcher.activated then
      if name ~= "Ghostty" then
         enableAllHotkeys()
      else
         disableAllHotkeys()
      end
   end
end

--------------------------------------------------
-- Vivaldi 専用ショートカット
--------------------------------------------------

-- 今前面にいるアプリが Vivaldi かどうか
local function isVivaldiFront()
    local app = hs.application.frontmostApplication()
    return app and app:name() == "Vivaldi"
end

--------------------------------------------------
-- Double Shift → Cmd+E （Vivaldi のときだけ）
--------------------------------------------------
local lastShiftTime = 0
local shiftThreshold = 0.30  -- 300ms 以内の 2 連打を検出
local prevShiftDown = false  -- 1つ前のイベントで Shift が押されていたか

local shiftTap = hs.eventtap.new({hs.eventtap.event.types.flagsChanged}, function(event)
    local flags = event:getFlags()
    local shiftDown = flags.shift or false
    local now = hs.timer.secondsSinceEpoch()

    -- Vivaldi 以外では何もしない（状態だけ更新）
    if not isVivaldiFront() then
        prevShiftDown = shiftDown
        return false
    end

    -- 「Shift を押した瞬間」だけ拾う
    if shiftDown and not prevShiftDown then
        if (now - lastShiftTime) < shiftThreshold then
            -- 2 回目の Shift → Cmd+E 発火
            hs.eventtap.keyStroke({ "cmd" }, "e", 0)
            lastShiftTime = 0
        else
            -- 1 回目の Shift として時刻記録
            lastShiftTime = now
        end
    end

    prevShiftDown = shiftDown
    return false  -- 元イベントはそのまま流す
end)

shiftTap:start()

--------------------------------------------------
-- Ctrl+n / Ctrl+p → ↓ / ↑ （Vivaldi のときだけ）
--------------------------------------------------
local ctrlNPtap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
    local keyCode = event:getKeyCode()
    local flags = event:getFlags()
    -- Ctrl だけ（Cmd/Alt/Shift が一緒に押されていたらスルー）
    if not flags.ctrl or flags.cmd or flags.alt or flags.shift then
        return false
    end
    -- Vivaldi 以外は素通し
    if not isVivaldiFront() then
        return false
    end
    if keyCode == hs.keycodes.map["n"] then
        -- Ctrl+n → ↓
        hs.eventtap.keyStroke({}, "down", 0)
        return true  -- 元の Ctrl+n はキャンセル
    elseif keyCode == hs.keycodes.map["p"] then
        -- Ctrl+p → ↑
        hs.eventtap.keyStroke({}, "up", 0)
        return true
    end
    return false
end)
ctrlNPtap:start()

appsWatcher = hs.application.watcher.new(handleGlobalAppEvent)
appsWatcher:start()

-- ===== Global Emacs-style remaps =====
remapKey({"alt"}, "b", keyCode("left", {"alt"}))
remapKey({"alt"}, "f", keyCode("right", {"alt"}))
remapKey({"ctrl"}, "w", keyCode("delete", {"alt"}))
remapKey({'ctrl'}, "/", keyCode("z", {"cmd"}))

-- ===== Vivaldi限定 remaps =====
remapKey({"ctrl"}, "n", keyCode("down"), { onlyFor = {"Vivaldi"} })
remapKey({"ctrl"}, "p", keyCode("up"), { onlyFor = {"Vivaldi"} })
