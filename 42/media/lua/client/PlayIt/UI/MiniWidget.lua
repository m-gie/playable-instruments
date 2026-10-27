-- Small movable panel left when the music window is closed during a song: Pause/Resume, Open, and
-- a close button that stops the music.

require "ISUI/ISPanel"
require "PlayIt/Controls"

PlayIt = PlayIt or {}
PlayIt.MiniWidget = ISPanel:derive("PlayItMiniWidget")
local MiniWidget = PlayIt.MiniWidget

local PAD = 6
local FONT_HGT = getTextManager():getFontHeight(UIFont.Small)
local ROW = FONT_HGT + 6

local widgets = {}

-- place: the furniture's tile (nil for hand-held instruments), so Resume and Open go back to it
function MiniWidget.show(player, fullType, place)
    local w = widgets[player:getPlayerNum()]
    if w == nil then
        w = MiniWidget:new(getCore():getScreenWidth() - 300, 120, player)
        w:initialise()
        w:addToUIManager()
        widgets[player:getPlayerNum()] = w
    end
    w.player = player
    w.fullType = fullType
    w.place = place
    w.label:setName(PlayIt.Instruments.displayName(fullType))
    w:setVisible(true)
end

function MiniWidget.hide(player)
    local w = widgets[player:getPlayerNum()]
    if w then w:setVisible(false) end
end

function MiniWidget:createChildren()
    self.label = ISLabel:new(PAD, PAD, FONT_HGT, "", 1, 1, 1, 1, UIFont.Small, true)
    self:addChild(self.label)
    local y = PAD + FONT_HGT + PAD
    local function button(x, w, key, onClick)
        local b = ISButton:new(x, y, w, ROW, getText(key), self, onClick)
        b:initialise()
        self:addChild(b)
        return b
    end
    self.pauseButton = button(PAD, 90, "IGUI_PlayIt_Pause", MiniWidget.onPause)
    self.openButton = button(PAD * 2 + 90, 70, "IGUI_PlayIt_Open", MiniWidget.onOpen)
    self.closeButton = button(self.width - PAD - ROW, ROW, "X", MiniWidget.onClose)
    self.closeButton:setY(PAD)
end

function MiniWidget:prerender()
    ISPanel.prerender(self)
    local c = PlayIt.Controls.get(self.player)
    if not (c:isPlaying() or c:isPaused()) then
        self:setVisible(false) -- song over or stopped elsewhere
        return
    end
    self.pauseButton:setTitle(getText(c:isPlaying() and "IGUI_PlayIt_Pause" or "IGUI_PlayIt_Resume"))
end

function MiniWidget:onPause()
    local c = PlayIt.Controls.get(self.player)
    if c:isPlaying() then
        PlayIt.Controls.pause(self.player)
    else
        PlayIt.MusicWindow.open(self.player, self.fullType, self.place):onPlay()
        self:setVisible(true)
        PlayIt.MusicWindow.get(self.player):setVisible(false)
    end
end

function MiniWidget:onOpen()
    PlayIt.MusicWindow.open(self.player, self.fullType, self.place)
end

function MiniWidget:onClose()
    PlayIt.Controls.stop(self.player)
    self:setVisible(false)
end

-- Esc pauses here too while the window is closed
function MiniWidget:isKeyConsumed(key)
    return key == Keyboard.KEY_ESCAPE and self:isVisible() and PlayIt.Controls.get(self.player):isPlaying()
end

function MiniWidget:onKeyRelease(key)
    if self:isKeyConsumed(key) then PlayIt.Controls.pause(self.player) end
end

function MiniWidget:new(x, y, player)
    local o = ISPanel.new(self, x, y, 200, PAD * 3 + FONT_HGT + ROW)
    o.player = player
    o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.8 }
    return o
end
