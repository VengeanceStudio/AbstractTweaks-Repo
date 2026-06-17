-- ============================================================================
-- Abstract Tweaks - Standalone Quality of Life Addon
-- ============================================================================

local AbstractTweaks = LibStub("AceAddon-3.0"):NewAddon("AbstractTweaks", "AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0")

AbstractTweaks.version = "12.0.7.0"

-- ============================================================================
-- LOCAL VARIABLES
-- ============================================================================

-- Hidden frame for hiding UI elements
local hiddenFrame = CreateFrame("Frame")
hiddenFrame:Hide()

local LOADOUT_SERIALIZATION_VERSION
local lootEpoch = 0
local LOOT_DELAY = 0.3

-- ============================================================================
-- STATIC POPUP DIALOGS
-- ============================================================================

StaticPopupDialogs["ABSTRACTTWEAKS_RELOAD_CONFIRM"] = {
    text = "This action requires a UI reload. Reload now?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        if not InCombatLockdown() then
            ReloadUI()
        else
            print("|cffff0000Abstract Tweaks:|r Cannot reload UI while in combat. Please leave combat and run /reload.")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["ABSTRACTTWEAKS_TALENT_IMPORT_ERROR"] = {
    text = "%s",
    button1 = OKAY,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
}

-- ============================================================================
-- DATABASE DEFAULTS
-- ============================================================================

local defaults = {
    profile = {
        fastLoot = true,
        hideGryphons = false,
        hideBagBar = false,
        importOverwriteEnabled = true,
        autoRepair = true,
        autoRepairGuild = false,
        autoSellJunk = true,
        revealMap = true,
        autoDelete = true,
        autoScreenshot = false,
        skipCutscenes = false,
        autoInsertKey = true,
        questFrameScale = 1.0,
        questFrameX = 0,
        questFrameY = 0,
        questFrameCustomPosition = false,
        groupFinderScale = 1.25,
        groupFinderX = 0,
        groupFinderY = 0,
        groupFinderCustomPosition = false,
        recolorDelvePins = true,
        delvePinColor = { r = 0.2, g = 1.0, b = 0.8, a = 1.0 },
        bountifulDelvePinColor = { r = 1.0, g = 0.84, b = 0.0, a = 1.0 },
        oneKeyFishing = false,
        oneKeyFishingFirstTime = true,
        customWhisperSound = false,
        whisperSoundPreset = "default",
        whisperSoundID = 567482,
    }
}

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function AbstractTweaks:OnInitialize()
    LOADOUT_SERIALIZATION_VERSION = C_Traits.GetLoadoutSerializationVersion and C_Traits.GetLoadoutSerializationVersion() or 1
    
    self.db = LibStub("AceDB-3.0"):New("AbstractTweaksDB", defaults, true)
    
    -- Initialize Tile Database
    self:InitializeTileDatabase()
    
    -- Register slash commands
    self:RegisterChatCommand("tweaks", "SlashCommand")
    self:RegisterChatCommand("abstracttweaks", "SlashCommand")
    self:RegisterChatCommand("at", "SlashCommand")
    
    -- Register diagnostic slash commands
    SLASH_ABSTRACTTWEAKSSTATUS1 = "/tweaksstatus"
    SlashCmdList["ABSTRACTTWEAKSSTATUS"] = function(msg)
        print("|cff00FF7FAbstract Tweaks Status:|r")
        if self.db then
            print("  Reveal Map: " .. tostring(self.db.profile.revealMap))
            print("  Recolor Delve Pins: " .. tostring(self.db.profile.recolorDelvePins))
            print("  Last Revealed Map ID: " .. tostring(self.lastRevealedMapID or "none"))
            local currentMap = C_Map.GetBestMapForUnit("player")
            print("  Current Map ID: " .. tostring(currentMap or "unknown"))
            print("  Tweaks Initialized: " .. tostring(self.tweaksInitialized))
            
            -- Show tile database status
            if self.TileDatabase and next(self.TileDatabase) then
                local stats = self:GetTileDatabaseStats()
                print("  Tile Database: " .. stats.maps .. " maps, " .. stats.tiles .. " tiles")
            else
                print("  Tile Database: Empty")
            end
        else
            print("  Database not ready")
        end
    end
    
    -- Print welcome message
    print("|cff00FF7FAbstract Tweaks|r v" .. self.version .. " loaded. Type |cff00FFFF/tweaks|r for options.")
end

function AbstractTweaks:OnEnable()
    -- Ensure delve pin colors are properly initialized
    if not self.db.profile.delvePinColor or type(self.db.profile.delvePinColor) ~= "table" then
        self.db.profile.delvePinColor = { r = 0.2, g = 1.0, b = 0.8, a = 1.0 }
    end
    
    if not self.db.profile.bountifulDelvePinColor or type(self.db.profile.bountifulDelvePinColor) ~= "table" then
        self.db.profile.bountifulDelvePinColor = { r = 1.0, g = 0.84, b = 0.0, a = 1.0 }
    end
    
    -- Register events
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("BAG_UPDATE_DELAYED")
    self:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    self:RegisterEvent("MERCHANT_SHOW")
    self:RegisterEvent("MERCHANT_CLOSED")
    self:RegisterEvent("ADDON_LOADED")
    
    if self.db.profile.autoScreenshot then
        self:RegisterEvent("ACHIEVEMENT_EARNED")
    end
    
    if self.db.profile.fastLoot then
        self:RegisterEvent("LOOT_READY")
    end
    
    -- Hook WorldMapFrame to refresh when opened
    if self.db.profile.revealMap then
        self:HookWorldMapFrame()
    end
    
    -- Immediate bag bar hiding setup
    if self.db.profile.hideBagBar then
        self:HideBagBar()
        C_Timer.After(0.5, function() self:HideBagBar() end)
        C_Timer.After(2, function() self:HideBagBar() end)
        C_Timer.After(5, function() self:HideBagBar() end)
    end
    
    -- Hook cutscene frames for auto-skip
    if self.db.profile.skipCutscenes then
        self:HookCutscenes()
    end
    
    -- Hook StaticPopup for auto-delete
    if self.db.profile.autoDelete then
        self:HookAutoDelete()
    end
    
    -- Setup talent import
    if self.db.profile.importOverwriteEnabled then
        self:SetupTalentImportWhenReady()
    end
    
    -- Setup auto keystone insertion
    if self.db.profile.autoInsertKey then
        self:HookKeystoneFrame()
    end
    
    -- Setup delve pin recoloring
    if self.db.profile.recolorDelvePins then
        C_Timer.After(3, function() 
            self:SetupDelvePinRecoloring()
        end)
    end
    
    -- Setup one-key fishing
    if self.db.profile.oneKeyFishing then
        self:SetupOneKeyFishing()
    end
    
    -- Setup custom whisper sound
    if self.db.profile.customWhisperSound then
        self:SetupCustomWhisperSound()
    end
    
    -- Register quest and gossip frame events
    self:RegisterEvent("QUEST_DETAIL")
    self:RegisterEvent("QUEST_PROGRESS")
    self:RegisterEvent("QUEST_COMPLETE")
    self:RegisterEvent("QUEST_GREETING")
    self:RegisterEvent("GOSSIP_SHOW")
    
    -- Hook Group Finder frame for scaling
    if PVEFrame then
        self:HookScript(PVEFrame, "OnShow", "ApplyGroupFinderScale")
    else
        C_Timer.After(2, function()
            if PVEFrame then
                self:HookScript(PVEFrame, "OnShow", "ApplyGroupFinderScale")
            end
        end)
    end
    
    -- Apply initial scaling
    self:ApplyQuestFrameScale()
    self:ApplyGroupFinderScale()
    
    -- Set up options panel
    C_Timer.After(0.5, function()
        self:SetupOptions()
    end)
end

-- ============================================================================
-- SLASH COMMAND HANDLER
-- ============================================================================

function AbstractTweaks:SlashCommand(input)
    -- Open options panel using AceConfigDialog
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    AceConfigDialog:Open("AbstractTweaks")
end

-- ============================================================================
-- TILE DATABASE FUNCTIONS
-- ============================================================================

function AbstractTweaks:InitializeTileDatabase()
    if not self.TileDatabase then
        self.TileDatabase = {}
    end
end

function AbstractTweaks:GetMapTileData(mapID)
    if self.TileDatabase and self.TileDatabase[mapID] then
        return self.TileDatabase[mapID]
    end
    return nil
end

function AbstractTweaks:GetTileDatabaseStats()
    local mapCount = 0
    local tileCount = 0
    
    if self.TileDatabase then
        for mapID, tiles in pairs(self.TileDatabase) do
            mapCount = mapCount + 1
            for key, fileIDs in pairs(tiles) do
                local _, count = string.gsub(fileIDs, ",", "")
                tileCount = tileCount + count + 1
            end
        end
    end
    
    return {
        maps = mapCount,
        tiles = tileCount
    }
end

-- ============================================================================
-- OPTIONS PANEL
-- ============================================================================

function AbstractTweaks:SetupOptions()
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    
    local options = {
        name = "Abstract Tweaks",
        type = "group",
        get = function(info) return self.db.profile[info[#info]] end,
        set = function(info, value) self.db.profile[info[#info]] = value end,
        args = {
            header = {
                type = "description",
                name = "|cff00FF7FAbstract Tweaks|r v" .. self.version .. "\n" ..
                       "Quality-of-life tweaks for World of Warcraft\n\n",
                fontSize = "medium",
                order = 1,
            }
        }
    }
    
    -- Add tweak options
    local tweakOptions = self:GetOptions()
    if tweakOptions and tweakOptions.args then
        for k, v in pairs(tweakOptions.args) do
            options.args[k] = v
        end
    end
    
    AceConfig:RegisterOptionsTable("AbstractTweaks", options)
    AceConfigDialog:AddToBlizOptions("AbstractTweaks", "Abstract Tweaks")
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

function AbstractTweaks:UPDATE_INVENTORY_DURABILITY()
    if self.db.profile.hideBagBar then
        self:HideBagBar()
    end
end

function AbstractTweaks:BAG_UPDATE_DELAYED()
    if self.db.profile.hideBagBar then
        self:HideBagBar()
    end
end

function AbstractTweaks:PLAYER_LOGIN()
    if self.db.profile.hideBagBar then
        C_Timer.After(1, function()
            self:HideBagBar()
        end)
        C_Timer.After(3, function()
            self:HideBagBar()
        end)
    end
end

function AbstractTweaks:ADDON_LOADED(event, addonName)
    if addonName == "Blizzard_EditMode" or addonName == "Blizzard_BagBar" then
        if self.db and self.db.profile.hideBagBar then
            C_Timer.After(0.5, function()
                self:HideBagBar()
            end)
        end
    end
end

function AbstractTweaks:PLAYER_ENTERING_WORLD()
    if self.tweaksInitialized then 
        -- Refresh delve pins on zone change
        if self.db and self.db.profile.recolorDelvePins then
            C_Timer.After(1, function()
                if self.db and self.db.profile.recolorDelvePins then
                    self:ColorDelvePins()
                    self:ColorMinimapDelvePins()
                end
            end)
            C_Timer.After(3, function()
                if self.db and self.db.profile.recolorDelvePins then
                    self:ColorMinimapDelvePins()
                end
            end)
        end
        
        -- Reveal map on zone change if enabled
        if self.db and self.db.profile.revealMap then
            local currentMapID = C_Map.GetBestMapForUnit("player")
            if currentMapID and currentMapID ~= self.lastRevealedMapID then
                self.lastRevealedMapID = currentMapID
                C_Timer.After(2, function()
                    if self.db and self.db.profile.revealMap then
                        self:RevealMap()
                    end
                end)
            end
        end
        return 
    end
    self.tweaksInitialized = true
    
    -- Apply tweaks with delays
    C_Timer.After(0.5, function() self:ApplyTweaks() end)
    C_Timer.After(2, function() self:ApplyTweaks() end)
    C_Timer.After(5, function() self:ApplyTweaks() end)
    
    -- Bag bar hiding with repeated attempts
    if self.db.profile.hideBagBar then
        self:HideBagBar()
        C_Timer.After(1, function() self:HideBagBar() end)
        C_Timer.After(3, function() self:HideBagBar() end)
    end
    
    -- Reveal map if enabled (initial load only)
    if self.db.profile.revealMap then
        local currentMapID = C_Map.GetBestMapForUnit("player")
        if currentMapID then
            self.lastRevealedMapID = currentMapID
            C_Timer.After(3, function()
                if self.db and self.db.profile.revealMap then
                    self:RevealMap()
                end
            end)
        end
    end
end

function AbstractTweaks:ACHIEVEMENT_EARNED(event, achievementID)
    if self.db.profile.autoScreenshot and achievementID then
        Screenshot()
        print("|cff00ff00[Abstract Tweaks]|r Achievement earned, screenshot taken.")
    end
end

function AbstractTweaks:LOOT_READY()
    if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
        if (GetTime() - lootEpoch) >= LOOT_DELAY then
            if TSMDestroyBtn and TSMDestroyBtn:IsShown() and TSMDestroyBtn:GetButtonState() == "DISABLED" then
                lootEpoch = GetTime()
                return
            end
            for i = GetNumLootItems(), 1, -1 do
                LootSlot(i)
            end
            lootEpoch = GetTime()
        end
    end
end

function AbstractTweaks:QUEST_DETAIL()
    self:ApplyQuestFrameScale()
end

function AbstractTweaks:QUEST_PROGRESS()
    self:ApplyQuestFrameScale()
end

function AbstractTweaks:QUEST_COMPLETE()
    self:ApplyQuestFrameScale()
end

function AbstractTweaks:QUEST_GREETING()
    self:ApplyQuestFrameScale()
end

function AbstractTweaks:GOSSIP_SHOW()
    self:ApplyQuestFrameScale()
end

function AbstractTweaks:LORE_TEXT_UPDATED_CAMPAIGN()
    if self.db and self.db.profile.recolorDelvePins then
        C_Timer.After(0.2, function()
            self:ColorDelvePins()
        end)
    end
end

function AbstractTweaks:QUEST_LOG_UPDATE()
    if self.db and self.db.profile.recolorDelvePins then
        C_Timer.After(0.2, function()
            self:ColorDelvePins()
        end)
    end
end

function AbstractTweaks:MERCHANT_SHOW()
    if self.db.profile.autoRepair then
        C_Timer.After(0.5, function()
            if self.db.profile.autoRepair then
                self:AutoRepair()
            end
        end)
    end
    
    if self.db.profile.autoSellJunk then
        C_Timer.After(0.5, function()
            if self.db.profile.autoSellJunk then
                self:AutoSellJunk()
            end
        end)
    end
end

function AbstractTweaks:MERCHANT_CLOSED()
    -- Cleanup if needed
end

function AbstractTweaks:UNIT_SPELLCAST_CHANNEL_START(event, unit, _, spellID)
    if unit ~= "player" then return end
    
    local FishingIDs = {
        [131474] = true, [131490] = true, [131476] = true, [7620] = true,
        [7731] = true, [7732] = true, [18248] = true, [33095] = true,
        [51294] = true, [88868] = true, [110410] = true, [158743] = true, [377895] = true,
    }
    
    if not FishingIDs[spellID] or not self.fishingButton then return end
    
    SetCVar("SoftTargetInteract", "3")
    SetCVar("SoftTargetInteractArc", "2")
    SetCVar("SoftTargetInteractRange", "60")
    
    if InCombatLockdown() then return end
    
    local key1, key2 = GetBindingKey("ABSTRACTTWEAKS_FISHING")
    if key1 then
        SetOverrideBinding(self.fishingButton, true, key1, "INTERACTTARGET")
    end
    if key2 then
        SetOverrideBinding(self.fishingButton, true, key2, "INTERACTTARGET")
    end
end

function AbstractTweaks:UNIT_SPELLCAST_CHANNEL_STOP(event, unit, _, spellID)
    if unit ~= "player" then return end
    
    local FishingIDs = {
        [131474] = true, [131490] = true, [131476] = true, [7620] = true,
        [7731] = true, [7732] = true, [18248] = true, [33095] = true,
        [51294] = true, [88868] = true, [110410] = true, [158743] = true, [377895] = true,
    }
    
    if not FishingIDs[spellID] or not self.fishingButton then return end
    
    if not InCombatLockdown() then
        ClearOverrideBindings(self.fishingButton)
    end
end

function AbstractTweaks:CHAT_MSG_WHISPER(event, text, playerName, ...)
    if self.db and self.db.profile.customWhisperSound and self.db.profile.whisperSoundID then
        PlaySoundFile(self.db.profile.whisperSoundID)
    end
end

function AbstractTweaks:CHAT_MSG_BN_WHISPER(event, text, playerName, ...)
    if self.db and self.db.profile.customWhisperSound and self.db.profile.whisperSoundID then
        PlaySoundFile(self.db.profile.whisperSoundID)
    end
end


function AbstractTweaks:ApplyGroupFinderScale()
    local scale = self.db.profile.groupFinderScale or 1.0
    local useCustomPos = self.db.profile.groupFinderCustomPosition
    local x = self.db.profile.groupFinderX
    local y = self.db.profile.groupFinderY
    
    -- Apply to PVEFrame (Group Finder)
    if PVEFrame then
        PVEFrame:SetScale(scale)
        if useCustomPos then
            PVEFrame:ClearAllPoints()
            PVEFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end
    end
end

function AbstractTweaks:ApplyQuestFrameScale()
    local scale = self.db.profile.questFrameScale or 1.0
    local useCustomPos = self.db.profile.questFrameCustomPosition
    local x = self.db.profile.questFrameX
    local y = self.db.profile.questFrameY
    
    -- Apply to QuestFrame
    if QuestFrame then
        QuestFrame:SetScale(scale)
        if useCustomPos then
            QuestFrame:ClearAllPoints()
            QuestFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end
    end
    
    -- Apply to GossipFrame (dialogue/gossip windows)
    if GossipFrame then
        GossipFrame:SetScale(scale)
        if useCustomPos then
            GossipFrame:ClearAllPoints()
            GossipFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end
    end
end

function AbstractTweaks:QUEST_DETAIL()
    self:ApplyQuestFrameScale()
end

function AbstractTweaks:QUEST_PROGRESS()
    self:ApplyQuestFrameScale()
end

function AbstractTweaks:QUEST_COMPLETE()
    self:ApplyQuestFrameScale()
end

function AbstractTweaks:QUEST_GREETING()
    self:ApplyQuestFrameScale()
end

function AbstractTweaks:GOSSIP_SHOW()
    self:ApplyQuestFrameScale()
end

function AbstractTweaks:LOOT_READY()
    -- Instant looting: Auto-loot all items immediately when loot window opens
    if GetCVarBool("autoLootDefault") ~= IsModifiedClick("AUTOLOOTTOGGLE") then
        if (GetTime() - lootEpoch) >= LOOT_DELAY then
            -- TSM compatibility: Don't loot if TSM destroy button is active
            if TSMDestroyBtn and TSMDestroyBtn:IsShown() and TSMDestroyBtn:GetButtonState() == "DISABLED" then
                lootEpoch = GetTime()
                return
            end
            -- Loot all items in reverse order for better compatibility
            for i = GetNumLootItems(), 1, -1 do
                LootSlot(i)
            end
            lootEpoch = GetTime()
        end
    end
end

function AbstractTweaks:BAG_UPDATE_DELAYED()
    if self.db.profile.hideBagBar then
        self:HideBagBar()
    end
end

function AbstractTweaks:PLAYER_LOGIN()
    if self.db.profile.hideBagBar then
        C_Timer.After(1, function()
            self:HideBagBar()
        end)
        C_Timer.After(3, function()
            self:HideBagBar()
        end)
    end
end

function AbstractTweaks:ADDON_LOADED(event, addonName)
    -- Hide bag bar when relevant addons load
    if addonName == "Blizzard_EditMode" or addonName == "Blizzard_BagBar" then
        if self.db and self.db.profile.hideBagBar then
            C_Timer.After(0.5, function()
                self:HideBagBar()
            end)
        end
    end
    
    -- Hook AddOn Manager when it loads
    if addonName == "Blizzard_AddOnManager" then
        -- Addon list sorting has been replaced by the AddonManager module
    end
end

function AbstractTweaks:PLAYER_ENTERING_WORLD()
    -- Only run tweaks setup once, not on every zone change
    if self.tweaksInitialized then 
        -- Refresh delve pins on zone change (reduced from 5 calls to 2)
        if self.db and self.db.profile.recolorDelvePins then
            C_Timer.After(1, function()
                if self.db and self.db.profile.recolorDelvePins then
                    self:ColorDelvePins()
                    self:ColorMinimapDelvePins()
                end
            end)
            C_Timer.After(3, function()
                if self.db and self.db.profile.recolorDelvePins then
                    self:ColorMinimapDelvePins()
                end
            end)
        end
        
        -- Reveal map on zone change if enabled (but only once per zone)
        if self.db and self.db.profile.revealMap then
            local currentMapID = C_Map.GetBestMapForUnit("player")
            if currentMapID and currentMapID ~= self.lastRevealedMapID then
                self.lastRevealedMapID = currentMapID
                C_Timer.After(2, function()
                    if self.db and self.db.profile.revealMap then
                        self:RevealMap()
                    end
                end)
            end
        end
        return 
    end
    self.tweaksInitialized = true
    
    -- Apply tweaks with delays (reduced from 5 calls to 3)
    C_Timer.After(0.5, function() self:ApplyTweaks() end)
    C_Timer.After(2, function() self:ApplyTweaks() end)
    C_Timer.After(5, function() self:ApplyTweaks() end)
    
    -- Bag bar hiding with repeated attempts
    if self.db.profile.hideBagBar then
        self:HideBagBar()
        C_Timer.After(1, function() self:HideBagBar() end)
        C_Timer.After(3, function() self:HideBagBar() end)
    end
    
    -- Reveal map if enabled (initial load only)
    if self.db.profile.revealMap then
        local currentMapID = C_Map.GetBestMapForUnit("player")
        if currentMapID then
            self.lastRevealedMapID = currentMapID
            C_Timer.After(3, function()
                if self.db and self.db.profile.revealMap then
                    self:RevealMap()
                end
            end)
        end
    end
end

function AbstractTweaks:ACHIEVEMENT_EARNED(event, achievementID)
    if self.db.profile.autoScreenshot and achievementID then
        Screenshot()
        print("|cff00ff00[Abstract Tweaks]|r Achievement earned, screenshot taken.")
    end
end

function AbstractTweaks:RevealMap()
    -- Implementation based on Leatrix Maps approach
    -- Hook into the MapExplorationPinTemplate to add unexplored textures
    
    if not WorldMapFrame then return end
    
    -- Validate that the map canvas is properly initialized
    local mapCanvas = WorldMapFrame.ScrollContainer
    if not mapCanvas then return end
    
    -- Check if the map has zoom level data (prevents the ipairs error)
    if not mapCanvas.zoomLevels or type(mapCanvas.zoomLevels) ~= "table" then
        return
    end
    
    -- Find the exploration pin (the system that manages fog of war)
    for pin in WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        if pin and pin.RefreshOverlays then
            -- Use pcall to safely refresh overlays
            local success, err = pcall(function()
                pin:RefreshOverlays(true)
            end)
            if not success then
                -- Silently fail, map might not be fully initialized yet
            end
        end
    end
    
    -- Also handle Battlefield Map if it exists
    if BattlefieldMapFrame then
        local battleCanvas = BattlefieldMapFrame.ScrollContainer
        if battleCanvas and battleCanvas.zoomLevels and type(battleCanvas.zoomLevels) == "table" then
            for pin in BattlefieldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
                if pin and pin.RefreshOverlays then
                    local success, err = pcall(function()
                        pin:RefreshOverlays(true)
                    end)
                end
            end
        end
    end
end

-- ============================================================================
-- WORLDMAP HOOKS
-- ============================================================================

function AbstractTweaks:HookWorldMapFrame()
    if self.worldMapHooked then return end
    if not WorldMapFrame then return end
    
    local module = self
    
    -- Store the original RefreshOverlays function from MapExplorationPinMixin
    if MapExplorationPinMixin and MapExplorationPinMixin.RefreshOverlays then
        local originalRefreshOverlays = MapExplorationPinMixin.RefreshOverlays
        
        -- Override RefreshOverlays to show all tiles (explored and unexplored)
        function MapExplorationPinMixin:RefreshOverlays(ignoreExplored)
            -- Always call the original function first
            originalRefreshOverlays(self, ignoreExplored)
            
            -- Only reveal if the option is enabled
            if not (module.db and module.db.profile.revealMap) then
                return
            end
            
            -- Get current map info
            local mapID = self:GetMap() and self:GetMap():GetMapID()
            if not mapID then return end
            
            -- Get the map canvas positioning for texture placement
            local mapRectLeft, mapRectRight, mapRectTop, mapRectBottom = self:GetMap():GetMapRectOnCanvas()
            if not mapRectLeft then return end
            
            -- Check if we have tile database for this map
            local tileData = AbstractTweaks:GetMapTileData(mapID)
            
            if tileData then
                -- Use the pre-built tile database (reveals unexplored areas)
                for key, fileIDsString in pairs(tileData) do
                    -- Parse the key: "width:height:offsetX:offsetY"
                    local width, height, offsetX, offsetY = key:match("(%d+):(%d+):(%d+):(%d+)")
                    if width and height and offsetX and offsetY then
                        width = tonumber(width)
                        height = tonumber(height)
                        offsetX = tonumber(offsetX)
                        offsetY = tonumber(offsetY)
                        
                        -- Parse file data IDs (comma-separated)
                        for fileIDStr in fileIDsString:gmatch("%d+") do
                            local fileDataID = tonumber(fileIDStr)
                            if fileDataID and fileDataID > 0 then
                                -- Acquire a texture from the pool
                                local texture = self.overlayTexturePool:Acquire()
                                
                                if texture then
                                    -- Set the texture using file data ID
                                    texture:SetTexture(fileDataID, nil, nil, "TRILINEAR")
                                    
                                    -- Set size
                                    texture:SetSize(width, height)
                                    
                                    -- Position the texture
                                    texture:ClearAllPoints()
                                    texture:SetPoint("TOPLEFT", self:GetMap():GetCanvas(), "TOPLEFT",
                                        mapRectLeft + offsetX,
                                        -(mapRectTop + offsetY))
                                    
                                    -- Ensure it's fully visible
                                    texture:SetAlpha(1.0)
                                    texture:SetDrawLayer("ARTWORK", 1)
                                    texture:Show()
                                end
                            end
                        end
                    end
                end
            else
                -- Fallback: Use Blizzard's explored textures only (no database for this map)
                local exploredMapTextures = C_MapExplorationInfo.GetExploredMapTextures(mapID)
                if exploredMapTextures then
                    for _, textureInfo in ipairs(exploredMapTextures) do
                        -- Only process tiles that have actual file data (explored tiles)
                        if textureInfo.fileDataIDs and #textureInfo.fileDataIDs > 0 then
                            for _, fileDataID in ipairs(textureInfo.fileDataIDs) do
                                if fileDataID and fileDataID > 0 then
                                    -- Acquire a texture from the pool
                                    local texture = self.overlayTexturePool:Acquire()
                                    
                                    if texture then
                                        -- Set the texture
                                        texture:SetTexture(fileDataID, nil, nil, "TRILINEAR")
                                        
                                        -- Set size
                                        local width = textureInfo.textureWidth or 256
                                        local height = textureInfo.textureHeight or 256
                                        texture:SetSize(width, height)
                                        
                                        -- Position the texture
                                        local offsetX = textureInfo.offsetX or 0
                                        local offsetY = textureInfo.offsetY or 0
                                        
                                        texture:ClearAllPoints()
                                        texture:SetPoint("TOPLEFT", self:GetMap():GetCanvas(), "TOPLEFT",
                                            mapRectLeft + offsetX,
                                            -(mapRectTop + offsetY))
                                        
                                        -- Ensure it's fully visible
                                        texture:SetAlpha(1.0)
                                        texture:SetDrawLayer("ARTWORK", 1)
                                        texture:Show()
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Hook WorldMapFrame to trigger reveal when shown
    WorldMapFrame:HookScript("OnShow", function()
        if module.db and module.db.profile.revealMap then
            -- Trigger a refresh on exploration pins
            for pin in WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
                if pin and pin.RefreshOverlays then
                    pin:RefreshOverlays(true)
                end
            end
        end
    end)
    
    -- Hook map changes to trigger reveal
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
        if module.db and module.db.profile.revealMap then
            C_Timer.After(0.1, function()
                for pin in WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
                    if pin and pin.RefreshOverlays then
                        pin:RefreshOverlays(true)
                    end
                end
            end)
        end
    end)
    
    self.worldMapHooked = true
end

-- ============================================================================
-- SKIP CUTSCENES
-- ============================================================================

function AbstractTweaks:HookCutscenes()
    if self.cutscenesHooked then return end
    
    local module = self
    
    -- Hook cinematic frame (in-game cinematics)
    if CinematicFrame then
        CinematicFrame:HookScript("OnShow", function()
            if module.db and module.db.profile.skipCutscenes then
                CinematicFrame_CancelCinematic()
            end
        end)
    end
    
    -- Hook movie frame (pre-rendered movies)
    if MovieFrame then
        MovieFrame:HookScript("OnShow", function()
            if module.db and module.db.profile.skipCutscenes then
                MovieFrame:StopMovie()
            end
        end)
    end
    
    self.cutscenesHooked = true
end

-- ============================================================================
-- AUTO INSERT MYTHIC KEYSTONE
-- ============================================================================

function AbstractTweaks:HookKeystoneFrame()
    if self.keystoneHooked then return end
    
    -- Wait for Blizzard_ChallengesUI to load
    if not ChallengesKeystoneFrame then
        -- Hook ADDON_LOADED to catch when it loads
        local frame = CreateFrame("Frame")
        frame:RegisterEvent("ADDON_LOADED")
        frame:SetScript("OnEvent", function(self, event, addon)
            if addon == "Blizzard_ChallengesUI" and ChallengesKeystoneFrame then
                AbstractTweaks:HookKeystoneFrame()
                frame:UnregisterEvent("ADDON_LOADED")
            end
        end)
        return
    end
    
    -- Hook the frame's Show event
    self:SecureHookScript(ChallengesKeystoneFrame, "OnShow", function()
        if self.db.profile.autoInsertKey then
            C_Timer.After(0.1, function()
                self:AutoInsertKeystone()
            end)
        end
    end)
    
    self.keystoneHooked = true
end

function AbstractTweaks:AutoInsertKeystone()
    -- Check if we can access the keystone slot
    if not C_ChallengeMode or not C_ChallengeMode.SlotKeystone then return end
    
    -- Don't try if a keystone is already slotted
    local hasKeystone = C_ChallengeMode.HasSlottedKeystone()
    if hasKeystone then return end
    
    -- Use class/subclass instead of hardcoded IDs (works for all expansions)
    local ReagentClass = Enum.ItemClass.Reagent
    local KeystoneClass = Enum.ItemReagentSubclass.Keystone
    
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then
                local itemClass, itemSubClass = select(12, C_Item.GetItemInfo(itemID))
                -- Check if it's a Mythic Keystone by class/subclass
                if itemClass == ReagentClass and itemSubClass == KeystoneClass then
                    C_Container.PickupContainerItem(bag, slot)
                    -- Verify item is on cursor before slotting
                    if C_Cursor.GetCursorItem() then
                        C_ChallengeMode.SlotKeystone()
                        return
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- AUTO DELETE CONFIRMATION
-- ============================================================================

function AbstractTweaks:HookAutoDelete()
    if self.autoDeleteHooked then return end
    
    local module = self
    
    -- Hook the OnShow event of all StaticPopup dialogs
    for i = 1, 4 do
        local dialog = _G["StaticPopup" .. i]
        if dialog then
            dialog:HookScript("OnShow", function(dialogFrame)
                if not module.db or not module.db.profile.autoDelete then return end
                
                local which = dialogFrame.which
                if not which then return end
                
                -- Check if this is a delete confirmation dialog
                if (which == "DELETE_ITEM" or which == "DELETE_GOOD_ITEM" or 
                    which == "DELETE_QUEST_ITEM" or which == "DELETE_GOOD_QUEST_ITEM") then
                    
                    C_Timer.After(0.1, function()
                        if dialogFrame:IsShown() then
                            -- Try multiple ways to find the editBox
                            local editBox = dialogFrame.editBox 
                                or dialogFrame.EditBox 
                                or _G[dialogFrame:GetName() .. "EditBox"]
                                or _G[dialogFrame:GetName() .. "WideEditBox"]
                            
                            -- If not found, search through child frames
                            if not editBox then
                                local children = {dialogFrame:GetChildren()}
                                for _, child in ipairs(children) do
                                    if child.GetObjectType and child:GetObjectType() == "EditBox" then
                                        editBox = child
                                        break
                                    end
                                end
                            end
                            
                            if editBox then
                                editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
                                editBox:HighlightText(0, 0)
                                
                                -- Enable the accept button
                                local button1 = dialogFrame.button1 or _G[dialogFrame:GetName() .. "Button1"]
                                if button1 then
                                    button1:Enable()
                                end
                                
                                -- Clear focus
                                C_Timer.After(0.05, function()
                                    if editBox then
                                        editBox:ClearFocus()
                                    end
                                end)
                            end
                        end
                    end)
                end
            end)
        end
    end
    
    self.autoDeleteHooked = true
end

function AbstractTweaks:HideBagBar()
    if BagsBar then
        BagsBar:SetParent(hiddenFrame)
        BagsBar:Hide()
        BagsBar:SetAlpha(0)
        BagsBar:UnregisterAllEvents()
        
        -- Hook Show to prevent it from appearing
        if not BagsBar.abstractHooked then
            hooksecurefunc(BagsBar, "Show", function()
                if AbstractTweaks.db and AbstractTweaks.db.profile.hideBagBar then
                    BagsBar:Hide()
                end
            end)
            BagsBar.abstractHooked = true
        end
    end
    if MicroButtonAndBagsBar and MicroButtonAndBagsBar.BagsBar then
        MicroButtonAndBagsBar.BagsBar:SetParent(hiddenFrame)
        MicroButtonAndBagsBar.BagsBar:Hide()
        MicroButtonAndBagsBar.BagsBar:SetAlpha(0)
        MicroButtonAndBagsBar.BagsBar:UnregisterAllEvents()
        
        -- Hook Show to prevent it from appearing
        if not MicroButtonAndBagsBar.BagsBar.abstractHooked then
            hooksecurefunc(MicroButtonAndBagsBar.BagsBar, "Show", function()
                if AbstractTweaks.db and AbstractTweaks.db.profile.hideBagBar then
                    MicroButtonAndBagsBar.BagsBar:Hide()
                end
            end)
            MicroButtonAndBagsBar.BagsBar.abstractHooked = true
        end
    end
    
    -- Also try to hide EditMode bag bar
    if EditModeManagerFrame and EditModeManagerFrame.GetSystemFrame then
        local bagBar = EditModeManagerFrame:GetSystemFrame(Enum.EditModeSystem.BagBar)
        if bagBar then
            bagBar:SetParent(hiddenFrame)
            bagBar:Hide()
            bagBar:SetAlpha(0)
            
            -- Hook Show to prevent it from appearing
            if not bagBar.abstractHooked then
                hooksecurefunc(bagBar, "Show", function()
                    if AbstractTweaks.db and AbstractTweaks.db.profile.hideBagBar then
                        bagBar:Hide()
                    end
                end)
                bagBar.abstractHooked = true
            end
        end
    end
end

function AbstractTweaks:ShowBagBar()
    -- Cancel ticker when showing
    if self.bagBarTicker then
        self.bagBarTicker:Cancel()
        self.bagBarTicker = nil
    end
    
    if BagsBar then
        BagsBar:SetParent(UIParent)
        BagsBar:Show()
        BagsBar:SetAlpha(1)
    end
    if MicroButtonAndBagsBar and MicroButtonAndBagsBar.BagsBar then
        MicroButtonAndBagsBar.BagsBar:SetParent(MicroButtonAndBagsBar)
        MicroButtonAndBagsBar.BagsBar:Show()
        MicroButtonAndBagsBar.BagsBar:SetAlpha(1)
    end
    
    -- Also show EditMode bag bar
    if EditModeManagerFrame and EditModeManagerFrame.GetSystemFrame then
        local bagBar = EditModeManagerFrame:GetSystemFrame(Enum.EditModeSystem.BagBar)
        if bagBar then
            bagBar:SetParent(UIParent)
            bagBar:Show()
            bagBar:SetAlpha(1)
        end
    end
end

function AbstractTweaks:ApplyTweaks()
    if self.db.profile.fastLoot then
        -- Set Auto Loot CVars
        SetCVar("autoLootDefault", "1")
        -- Register instant loot event
        self:RegisterEvent("LOOT_READY")
    else
        -- Unregister instant loot event if disabled
        self:UnregisterEvent("LOOT_READY")
    end
    
    -- RevealMap is now called separately from PLAYER_ENTERING_WORLD with proper guards
    -- to prevent excessive map texture loading
    
    if self.db.profile.hideBagBar then
        self:HideBagBar()
        
        -- Set up persistent hooks if not already done
        if not self.bagBarHooked then
            if BagsBar then
                hooksecurefunc(BagsBar, "Show", function()
                    if self.db.profile.hideBagBar then
                        BagsBar:Hide()
                    end
                end)
                hooksecurefunc(BagsBar, "SetParent", function(frame, parent)
                    if self.db.profile.hideBagBar and parent ~= hiddenFrame then
                        C_Timer.After(0, function()
                            frame:SetParent(hiddenFrame)
                        end)
                    end
                end)
            end
            if MicroButtonAndBagsBar and MicroButtonAndBagsBar.BagsBar then
                hooksecurefunc(MicroButtonAndBagsBar.BagsBar, "Show", function()
                    if self.db.profile.hideBagBar then
                        MicroButtonAndBagsBar.BagsBar:Hide()
                    end
                end)
                hooksecurefunc(MicroButtonAndBagsBar.BagsBar, "SetParent", function(frame, parent)
                    if self.db.profile.hideBagBar and parent ~= hiddenFrame then
                        C_Timer.After(0, function()
                            frame:SetParent(hiddenFrame)
                        end)
                    end
                end)
            end
            self.bagBarHooked = true
        end
    else
        self:ShowBagBar()
    end
end

-- ============================================================================
-- MERCHANT FUNCTIONS
-- ============================================================================

function AbstractTweaks:MERCHANT_SHOW()
    if self.db.profile.autoRepair then
        C_Timer.After(0.5, function()
            if self.db.profile.autoRepair then
                self:AutoRepair()
            end
        end)
    end
    
    if self.db.profile.autoSellJunk then
        C_Timer.After(0.5, function()
            if self.db.profile.autoSellJunk then
                self:AutoSellJunk()
            end
        end)
    end
end

function AbstractTweaks:MERCHANT_CLOSED()
    -- Cleanup if needed
end

function AbstractTweaks:AutoRepair()
    if not CanMerchantRepair() then
        return
    end
    
    local repairCost, canRepair = GetRepairAllCost()
    if not canRepair or repairCost <= 0 then
        return
    end
    
    local useGuildBank = self.db.profile.autoRepairGuild and CanGuildBankRepair()
    
    if useGuildBank then
        RepairAllItems(true)
        local guildRepairCost = GetGuildBankWithdrawMoney()
        if guildRepairCost >= repairCost then
            print("|cff00ff00[Abstract Tweaks]|r Repaired all items using guild bank funds for " .. GetCoinTextureString(repairCost))
        else
            print("|cff00ff00[Abstract Tweaks]|r Guild bank repair failed, insufficient funds.")
        end
    else
        if GetMoney() >= repairCost then
            RepairAllItems(false)
            print("|cff00ff00[Abstract Tweaks]|r Repaired all items for " .. GetCoinTextureString(repairCost))
        else
            print("|cffff6b6b[Abstract Tweaks]|r Not enough gold to repair all items. Need " .. GetCoinTextureString(repairCost))
        end
    end
end

function AbstractTweaks:AutoSellJunk()
    if not MerchantFrame:IsShown() then
        return
    end
    
    local totalValue = 0
    local itemsSold = 0
    
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
            if itemInfo then
                local itemLink = itemInfo.hyperlink
                if itemLink then
                    local itemQuality = C_Item.GetItemQualityByID(itemLink)
                    local itemSellPrice = select(11, C_Item.GetItemInfo(itemLink))
                    
                    -- Sell grey (poor quality) items
                    if itemQuality == Enum.ItemQuality.Poor and itemSellPrice and itemSellPrice > 0 then
                        local stackCount = itemInfo.stackCount or 1
                        totalValue = totalValue + (itemSellPrice * stackCount)
                        itemsSold = itemsSold + stackCount
                        C_Container.UseContainerItem(bag, slot)
                    end
                end
            end
        end
    end
    
    if itemsSold > 0 then
        print("|cff00ff00[Abstract Tweaks]|r Sold " .. itemsSold .. " junk item(s) for " .. GetCoinTextureString(totalValue))
    end
end

function AbstractTweaks:GetOptions()
    return {
        type = "group", 
        name = "Tweaks",
        get = function(info) return self.db.profile[info[#info]] end,
        set = function(info, value) self.db.profile[info[#info]] = value end,
        args = {
            fastLoot = { name = "Fast Loot", type = "toggle", order = 1,
                desc = "Enables auto-loot and instant item pickup without loot window delay",
                set = function(_, v) self.db.profile.fastLoot = v; self:ApplyTweaks() end },
            hideGryphons = { name = "Hide Action Bar Art", type = "toggle", order = 2,
                set = function(_, v) 
                    self.db.profile.hideGryphons = v
                    StaticPopup_Show("ABSTRACTTWEAKS_RELOAD_CONFIRM")
                end },
            hideBagBar = { name = "Hide Bag Bar", type = "toggle", order = 3,
                set = function(_, v) self.db.profile.hideBagBar = v; self:ApplyTweaks() end },
            autoRepair = {
                name = "Auto Repair at Vendors",
                desc = "Automatically repair all items when opening a merchant that can repair",
                type = "toggle",
                order = 5,
            },
            autoRepairGuild = {
                name = "Use Guild Bank for Repairs",
                desc = "Use guild bank funds for repairs if available (requires guild repair privileges)",
                type = "toggle",
                order = 6,
                disabled = function() return not self.db.profile.autoRepair end,
            },
            autoSellJunk = {
                name = "Auto Sell Junk at Vendors",
                desc = "Automatically sell all grey (poor quality) items when opening a merchant",
                type = "toggle",
                order = 7,
            },
            revealMap = {
                name = "Reveal Entire Map (Remove Fog of War)",
                desc = "Attempts to hide the fog of war overlay on the world map, revealing unexplored areas. Note: Blizzard has restrictions on this feature - it may not work on all maps or may require opening the map to take effect.",
                type = "toggle",
                order = 8,
                set = function(_, v)
                    self.db.profile.revealMap = v
                    if v then
                        self:HookWorldMapFrame()
                        -- Immediately reveal if map is open
                        if WorldMapFrame and WorldMapFrame:IsShown() then
                            C_Timer.After(0.1, function()
                                self:RevealMap()
                            end)
                        end
                    end
                end,
            },
            autoDelete = {
                name = "Auto-Fill Delete Confirmation",
                desc = "Automatically fills in the DELETE confirmation text and enables the delete button when deleting items",
                type = "toggle",
                order = 9,
                set = function(_, v)
                    self.db.profile.autoDelete = v
                    if v then
                        self:HookAutoDelete()
                    end
                end,
            },
            autoScreenshot = {
                name = "Auto Screenshot on Achievement",
                desc = "Automatically takes a screenshot whenever you earn an achievement",
                type = "toggle",
                order = 10,
                set = function(_, v)
                    self.db.profile.autoScreenshot = v
                    if v then
                        self:RegisterEvent("ACHIEVEMENT_EARNED")
                    else
                        self:UnregisterEvent("ACHIEVEMENT_EARNED")
                    end
                end,
            },
            skipCutscenes = {
                name = "Skip Cutscenes",
                desc = "Automatically skips cinematics and movie cutscenes",
                type = "toggle",
                order = 11,
                set = function(_, v)
                    self.db.profile.skipCutscenes = v
                    if v then
                        self:HookCutscenes()
                    end
                end,
            },
            autoInsertKey = {
                name = "Auto-Insert Mythic Keystone",
                desc = "Automatically places Mythic Keystones from your bags into the keystone font",
                type = "toggle",
                order = 12,
                set = function(_, v)
                    self.db.profile.autoInsertKey = v
                    if v then
                        self:HookKeystoneFrame()
                    end
                end,
            },
            importOverwriteEnabled = { 
                name = "Enable Talent Import Overwrite", 
                desc = "Adds a checkbox to the talent import dialog to overwrite the current loadout instead of creating a new one",
                type = "toggle", 
                order = 13,
                set = function(_, v) 
                    self.db.profile.importOverwriteEnabled = v
                    if v then
                        self:SetupTalentImportWhenReady()
                    else
                        self:DisableTalentImportHook()
                    end
                end 
            },
            questFrameScale = {
                name = "Quest/Dialogue Frame Scale",
                desc = "Adjust the size of Quest and Dialogue/Gossip windows (1.0 = default, 1.5 = 50% larger)",
                type = "range",
                min = 0.5,
                max = 2.0,
                step = 0.05,
                order = 14,
                set = function(_, v)
                    self.db.profile.questFrameScale = v
                    self:ApplyQuestFrameScale()
                end,
            },
            questFrameCustomPosition = {
                name = "Use Custom Quest/Dialogue Position",
                desc = "Enable to set a custom default position for Quest and Dialogue/Gossip windows",
                type = "toggle",
                order = 15,
                set = function(_, v)
                    self.db.profile.questFrameCustomPosition = v
                    self:ApplyQuestFrameScale()
                end,
            },
            questFrameX = {
                name = "Quest/Dialogue Horizontal Position",
                desc = "Horizontal offset from center of screen (negative = left, positive = right)",
                type = "range",
                min = -1200,
                max = 1200,
                step = 1,
                order = 16,
                disabled = function() return not self.db.profile.questFrameCustomPosition end,
                set = function(_, v)
                    self.db.profile.questFrameX = v
                    self:ApplyQuestFrameScale()
                end,
            },
            questFrameY = {
                name = "Quest/Dialogue Vertical Position",
                desc = "Vertical offset from center of screen (negative = down, positive = up)",
                type = "range",
                min = -500,
                max = 500,
                step = 1,
                order = 17,
                disabled = function() return not self.db.profile.questFrameCustomPosition end,
                set = function(_, v)
                    self.db.profile.questFrameY = v
                    self:ApplyQuestFrameScale()
                end,
            },
            groupFinderScale = {
                name = "Group Finder Frame Scale",
                desc = "Adjust the size of the Group Finder (LFG/LFR) window (1.0 = default, 1.5 = 50% larger)",
                type = "range",
                min = 0.5,
                max = 2.0,
                step = 0.05,
                order = 18,
                set = function(_, v)
                    self.db.profile.groupFinderScale = v
                    self:ApplyGroupFinderScale()
                end,
            },
            groupFinderCustomPosition = {
                name = "Use Custom Group Finder Position",
                desc = "Enable to set a custom default position for the Group Finder window",
                type = "toggle",
                order = 19,
                set = function(_, v)
                    self.db.profile.groupFinderCustomPosition = v
                    self:ApplyGroupFinderScale()
                end,
            },
            groupFinderX = {
                name = "Group Finder Horizontal Position",
                desc = "Horizontal offset from center of screen (negative = left, positive = right)",
                type = "range",
                min = -1200,
                max = 1200,
                step = 1,
                order = 20,
                disabled = function() return not self.db.profile.groupFinderCustomPosition end,
                set = function(_, v)
                    self.db.profile.groupFinderX = v
                    self:ApplyGroupFinderScale()
                end,
            },
            groupFinderY = {
                name = "Group Finder Vertical Position",
                desc = "Vertical offset from center of screen (negative = down, positive = up)",
                type = "range",
                min = -500,
                max = 500,
                step = 1,
                order = 21,
                disabled = function() return not self.db.profile.groupFinderCustomPosition end,
                set = function(_, v)
                    self.db.profile.groupFinderY = v
                    self:ApplyGroupFinderScale()
                end,
            },
            recolorDelvePins = {
                name = "Recolor Delve Pins",
                desc = "Makes Delve entrance pins on the world map more visible with a custom color",
                type = "toggle",
                order = 22,
                set = function(_, v)
                    self.db.profile.recolorDelvePins = v
                    if v then
                        self:SetupDelvePinRecoloring()
                    end
                    self:RefreshWorldMap()
                end,
            },
            delvePinColor = {
                name = "Delve Pin Color",
                desc = "Color to use for Delve entrance pins on the world map",
                type = "color",
                order = 23,
                hasAlpha = false,
                disabled = function() return not self.db.profile.recolorDelvePins end,
                get = function()
                    if not self.db or not self.db.profile then
                        return 0.2, 1.0, 0.8, 1.0
                    end
                    local c = self.db.profile.delvePinColor
                    if type(c) ~= "table" then
                        return 0.2, 1.0, 0.8, 1.0
                    end
                    local r = type(c.r) == "number" and c.r or 0.2
                    local g = type(c.g) == "number" and c.g or 1.0
                    local b = type(c.b) == "number" and c.b or 0.8
                    return r, g, b, 1.0
                end,
                set = function(_, r, g, b, a)
                    -- Ensure we have a valid color table
                    if type(self.db.profile.delvePinColor) ~= "table" then
                        self.db.profile.delvePinColor = {}
                    end
                    self.db.profile.delvePinColor.r = r
                    self.db.profile.delvePinColor.g = g
                    self.db.profile.delvePinColor.b = b
                    self:RefreshWorldMap()
                end,
            },
            bountifulDelvePinColor = {
                name = "Bountiful Delve Pin Color",
                desc = "Color to use for Bountiful Delve entrance pins on the world map (delves with a weekly bonus reward)",
                type = "color",
                order = 23.5,
                hasAlpha = false,
                disabled = function() return not self.db.profile.recolorDelvePins end,
                get = function()
                    if not self.db or not self.db.profile then
                        return 1.0, 0.84, 0.0, 1.0
                    end
                    local c = self.db.profile.bountifulDelvePinColor
                    if type(c) ~= "table" then
                        return 1.0, 0.84, 0.0, 1.0
                    end
                    local r = type(c.r) == "number" and c.r or 1.0
                    local g = type(c.g) == "number" and c.g or 0.84
                    local b = type(c.b) == "number" and c.b or 0.0
                    return r, g, b, 1.0
                end,
                set = function(_, r, g, b, a)
                    -- Ensure we have a valid color table
                    if type(self.db.profile.bountifulDelvePinColor) ~= "table" then
                        self.db.profile.bountifulDelvePinColor = {}
                    end
                    self.db.profile.bountifulDelvePinColor.r = r
                    self.db.profile.bountifulDelvePinColor.g = g
                    self.db.profile.bountifulDelvePinColor.b = b
                    self:RefreshWorldMap()
                end,
            },
            oneKeyFishing = {
                name = "One-Key Fishing (Set keybind in Options > Keybindings > Abstract Tweaks)",
                desc = "Enables a single keybind for both casting and hooking fish using Soft Targeting accessibility.\n\n" ..
                       "Instructions:\n" ..
                       "1. Set a keybind in Interface > Keybindings > Abstract Tweaks > One-Key Fishing\n" ..
                       "2. Press once to cast your fishing line\n" ..
                       "3. Hover over the fishing bobber and press again to hook the fish",
                type = "toggle",
                order = 24,
                set = function(_, v)
                    self.db.profile.oneKeyFishing = v
                    if v then
                        self:SetupOneKeyFishing()
                    else
                        self:DisableOneKeyFishing()
                    end
                end,
            },
            customWhisperSound = {
                name = "Custom Whisper Sound",
                desc = "Replace the default whisper notification sound with a custom sound",
                type = "toggle",
                order = 25,
                set = function(_, v)
                    self.db.profile.customWhisperSound = v
                    if v then
                        self:SetupCustomWhisperSound()
                    else
                        self:DisableCustomWhisperSound()
                    end
                    
                    -- Refresh options panel to show/hide whisper sound options
                    if _G.AbstractTweaks_OptionsPanel then
                        _G.AbstractTweaks_OptionsPanel:Refresh()
                    end
                end,
            },
            whisperSoundPreset = {
                name = "Whisper Sound",
                desc = "Select a sound to play when receiving a whisper",
                type = "select",
                order = 26,
                hidden = function() return not self.db.profile.customWhisperSound end,
                values = {
                    default = "Default Whisper (TellMessage)",
                    bell = "Bell",
                    auction = "Auction House Bell",
                    click = "Short Click",
                    quest = "Quest Complete",
                    interface = "Interface Click",
                    raid = "Raid Warning",
                    horn = "War Horn",
                    gong = "Gong",
                    custom = "Custom (Enter Sound ID)",
                },
                sorting = function()
                    return {"default", "bell", "auction", "click", "quest", "interface", "raid", "horn", "gong", "custom"}
                end,
                get = function() return self.db.profile.whisperSoundPreset end,
                set = function(_, v)
                    self.db.profile.whisperSoundPreset = v
                    
                    -- Map preset to File Data ID (from wowhead.com/sounds)
                    local soundMap = {
                        default = 567421,  -- TellMessage (default whisper sound)
                        bell = 565853,     -- Bell Toll Horde
                        auction = 567499,  -- Auction House Bell
                        click = 567451,    -- Player Invite
                        quest = 567439,    -- Quest Complete
                        interface = 567481, -- Interface Sound
                        raid = 567397,     -- Raid Warning
                        horn = 566719,     -- Zeppelin Horn
                        gong = 565564,     -- Gong
                    }
                    
                    if v ~= "custom" and soundMap[v] then
                        self.db.profile.whisperSoundID = soundMap[v]
                        -- Test the sound (all presets now use PlaySoundFile with file data IDs)
                        PlaySoundFile(soundMap[v])
                        print("|cff00ff00[Abstract Tweaks]|r Whisper sound set to: " .. v)
                    end
                    
                    -- Refresh options panel to show/hide Custom Sound ID input
                    if _G.AbstractTweaks_OptionsPanel then
                        _G.AbstractTweaks_OptionsPanel:Refresh()
                    end
                end,
            },
            whisperSoundCustomID = {
                name = "Custom Sound ID",
                desc = "Enter a custom sound file data ID from wowhead.com/sounds\n\nYou can search for sounds on wowhead, preview them, and copy the ID from the URL.\nExample: wowhead.com/sound=567482 → enter 567482\n\nClick 'Test Sound' after entering.",
                type = "input",
                width = "inline",
                order = 27,
                hidden = function() 
                    return not self.db.profile.customWhisperSound or self.db.profile.whisperSoundPreset ~= "custom"
                end,
                get = function() return tostring(self.db.profile.whisperSoundID) end,
                set = function(_, v)
                    local soundID = tonumber(v)
                    if soundID and soundID > 0 then
                        self.db.profile.whisperSoundID = soundID
                        print("|cff00ff00[Abstract Tweaks]|r Custom whisper sound ID set to: " .. soundID)
                    else
                        print("|cffff6b6b[Abstract Tweaks]|r Invalid sound ID. Please enter a positive number.")
                    end
                end,
            },
            whisperSoundTest = {
                name = "Test Sound",
                desc = "Play the currently selected whisper sound",
                type = "execute",
                width = "inline",
                order = 28,
                hidden = function() return not self.db.profile.customWhisperSound end,
                func = function()
                    if self.db.profile.whisperSoundID then
                        -- All sounds now use PlaySoundFile with file data IDs
                        PlaySoundFile(self.db.profile.whisperSoundID)
                        print("|cff00ff00[Abstract Tweaks]|r Playing sound file data ID: " .. self.db.profile.whisperSoundID)
                    end
                end,
            },
        }
    }
end

-- ============================================================================
-- ONE-KEY FISHING FUNCTIONALITY
-- ============================================================================

-- Global function called by the keybinding
function AbstractTweaks_FishingRun()
    local Tweaks = AbstractTweaks:GetModule("Tweaks", true)
    if not Tweaks or not AbstractTweaks.db or not AbstractTweaks.db.profile.oneKeyFishing then return end
    
    -- Don't run in combat or while flying
    if InCombatLockdown() or IsFlying() or IsMounted() then return end
    
    local button = AbstractTweaks:GetFishingButton()
    if not button then return end
    
    -- Always set the fishing spell - event handlers will switch to INTERACTTARGET when fishing starts
    local key1, key2 = GetBindingKey("ABSTRACTTWEAKS_FISHING")
    local fishingSpell = C_Spell.GetSpellName(131474) or "Fishing"
    
    if key1 then
        SetOverrideBindingSpell(button, true, key1, fishingSpell)
    end
    if key2 then
        SetOverrideBindingSpell(button, true, key2, fishingSpell)
    end
end

function AbstractTweaks:GetFishingButton()
    return self.fishingButton
end

function AbstractTweaks:SetupOneKeyFishing()
    -- Create the secure action button if it doesn't exist
    if not self.fishingButton then
        self.fishingButton = CreateFrame("Button", "AbstractTweaks_FishingButton", UIParent, "SecureActionButtonTemplate")
        self.fishingButton:Hide()
        
        -- Register events to manage bindings
        self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
        self:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    end
    
    -- Enable soft targeting (interact with mouseover)
    SetCVar("SoftTargetInteract", "3")
    SetCVar("SoftTargetInteractArc", "2")
    SetCVar("SoftTargetInteractRange", "60")
    
    -- Only show instructions on first enable
    if self.db.profile.oneKeyFishingFirstTime then
        print("Abstract AbstractTweaks: One-Key Fishing enabled. Set a keybind in Interface > Keybindings > Abstract Tweaks > One-Key Fishing")
        print("Abstract AbstractTweaks: Hover over the fishing bobber and press your keybind to hook the fish")
        self.db.profile.oneKeyFishingFirstTime = false
    end
end

function AbstractTweaks:DisableOneKeyFishing()
    if self.fishingButton then
        -- Clear any keybindings
        local key1, key2 = GetBindingKey("ABSTRACTTWEAKS_FISHING")
        if key1 then
            SetBinding(key1, nil)
        end
        if key2 then
            SetBinding(key2, nil)
        end
        SaveBindings(GetCurrentBindingSet())
        
        -- Clear override bindings
        ClearOverrideBindings(self.fishingButton)
        
        self.fishingButton:Hide()
        
        -- Unregister events
        self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_START")
        self:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    end
end

-- Event handlers for fishing state changes
function AbstractTweaks:UNIT_SPELLCAST_CHANNEL_START(event, unit, _, spellID)
    if unit ~= "player" then return end
    
    -- Check if it's a fishing spell (all known fishing spell IDs)
    local FishingIDs = {
        [131474] = true,   -- Live/MoP
        [131490] = true,   -- Cast ID on MoP+ when pole equipped
        [131476] = true,   -- Cast ID on Live, and MoP without pole equipped
        [7620] = true,
        [7731] = true,
        [7732] = true,
        [18248] = true,
        [33095] = true,
        [51294] = true,
        [88868] = true,
        [110410] = true,   -- MoP fishing
        [158743] = true,   -- WoD Fishing
        [377895] = true,   -- Ice Fishing
    }
    
    if not FishingIDs[spellID] or not self.fishingButton then return end
    
    -- Re-apply CVars to ensure soft targeting is active
    SetCVar("SoftTargetInteract", "3")
    SetCVar("SoftTargetInteractArc", "2")
    SetCVar("SoftTargetInteractRange", "60")
    
    -- Switch binding to interact when fishing starts
    if InCombatLockdown() then return end
    
    local key1, key2 = GetBindingKey("ABSTRACTTWEAKS_FISHING")
    if key1 then
        SetOverrideBinding(self.fishingButton, true, key1, "INTERACTTARGET")
    end
    if key2 then
        SetOverrideBinding(self.fishingButton, true, key2, "INTERACTTARGET")
    end
end

function AbstractTweaks:UNIT_SPELLCAST_CHANNEL_STOP(event, unit, _, spellID)
    if unit ~= "player" then return end
    
    -- Check if it's a fishing spell (all known fishing spell IDs)
    local FishingIDs = {
        [131474] = true,
        [131490] = true,
        [131476] = true,
        [7620] = true,
        [7731] = true,
        [7732] = true,
        [18248] = true,
        [33095] = true,
        [51294] = true,
        [88868] = true,
        [110410] = true,
        [158743] = true,
        [377895] = true,
    }
    
    if not FishingIDs[spellID] or not self.fishingButton then return end
    
    -- Clear bindings when fishing stops
    if not InCombatLockdown() then
        ClearOverrideBindings(self.fishingButton)
    end
end

-- ============================================================================
-- CUSTOM WHISPER SOUND FUNCTIONALITY
-- ============================================================================

function AbstractTweaks:SetupCustomWhisperSound()
    if self.whisperSoundHooked then return end
    
    -- Mute the default whisper sound files (using file data IDs)
    MuteSoundFile(567482)  -- TellMessage (main whisper sound)
    MuteSoundFile(567333)  -- BNet whisper sound
    
    -- Register event to listen for incoming whispers
    self:RegisterEvent("CHAT_MSG_WHISPER")
    self:RegisterEvent("CHAT_MSG_BN_WHISPER") -- Battle.net whispers
    
    self.whisperSoundHooked = true
    print("|cff00ff00[Abstract Tweaks]|r Custom whisper sound enabled. Test it by whispering yourself: /w " .. UnitName("player") .. " test")
end

function AbstractTweaks:DisableCustomWhisperSound()
    -- Unmute the default whisper sound files (using file data IDs)
    UnmuteSoundFile(567482)  -- TellMessage (main whisper sound)
    UnmuteSoundFile(567333)  -- BNet whisper sound
    
    -- Unregister the whisper events
    self:UnregisterEvent("CHAT_MSG_WHISPER")
    self:UnregisterEvent("CHAT_MSG_BN_WHISPER")
    print("|cff00ff00[Abstract Tweaks]|r Custom whisper sound disabled.")
end

function AbstractTweaks:CHAT_MSG_WHISPER(event, text, playerName, ...)
    -- Play custom sound when receiving a whisper
    if self.db and self.db.profile.customWhisperSound and self.db.profile.whisperSoundID then
        -- All sounds now use PlaySoundFile with file data IDs
        PlaySoundFile(self.db.profile.whisperSoundID)
    end
end

function AbstractTweaks:CHAT_MSG_BN_WHISPER(event, text, playerName, ...)
    -- Play custom sound when receiving a Battle.net whisper
    if self.db and self.db.profile.customWhisperSound and self.db.profile.whisperSoundID then
        -- All sounds now use PlaySoundFile with file data IDs
        PlaySoundFile(self.db.profile.whisperSoundID)
    end
end

-- ============================================================================
-- TALENT IMPORT OVERWRITE FUNCTIONALITY
-- ============================================================================

function AbstractTweaks:SetupTalentImportWhenReady()
    if ClassTalentLoadoutImportDialog then
        self:SetupTalentImportHook()
        return
    end
    
    -- Try to find and hook the talent frame immediately
    local talentFrame = PlayerSpellsFrame or ClassTalentFrame or PlayerTalentFrame
    
    if talentFrame then
        self:HookTalentFrame(talentFrame)
        
        -- If already visible, start checking now
        if talentFrame:IsVisible() then
            self:HookTalentFrameForPolling(talentFrame)
        end
    else
        -- Frame doesn't exist yet - wait for ADDON_LOADED
        self:RegisterEvent("ADDON_LOADED", function(event, addonName)
            if addonName == "Blizzard_PlayerSpells" or addonName == "Blizzard_ClassTalentUI" then
                C_Timer.After(0.2, function()
                    local frame = PlayerSpellsFrame or ClassTalentFrame or PlayerTalentFrame
                    if frame then
                        self:HookTalentFrame(frame)
                        
                        -- Check if frame is already visible (opened before hook)
                        if frame:IsVisible() then
                            C_Timer.After(0.3, function()
                                if ClassTalentLoadoutImportDialog then
                                    self:SetupTalentImportHook()
                                else
                                    self:HookTalentFrameForPolling(frame)
                                end
                            end)
                        end
                    end
                end)
            end
        end)
    end
end

function AbstractTweaks:HookTalentFrame(talentFrame)
    if self.talentFrameHooked then
        return -- Already hooked
    end
    
    -- Hook the Show event to detect when talent UI opens
    hooksecurefunc(talentFrame, "Show", function()
        if self.importCheckbox then
            return -- Already set up
        end
        
        -- Small delay to let UI fully initialize
        C_Timer.After(0.3, function()
            if ClassTalentLoadoutImportDialog then
                self:SetupTalentImportHook()
            else
                self:HookTalentFrameForPolling(talentFrame)
            end
        end)
    end)
    
    self.talentFrameHooked = true
end

function AbstractTweaks:ScanForTalentFrame()
    -- Scan UIParent children to find talent-related frames
    for _, child in ipairs({UIParent:GetChildren()}) do
        if child.GetName then
            local name = child:GetName()
            if name and (name:match("Talent") or name:match("PlayerSpells")) then
                if child:IsVisible() then
                    self:HookTalentFrameForPolling(child)
                    break
                end
            end
        end
    end
end

function AbstractTweaks:HookTalentFrameForPolling(talentFrame)
    -- Accept passed frame or try to find one
    talentFrame = talentFrame or PlayerSpellsFrame or ClassTalentFrame or PlayerTalentFrame
    
    if not talentFrame then
        return
    end
    
    -- Poll while frame is visible (only while actively open, not continuously)
    local checkCount = 0
    local function CheckForDialog()
        if self.importCheckbox or not talentFrame:IsVisible() then
            return -- Already set up or frame closed
        end
        
        checkCount = checkCount + 1
        
        if ClassTalentLoadoutImportDialog then
            self:SetupTalentImportHook()
            return
        end
        
        -- Continue polling while frame is visible (max 60 seconds)
        if checkCount < 600 then
            C_Timer.After(0.1, CheckForDialog)
        end
    end
    
    CheckForDialog()
end

function AbstractTweaks:SetupTalentImportHook()
    if not ClassTalentLoadoutImportDialog or self.importCheckbox then
        return
    end
    
    local dialog = ClassTalentLoadoutImportDialog
    
    self:CreateImportCheckbox(dialog)
    self:CreateImportAcceptButton(dialog)
    
    if self.importCheckbox then
        self.importCheckbox:SetChecked(false)
        self:OnImportCheckboxClick(self.importCheckbox)
    end
end

function AbstractTweaks:DisableTalentImportHook()
    self:UnhookAll()
    if self.importCheckbox then
        self.importCheckbox:Hide()
        ClassTalentLoadoutImportDialog.NameControl:SetShown(true)
        ClassTalentLoadoutImportDialog:UpdateAcceptButtonEnabledState()
    end
    if self.importAcceptButton then
        self.importAcceptButton:Hide()
    end
end

function AbstractTweaks:CreateImportCheckbox(dialog)
    if self.importCheckbox then
        self.importCheckbox:Show()
        return
    end
    
    local checkbox = CreateFrame("CheckButton", "AbstractTweaks_ImportOverwriteCheckbox", dialog, "UICheckButtonTemplate")
    
    -- Position relative to the dialog itself if NameControl doesn't exist
    if dialog.NameControl then
        checkbox:SetPoint("TOPLEFT", dialog.NameControl, "BOTTOMLEFT", 0, 10)
    else
        checkbox:SetPoint("TOP", dialog, "TOP", 0, -100)
    end
    
    checkbox:SetSize(24, 24)
    checkbox:SetFrameStrata("DIALOG")
    checkbox:SetFrameLevel(dialog:GetFrameLevel() + 10)
    checkbox:SetScript("OnClick", function(cb) self:OnImportCheckboxClick(cb) end)
    checkbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Overwrite Current Loadout")
        GameTooltip:AddLine("If checked, the imported build will overwrite your currently selected loadout.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    checkbox.text = checkbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    checkbox.text:SetPoint("LEFT", checkbox, "RIGHT", 0, 1)
    checkbox.text:SetText("Overwrite Current Loadout")
    checkbox:SetHitRectInsets(-10, -checkbox.text:GetStringWidth(), -5, 0)
    
    checkbox:Show()
    
    self.importCheckbox = checkbox
end

function AbstractTweaks:CreateImportAcceptButton(dialog)
    self:SecureHook(dialog, "OnTextChanged", function() 
        if self.importAcceptButton then
            self.importAcceptButton:SetEnabled(dialog.ImportControl:HasText()) 
        end
    end)
    
    if self.importAcceptButton then
        self.importAcceptButton:Show()
        return
    end
    
    local acceptButton = CreateFrame("Button", nil, dialog, "ClassTalentLoadoutDialogButtonTemplate")
    acceptButton:SetPoint("BOTTOMRIGHT", dialog.ContentArea, "BOTTOM", -5, 0)
    acceptButton:SetText("Import & Overwrite")
    acceptButton.disabledTooltip = "Enter an import string"
    acceptButton:SetScript("OnClick", function()
        local importString = dialog.ImportControl:GetText()
        if self:ImportLoadoutIntoActive(importString) then
            ClassTalentLoadoutImportDialog:OnCancel()
        end
    end)
    
    self.importAcceptButton = acceptButton
end

function AbstractTweaks:OnImportCheckboxClick(checkbox)
    local dialog = checkbox:GetParent()
    dialog.NameControl:SetShown(not checkbox:GetChecked())
    dialog.NameControl:SetText(checkbox:GetChecked() and "" or "")
    
    if self.importAcceptButton then
        self.importAcceptButton:SetShown(checkbox:GetChecked())
    end
    dialog.AcceptButton:SetShown(not checkbox:GetChecked())
    
    if checkbox:GetChecked() and self.importAcceptButton then
        self.importAcceptButton:SetEnabled(dialog.ImportControl:HasText())
    else
        dialog:UpdateAcceptButtonEnabledState()
    end
end

function AbstractTweaks:GetTreeID()
    local configInfo = C_Traits.GetConfigInfo(C_ClassTalents.GetActiveConfigID())
    return configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
end

function AbstractTweaks:ShowImportError(errorString)
    StaticPopup_Show("ABSTRACTTWEAKS_TALENT_IMPORT_ERROR", errorString)
end

function AbstractTweaks:ImportLoadoutIntoActive(importText)
    local importStream = ExportUtil.MakeImportDataStream(importText)
    
    local headerValid, serializationVersion, specID, treeHash = ClassTalentImportExportMixin:ReadLoadoutHeader(importStream)
    
    if not headerValid then
        self:ShowImportError(LOADOUT_ERROR_BAD_STRING)
        return false
    end
    
    if serializationVersion ~= LOADOUT_SERIALIZATION_VERSION then
        self:ShowImportError(LOADOUT_ERROR_SERIALIZATION_VERSION_MISMATCH)
        return false
    end
    
    if specID ~= PlayerUtil.GetCurrentSpecID() then
        self:ShowImportError(LOADOUT_ERROR_WRONG_SPEC)
        return false
    end
    
    local treeID = self:GetTreeID()
    if not ClassTalentImportExportMixin:IsHashEmpty(treeHash) then
        if not ClassTalentImportExportMixin:HashEquals(treeHash, C_Traits.GetTreeHash(treeID)) then
            self:ShowImportError(LOADOUT_ERROR_TREE_CHANGED)
            return false
        end
    end
    
    local loadoutContent = ClassTalentImportExportMixin:ReadLoadoutContent(importStream, treeID)
    local loadoutEntryInfo = self:ConvertToImportLoadoutEntryInfo(treeID, loadoutContent)
    
    return self:DoImport(loadoutEntryInfo)
end

function AbstractTweaks:DoImport(loadoutEntryInfo)
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then
        return false
    end
    
    C_Traits.ResetTree(configID, self:GetTreeID())
    
    while true do
        local removed = self:PurchaseLoadoutEntryInfo(configID, loadoutEntryInfo)
        if removed == 0 then
            break
        end
    end
    
    return true
end

function AbstractTweaks:PurchaseLoadoutEntryInfo(configID, loadoutEntryInfo)
    local removed = 0
    for i, nodeEntry in pairs(loadoutEntryInfo) do
        local success = false
        if nodeEntry.selectionEntryID then
            success = C_Traits.SetSelection(configID, nodeEntry.nodeID, nodeEntry.selectionEntryID)
        elseif nodeEntry.ranksPurchased then
            for rank = 1, nodeEntry.ranksPurchased do
                success = C_Traits.PurchaseRank(configID, nodeEntry.nodeID)
            end
        end
        if success then
            removed = removed + 1
            loadoutEntryInfo[i] = nil
        end
    end
    return removed
end

function AbstractTweaks:ConvertToImportLoadoutEntryInfo(treeID, loadoutContent)
    local results = {}
    local treeNodes = C_Traits.GetTreeNodes(treeID)
    local configID = C_ClassTalents.GetActiveConfigID()
    local count = 1
    
    for i, treeNodeID in ipairs(treeNodes) do
        local indexInfo = loadoutContent[i]
        
        if indexInfo.isNodeSelected then
            local treeNode = C_Traits.GetNodeInfo(configID, treeNodeID)
            local isChoiceNode = treeNode.type == Enum.TraitNodeType.Selection or treeNode.type == Enum.TraitNodeType.SubTreeSelection
            local choiceNodeSelection = indexInfo.isChoiceNode and indexInfo.choiceNodeSelection or nil
            
            if indexInfo.isNodeSelected and isChoiceNode ~= indexInfo.isChoiceNode then
                print(string.format("Import string is corrupt, node type mismatch at nodeID %d. First option will be selected.", treeNodeID))
                choiceNodeSelection = 1
            end
            
            local result = {}
            result.nodeID = treeNode.ID
            result.ranksPurchased = indexInfo.isPartiallyRanked and indexInfo.partialRanksPurchased or treeNode.maxRanks
            result.selectionEntryID = indexInfo.isNodeSelected and isChoiceNode and treeNode.entryIDs[choiceNodeSelection] or nil
            results[count] = result
            count = count + 1
        end
    end
    
    return results
end

-- ============================================================================
-- DELVE PIN RECOLORING
-- ============================================================================

function AbstractTweaks:SetupDelvePinRecoloring()
    if self.delvePinHooked then return end
    
    -- Wait for WorldMapFrame to be available
    if not WorldMapFrame then
        C_Timer.After(1, function() self:SetupDelvePinRecoloring() end)
        return
    end
    
    local module = self
    
    -- Hook WorldMapFrame OnMapChanged
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
        if not module.db or not module.db.profile.recolorDelvePins then return end
        if WorldMapFrame:IsShown() then
            C_Timer.After(0.5, function()
                module:ColorDelvePins()
            end)
        end
    end)
    
    -- Hook quest log updates which can affect map pins
    self:RegisterEvent("LORE_TEXT_UPDATED_CAMPAIGN")
    self:RegisterEvent("QUEST_LOG_UPDATE")
    
    -- Remove the constant 1-second ticker that was causing FPS drops in cities
    -- Only update minimap pins on demand via events and zone changes
    
    self.delvePinHooked = true
    
    -- Apply initial coloring with multiple attempts
    C_Timer.After(0.5, function()
        self:ColorMinimapDelvePins()
    end)
    C_Timer.After(1, function()
        self:ColorDelvePins()
        self:ColorMinimapDelvePins()
    end)
    C_Timer.After(2, function()
        self:ColorMinimapDelvePins()
    end)
end

function AbstractTweaks:ColorDelvePins()
    if not WorldMapFrame then return end
    if not WorldMapFrame:IsShown() then return end
    if not self.db or not self.db.profile.recolorDelvePins then return end
    
    local normalColor = self.db.profile.delvePinColor
    local bountifulColor = self.db.profile.bountifulDelvePinColor
    local r, g, b = normalColor.r, normalColor.g, normalColor.b
    local br, bg, bb = bountifulColor.r, bountifulColor.g, bountifulColor.b
    
    -- Validate normal color values are numbers
    if type(r) ~= "number" then r = 0.2 end
    if type(g) ~= "number" then g = 1.0 end
    if type(b) ~= "number" then b = 0.8 end
    
    -- Validate bountiful color values are numbers
    if type(br) ~= "number" then br = 1.0 end
    if type(bg) ~= "number" then bg = 0.84 end
    if type(bb) ~= "number" then bb = 0.0 end
    
    -- Get all children from the map scroll container
    local pins = {WorldMapFrame.ScrollContainer.Child:GetChildren()}
    
    for _, pin in pairs(pins) do
        if pin.poiInfo and pin.poiInfo.areaPoiID and pin.Texture and pin:IsShown() then
            local atlasName = pin.poiInfo.atlasName or ""
            local poiName = pin.poiInfo.name or ""
            
            -- Check if this is a delve by atlas name or POI name
            local isDelve = false
            if string.find(string.lower(atlasName), "delve") then
                isDelve = true
            elseif string.find(string.lower(poiName), "delve") then
                isDelve = true
            end
            
            -- Apply color to delve pins
            if isDelve then
                -- Check if this is a bountiful delve
                -- Bountiful delves have widget data (widgetSetID) or specific texture indicators
                local isBountiful = false
                
                -- Method 1: Check for widget data (most reliable)
                if pin.poiInfo.widgetSetID and pin.poiInfo.widgetSetID > 0 then
                    isBountiful = true
                end
                
                -- Method 2: Check for tooltip text containing "Bountiful"
                if not isBountiful and pin.poiInfo.description then
                    if string.find(string.lower(pin.poiInfo.description), "bountiful") then
                        isBountiful = true
                    end
                end
                
                -- Method 3: Check for specific atlas variations
                if not isBountiful and atlasName then
                    if string.find(string.lower(atlasName), "bountiful") or 
                       string.find(string.lower(atlasName), "delves%-portal%-icon%-available") then
                        isBountiful = true
                    end
                end
                
                -- Apply appropriate color
                if isBountiful then
                    pin.Texture:SetVertexColor(br, bg, bb)
                else
                    pin.Texture:SetVertexColor(r, g, b)
                end
                pin.Texture:SetDesaturated(false)
            end
        end
    end
end

function AbstractTweaks:LORE_TEXT_UPDATED_CAMPAIGN()
    if self.db and self.db.profile.recolorDelvePins then
        C_Timer.After(0.2, function()
            self:ColorDelvePins()
        end)
    end
end

function AbstractTweaks:QUEST_LOG_UPDATE()
    if self.db and self.db.profile.recolorDelvePins then
        C_Timer.After(0.2, function()
            self:ColorDelvePins()
        end)
    end
end

function AbstractTweaks:ColorMinimapDelvePins()
    if not Minimap then return end
    if not self.db or not self.db.profile.recolorDelvePins then return end
    
    local normalColor = self.db.profile.delvePinColor
    local bountifulColor = self.db.profile.bountifulDelvePinColor
    local r, g, b = normalColor.r, normalColor.g, normalColor.b
    local br, bg, bb = bountifulColor.r, bountifulColor.g, bountifulColor.b
    
    -- Validate normal color values are numbers
    if type(r) ~= "number" then r = 0.2 end
    if type(g) ~= "number" then g = 1.0 end
    if type(b) ~= "number" then b = 0.8 end
    
    -- Validate bountiful color values are numbers
    if type(br) ~= "number" then br = 1.0 end
    if type(bg) ~= "number" then bg = 0.84 end
    if type(bb) ~= "number" then bb = 0.0 end
    
    -- Get current map for player
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    
    local poiInfos = C_AreaPoiInfo.GetAreaPOIForMap(mapID)
    if not poiInfos then return end
    
    -- Build list of delve POI IDs with bountiful status
    local delvePOIs = {}
    local bountifulPOIs = {}
    for _, poiID in ipairs(poiInfos) do
        local poiInfo = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
        if poiInfo then
            local atlasName = poiInfo.atlasName or ""
            local name = poiInfo.name or ""
            
            if string.find(string.lower(atlasName), "delve") or string.find(string.lower(name), "delve") then
                delvePOIs[poiID] = true
                
                -- Check if this is a bountiful delve
                if poiInfo.widgetSetID and poiInfo.widgetSetID > 0 then
                    bountifulPOIs[poiID] = true
                elseif poiInfo.description and string.find(string.lower(poiInfo.description), "bountiful") then
                    bountifulPOIs[poiID] = true
                elseif atlasName and (string.find(string.lower(atlasName), "bountiful") or 
                       string.find(string.lower(atlasName), "delves%-portal%-icon%-available")) then
                    bountifulPOIs[poiID] = true
                end
            end
        end
    end
    
    -- Iterate through all minimap children
    for i = 1, Minimap:GetNumChildren() do
        local child = select(i, Minimap:GetChildren())
        if child then
            local shouldColor = false
            local isBountiful = false
            local poiID = nil
            
            -- Method 1: Check areaPoiID
            if child.areaPoiID and delvePOIs[child.areaPoiID] then
                shouldColor = true
                poiID = child.areaPoiID
                if bountifulPOIs[poiID] then
                    isBountiful = true
                end
            end
            
            -- Method 2: Check texture atlas
            if not shouldColor then
                for j = 1, child:GetNumRegions() do
                    local region = select(j, child:GetRegions())
                    if region and region:GetObjectType() == "Texture" then
                        local atlas = region:GetAtlas()
                        if atlas and string.find(string.lower(atlas), "delve") then
                            shouldColor = true
                            -- Check if atlas indicates bountiful
                            if string.find(string.lower(atlas), "bountiful") or 
                               string.find(string.lower(atlas), "available") then
                                isBountiful = true
                            end
                            break
                        end
                    end
                end
            end
            
            -- Method 3: Check for poiInfo property
            if not shouldColor and child.poiInfo then
                local atlasName = child.poiInfo.atlasName or ""
                local name = child.poiInfo.name or ""
                if string.find(string.lower(atlasName), "delve") or string.find(string.lower(name), "delve") then
                    shouldColor = true
                    -- Check for bountiful indicators
                    if child.poiInfo.widgetSetID and child.poiInfo.widgetSetID > 0 then
                        isBountiful = true
                    elseif child.poiInfo.description and string.find(string.lower(child.poiInfo.description), "bountiful") then
                        isBountiful = true
                    elseif string.find(string.lower(atlasName), "bountiful") or 
                           string.find(string.lower(atlasName), "available") then
                        isBountiful = true
                    end
                end
            end
            
            -- Apply color if this is a delve pin
            if shouldColor then
                local finalR, finalG, finalB = r, g, b
                if isBountiful then
                    finalR, finalG, finalB = br, bg, bb
                end
                
                -- Color all texture regions
                for j = 1, child:GetNumRegions() do
                    local region = select(j, child:GetRegions())
                    if region and region:GetObjectType() == "Texture" then
                        region:SetVertexColor(finalR, finalG, finalB)
                        region:SetDesaturated(false)
                    end
                end
                
                -- Also try specific Texture property
                if child.Texture then
                    child.Texture:SetVertexColor(finalR, finalG, finalB)
                    child.Texture:SetDesaturated(false)
                end
            end
        end
    end
end

function AbstractTweaks:RefreshWorldMap()
    if WorldMapFrame and WorldMapFrame:IsShown() then
        C_Timer.After(0.1, function()
            if WorldMapFrame.RefreshAllDataProviders then
                WorldMapFrame:RefreshAllDataProviders()
            end
            self:ColorDelvePins()
            self:ColorMinimapDelvePins()
        end)
    end
end

