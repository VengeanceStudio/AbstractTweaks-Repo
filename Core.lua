-- ============================================================================
-- Abstract Tweaks - Core Initialization
-- ============================================================================

local AbstractTweaks = LibStub("AceAddon-3.0"):NewAddon("AbstractTweaks", "AceConsole-3.0", "AceEvent-3.0")

AbstractTweaks.version = "12.0.7.0"

-- Keybinding localization
BINDING_NAME_ABSTRACTTWEAKS_FISHING = "One-Key Fishing"

-- Define reload confirmation dialog
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
    self.db = LibStub("AceDB-3.0"):New("AbstractTweaksDB", defaults, true)
    
    -- Initialize Tile Database
    self:InitializeTileDatabase()
    
    -- Register slash commands
    self:RegisterChatCommand("tweaks", "SlashCommand")
    self:RegisterChatCommand("abstracttweaks", "SlashCommand")
    self:RegisterChatCommand("at", "SlashCommand")
    
    -- Register diagnostic slash commands
    SLASH_ABSTRACTTWEAKS1 = "/tweaksstatus"
    SlashCmdList["ABSTRACTTWEAKS"] = function(msg)
        if msg == "status" or msg == "" then
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
    end
    
    -- Print welcome message
    print("|cff00FF7FAbstract Tweaks|r v" .. self.version .. " loaded. Type |cff00FFFF/tweaks|r for options.")
end

function AbstractTweaks:OnEnable()
    -- Trigger initialization for the Tweaks module (loaded from Tweaks.lua)
    self:SendMessage("ABSTRACTTWEAKS_DB_READY")
    
    -- Set up options panel after a short delay to let module initialize
    C_Timer.After(0.5, function()
        self:SetupOptions()
    end)
end

-- ============================================================================
-- SLASH COMMAND HANDLER
-- ============================================================================
function AbstractTweaks:SlashCommand(input)
    -- Open options panel
    InterfaceOptionsFrame_OpenToCategory("Abstract Tweaks")
    InterfaceOptionsFrame_OpenToCategory("Abstract Tweaks")  -- Called twice due to Blizzard bug
end

-- ============================================================================
-- TILE DATABASE FUNCTIONS
-- ============================================================================
function AbstractTweaks:InitializeTileDatabase()
    -- TileDatabase will be populated from TileDatabase.lua
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
                -- Count comma-separated file IDs
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
    
    -- Get options from the Tweaks module
    local options = {
        name = "Abstract Tweaks",
        type = "group",
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
    
    -- Merge in options from the Tweaks module if available
    if self.GetModule and self:GetModule("Tweaks", true) then
        local tweaksModule = self:GetModule("Tweaks")
        if tweaksModule.GetOptions then
            local tweaksOptions = tweaksModule:GetOptions()
            if tweaksOptions and tweaksOptions.args then
                for k, v in pairs(tweaksOptions.args) do
                    options.args[k] = v
                end
            end
        end
    end
    
    AceConfig:RegisterOptionsTable("AbstractTweaks", options)
    AceConfigDialog:AddToBlizOptions("AbstractTweaks", "Abstract Tweaks")
end
