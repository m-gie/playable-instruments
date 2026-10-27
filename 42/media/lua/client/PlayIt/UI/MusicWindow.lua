-- The music window: paste a song, set BPM and volume, Play/Pause, Stop, Save, Load.
-- Closing it while a song plays or is paused leaves the small widget instead.

require "ISUI/ISCollapsableWindow"
require "RadioCom/ISUIRadio/ISSliderPanel"
require "PlayIt/Song"
require "PlayIt/SongFiles"
require "PlayIt/Session"
require "PlayIt/Controls"
require "PlayIt/Instruments"
require "PlayIt/Furniture"
require "PlayIt/Playback"

PlayIt = PlayIt or {}
PlayIt.MusicWindow = ISCollapsableWindow:derive("PlayItMusicWindow")
local MusicWindow = PlayIt.MusicWindow

local PAD = 8
local FONT_HGT = getTextManager():getFontHeight(UIFont.Small)
local ROW = FONT_HGT + 8
local DEFAULT_VOLUME = 70

local windows = {} -- one per local player

-- place: the tile of a piano, organ or drum played from the world (nil for hand-held instruments)
function MusicWindow.open(player, fullType, place)
    local w = windows[player:getPlayerNum()]
    if w == nil then
        w = MusicWindow:new(200, 150, 440, 400, player)
        w:initialise()
        w:addToUIManager()
        windows[player:getPlayerNum()] = w
    end
    w.player = player -- the slot's character may have died and respawned since the window was made
    w.fullType = fullType
    w.place = place
    w:setTitle(getText("IGUI_PlayIt_Title", PlayIt.Instruments.displayName(fullType)))
    w:setVisible(true)
    w:bringToTop()
    PlayIt.MiniWidget.hide(player)
    return w
end

function MusicWindow.get(player)
    return windows[player:getPlayerNum()]
end

function MusicWindow:controller()
    return PlayIt.Controls.get(self.player)
end

function MusicWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local top = self:titleBarHeight() + PAD

    self.songBox = ISTextEntryBox:new("", PAD, top, self.width - PAD * 2, 100)
    self.songBox:initialise()
    self.songBox:instantiate()
    self.songBox:setMultipleLine(true)
    self.songBox:setMaxLines(PlayIt.Song.MAX_LINES + 1)
    self.songBox.target = self
    self.songBox.onTextChangeFunction = MusicWindow.onSongChanged
    self:addChild(self.songBox)

    self.bpmLabel = ISLabel:new(0, 0, ROW, getText("IGUI_PlayIt_BPM"), 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.bpmLabel)
    self.bpmBox = ISTextEntryBox:new(tostring(PlayIt.Song.BPM_DEFAULT), 0, 0, 50, ROW)
    self.bpmBox:initialise()
    self.bpmBox:instantiate()
    self.bpmBox:setOnlyNumbers(true)
    self:addChild(self.bpmBox)

    self.volumeLabel = ISLabel:new(0, 0, ROW, getText("IGUI_PlayIt_Volume"), 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.volumeLabel)
    self.volume = ISSliderPanel:new(0, 0, 150, ROW, self, nil)
    self.volume:initialise()
    self.volume:instantiate()
    self.volume:setValues(0, 100, 5, 10)
    self.volume:setCurrentValue(DEFAULT_VOLUME, true)
    self:addChild(self.volume)

    local function button(key, onClick)
        local b = ISButton:new(0, 0, 80, ROW, getText(key), self, onClick)
        b:initialise()
        b:instantiate()
        self:addChild(b)
        return b
    end
    self.playButton = button("IGUI_PlayIt_Play", MusicWindow.onPlay)
    self.stopButton = button("IGUI_PlayIt_Stop", MusicWindow.onStop)
    self.saveButton = button("IGUI_PlayIt_Save", MusicWindow.onSave)
    self.loadButton = button("IGUI_PlayIt_Load", MusicWindow.onLoad)

    self.status = ISLabel:new(PAD, 0, FONT_HGT, "", 1, 0.8, 0.4, 1, UIFont.Small, true)
    self:addChild(self.status)
    self:layout()
end

-- positions everything for the current size (the window is resizable)
function MusicWindow:layout()
    local bottom = self.height - PAD - self:resizeWidgetHeight()
    local buttonsY = bottom - ROW
    local controlsY = buttonsY - PAD - ROW
    local statusY = controlsY - PAD - FONT_HGT
    local top = self:titleBarHeight() + PAD
    self.songBox:setX(PAD)
    self.songBox:setY(top)
    self.songBox:setWidth(self.width - PAD * 2)
    self.songBox:setHeight(math.max(ROW, statusY - PAD - top))
    self.status:setY(statusY)

    local x = PAD
    for _, el in ipairs({ self.bpmLabel, self.bpmBox, self.volumeLabel, self.volume }) do
        el:setX(x)
        el:setY(controlsY)
        x = x + el:getWidth() + PAD
    end
    self.volume:setWidth(math.max(60, self.width - PAD - self.volume:getX()))

    x = PAD
    for _, b in ipairs({ self.playButton, self.stopButton, self.saveButton, self.loadButton }) do
        b:setX(x)
        b:setY(buttonsY)
        x = x + b:getWidth() + PAD
    end
    self.laidOutW, self.laidOutH = self.width, self.height
end

function MusicWindow:prerender()
    ISCollapsableWindow.prerender(self)
    if self.laidOutW ~= self.width or self.laidOutH ~= self.height then self:layout() end
    local c = self:controller()
    self.playButton:setTitle(getText(c:isPlaying() and "IGUI_PlayIt_Pause"
        or (c:isPaused() and "IGUI_PlayIt_Resume" or "IGUI_PlayIt_Play")))
end

function MusicWindow:onSongChanged()
    local bpm = PlayIt.Song.readBpmHeader(self.songBox:getText())
    if bpm then self.bpmBox:setText(tostring(bpm)) end
end

function MusicWindow:setStatus(text)
    self.status:setName(text or "")
end

function MusicWindow:warningsFor(text, bpm)
    local song = PlayIt.Song.parse(text, bpm)
    local w = song.warnings[1]
    if w == nil then return "" end
    return getText("IGUI_PlayIt_Warn_" .. w.key, tostring(w.line))
end

-- the place to send for furniture: the clicked tile, plus for drums the kit around the musician now.
-- nil and the reason ("Gone", "TooFar", "NoSticks", "Busy") when they can't play here
function MusicWindow:worldPlace()
    local p = self.place
    local place = { x = p.x, y = p.y, z = p.z }
    local ctx = PlayIt.Furniture.ctxFor(self.player)
    if PlayIt.Instruments.defs[self.fullType].drums then
        place.kit = PlayIt.Furniture.kitAround(PlayIt.Furniture.scan(ctx.px, ctx.py, ctx.pz), ctx.px, ctx.py, ctx.pz)
        if #place.kit == 0 then return nil, ctx.hasStick and "TooFar" or "NoSticks" end
    end
    local ok, why = PlayIt.Furniture.check(self.fullType, place, ctx)
    if not ok then return nil, why end
    if PlayIt.Playback.busyAt(self.fullType, place, PlayIt.Net.idOf(self.player)) then return nil, "Busy" end
    return place
end

function MusicWindow:onPlay()
    local c = self:controller()
    if c:isPlaying() then
        PlayIt.Controls.pause(self.player)
        return
    end
    local text = self.songBox:getText()
    local bpm = tonumber(self.bpmBox:getText()) or PlayIt.Song.BPM_DEFAULT
    local place
    if PlayIt.Instruments.isWorld(self.fullType) then
        local why
        place, why = self:worldPlace()
        if place == nil then
            self:setStatus(getText("IGUI_PlayIt_" .. why))
            return
        end
    else
        local item = self.player:getPrimaryHandItem()
        local queued = ISTimedActionQueue.hasActionType(self.player, "ISEquipWeaponAction")
        if not queued and (item == nil or item:getFullType() ~= self.fullType) then
            self:setStatus(getText("IGUI_PlayIt_NotHolding"))
            return
        end
    end
    if #PlayIt.Song.compact(text) > PlayIt.Session.MAX_TEXT then
        self:setStatus(getText("IGUI_PlayIt_TooLong"))
        return
    end
    self:setStatus(self:warningsFor(text, bpm))
    PlayIt.Controls.play(self.player, text, bpm, self.volume:getCurrentValue() / 100, self.fullType, place)
end

function MusicWindow:onStop()
    PlayIt.Controls.stop(self.player)
end

function MusicWindow:onSave()
    local modal = ISTextBox:new(0, 0, 300, 150, getText("IGUI_PlayIt_SaveAs"), "", self, MusicWindow.onSaveName,
        self.player:getPlayerNum())
    modal:initialise()
    modal:addToUIManager()
end

function MusicWindow:onSaveName(button)
    if button.internal ~= "OK" then return end
    local bpm = tonumber(self.bpmBox:getText()) or PlayIt.Song.BPM_DEFAULT
    local name = PlayIt.SongFiles.save(button.parent.entry:getText(), self.songBox:getText(), bpm)
    self:setStatus(name and getText("IGUI_PlayIt_Saved", name) or getText("IGUI_PlayIt_BadName"))
end

function MusicWindow:onLoad()
    local names = PlayIt.SongFiles.list()
    local menu = ISContextMenu.get(self.player:getPlayerNum(), getMouseX(), getMouseY())
    if #names == 0 then
        menu:addOption(getText("IGUI_PlayIt_NoSongs"))
        return
    end
    for _, name in ipairs(names) do
        menu:addOption(name, self, MusicWindow.loadSong, name)
    end
end

function MusicWindow:loadSong(name)
    local text, bpm = PlayIt.SongFiles.load(name)
    if text == nil then return end
    self.songBox:setText(text)
    if bpm then self.bpmBox:setText(tostring(bpm)) end
    self:setStatus("")
end

-- Esc pauses while playing, and works as usual otherwise
function MusicWindow:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE and self:isVisible() and self:controller():isPlaying()
end

function MusicWindow:onKeyRelease(key)
    if key == Keyboard.KEY_ESCAPE and self:isVisible() and self:controller():isPlaying() then
        PlayIt.Controls.pause(self.player)
    end
end

-- closing while a song plays or is paused leaves the widget; closing the widget stops it
function MusicWindow:close()
    ISCollapsableWindow.close(self)
    local c = self:controller()
    if c:isPlaying() or c:isPaused() then PlayIt.MiniWidget.show(self.player, self.fullType, self.place) end
end

function MusicWindow:new(x, y, width, height, player)
    local o = ISCollapsableWindow.new(self, x, y, width, height)
    o.player = player
    o.minimumWidth = 360
    o.minimumHeight = 260
    return o
end
