-- Drives local playback of every musician in earshot.

require "PlayIt/Playback"

Events.OnTick.Add(function()
    PlayIt.Playback.update(getTimestampMs())
end)
