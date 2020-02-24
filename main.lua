HugeLoot = LibStub("AceAddon-3.0"):NewAddon("HugeLoot", "AceConsole-3.0")
local LDB = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub("LibDBIcon-1.0", true)
local channelToMasterLoot = "RAID_WARNING"
local channelToAnnounce = "RAID"
local itemsToNotAnnounce = {
	["Lava Core"] = true,
	["Fiery Core"] = true,
	["Elementium Ore"] = true
}
local announcedGuids = {}
local prioritySet = {}

HugeLoot:RegisterChatCommand("hgl", "ProcessCommand")

-- Register for events
local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_OPENED") -- Fired on user opening a loot panel
frame:SetScript("OnEvent", function(self, event, ...)
	if event == "LOOT_OPENED" then 
		ProcessLoot()
	end
end)

local configOptions = {
	type = "group",
	args = {
		enable = {
			name = "Announce Loot",
			desc = "Whether or not to announce loot to the raid",
			type = "toggle",
			set = function(info,val) HugeLoot.db.profile.doAnnnounce = val end,
			get = function(info) return HugeLoot.db.profile.doAnnnounce end
		},
		minItemQualityToMasterLoot = {
			name = "Master Loot Rarity",
			desc = "Minimum rarity for master looting",
			type = "select",
			values = {
				[2] = "Uncommon",
				[3] = "Rare",
				[4] = "Epic"
			},
			set = function(info,val) HugeLoot.db.profile.minItemQualityToMasterLoot = val end,
			get = function(info) return HugeLoot.db.profile.minItemQualityToMasterLoot end
		},
		minItemQualityToAnnounce = {
			name = "Announce Loot Rarity",
			desc = "Minimum rarity for raid announcement",
			type = "select",
			values = {
				[0] = "Poor",
				[1] = "Common",
				[2] = "Uncommon",
				[3] = "Rare",
				[4] = "Epic"
			},
			set = function(info,val) HugeLoot.db.profile.minItemQualityToAnnounce = val end,
			get = function(info) return HugeLoot.db.profile.minItemQualityToAnnounce end
		},
		lootPriority = {
			name = "Loot Priority",
			desc = "Input loot priority in CSV format",
			type = "input",
			multiline = true,
			set = function(info,val) parseLootPriority(val) end,
		},
	}
}

local defaults = {
	profile = {
		minItemQualityToAnnounce = 3, -- Rare and above
		minItemQualityToMasterLoot = 4, -- Epic and above
		doAnnnounce = true,
		prioritySet = {}
	}
}

function HugeLoot:OnInitialize()
	HugeLoot:Print("initialized")
  	self.db = LibStub("AceDB-3.0"):New("HugeLootDB", defaults)
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
	
	HugeLoot:RefreshConfig()
	
	LibStub("AceConfig-3.0"):RegisterOptionsTable("HugeLoot", configOptions)
  
	if LDB then
		createLDBLauncher()
	end

end

function HugeLoot:ProcessCommand(input)
	if input == "config" then 
		toggleConfigWindow()
	elseif string.sub(input, 1, 8) == "priority" then
		local name = string.sub(input, 10)
		if name ~= nil and prioritySet[name] ~= nil then 
			HugeLoot:Print(name.." | "..prioritySet[name].priority.." | "..prioritySet[name].note)
		else 
			HugeLoot:Print("Item not found")
		end
	elseif input == "help" then 
		HugeLoot:Print("/hgl config -- Opens/closes the config menu")
		HugeLoot:Print("/hgl help -- Prints a list of commands")
		HugeLoot:Print("/hgl priority {itemName} -- Returns the priority information for the given item")
	else
		HugeLoot:Print("Unrecognised command: "..input.." try /hgl help")
	end
end

function HugeLoot:RefreshConfig() 
	minItemQualityToAnnounce = self.db.profile.minItemQualityToAnnounce
	minItemQualityToMasterLoot = self.db.profile.minItemQualityToMasterLoot
	doAnnnounce = self.db.profile.doAnnnounce
	prioritySet = self.db.profile.prioritySet
end

function createLDBLauncher()
	local LDBObj = LDB:NewDataObject("HugeLoot", {
		type = "launcher",
		label = "HugeLoot",
		OnClick = function(_, msg)
			toggleConfigWindow()
		end,
		icon = "Interface\\AddOns\\HugeLoot\\Media\\icon",
		OnTooltipShow = function(tooltip)
			if not tooltip or not tooltip.AddLine then return end
			tooltip:AddLine("HugeLoot")
		end
	})

	if LDBIcon then
		LDBIcon:Register("HugeLoot", LDBObj, HugeLoot.db.profile.minimapIcon)
	end
end

function toggleConfigWindow() 
	local AceConfigDialog = LibStub("AceConfigDialog-3.0")
	if AceConfigDialog.OpenFrames["HugeLoot"] then
		AceConfigDialog:Close("HugeLoot")
	else
		AceConfigDialog:Open("HugeLoot")
	end
end

function parseLootPriority(input) 
	for line in input:gmatch("[^\r\n]+") do
		--HugeLoot:Print(""..line)
		local _, name, priority, note, _ = line:match("%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-)")
		
		--HugeLoot:Print("Name: "..name)
		--HugeLoot:Print("Priority: "..priority)
		--HugeLoot:Print("Note: "..note)
		prioritySet[name] = {
			["priority"] = priority,
			["note"] = note
		}
	end
	HugeLoot.db.profile.prioritySet = prioritySet
	HugeLoot:Print(prioritySet)
end

function ProcessLoot() 
	local masterlooterRaidID = select(3, GetLootMethod())
	local isMasterLooter = masterlooterRaidID ~= nil and UnitName("raid"..masterlooterRaidID) == UnitName("player")
	local guid =  UnitGUID("target")
	
	-- Early exit if not master looter
	if not(isMasterLooter) then return end
	
	-- Build a list of links
	local lootMessage = ""
	local currentLoot = GetLootInfo()
	for i = 1, #currentLoot do
		local _, name, _, _, quality = GetLootSlotInfo(i)
		--local name = select(2, GetLootSlotInfo(i))
		--local quality = select(5, GetLootSlotInfo(i))
		
		if not(itemsToNotAnnounce[name]) and quality >= minItemQualityToAnnounce then
			lootMessage = lootMessage .. GetLootSlotLink(i)
		end
	end
	
	-- Announce the links. Only do so once per GUID
	-- FIXME Character limit could be a problem
	if doAnnnounce and not(announcedGuids[guid]) then
		announcedGuids[guid] = true
		SendChatMessage(lootMessage, channelToAnnounce);
	end
	
	
end

function mySplit(inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                table.insert(t, str)
        end
        return t
end