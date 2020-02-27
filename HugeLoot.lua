HugeLoot = LibStub("AceAddon-3.0"):NewAddon("HugeLoot", "AceConsole-3.0")
local LDB = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub("LibDBIcon-1.0", true)
local AceGUI = LibStub("AceGUI-3.0")

local CHANNEL_TO_MASTER_LOOT = "RAID_WARNING"
local CHANNEL_TO_ANNOUNCE = "RAID"
local DEFAULT_PRIORITY = "MS > OS"
local ITEMS_TO_NOT_ANNOUNCE = {
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
		processLoot()
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
				[1] = "Common", -- TODO remove
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
	local itemsParsed = 0
	for line in input:gmatch("[^\r\n]+") do
		local _, name, priority, note, _ = line:match("%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-)")

		prioritySet[name] = {
			["priority"] = priority,
			["note"] = note
		}
		itemsParsed = itemsParsed + 1
	end
	HugeLoot.db.profile.prioritySet = prioritySet
	HugeLoot:Print("Successfully added "..itemsParsed.." items to the priority database")
end

function processLoot() 
	--HugeLoot:Print("Processing loot")
	local masterlooterRaidID = select(3, GetLootMethod())
	local isMasterLooter = masterlooterRaidID ~= nil and UnitName("raid"..masterlooterRaidID) == UnitName("player")
	local guid =  UnitGUID("target")
	
	-- Early exit if not master looter
	if not(isMasterLooter) then return end
	
	-- Build a list of links
	local lootMessage = ""
	local currentLoot = GetLootInfo()
	local masterLootCandidates = {}
	local numItemsToMasterLoot = 0
	for i = 1, #currentLoot do
		local icon, name, _, _, quality = GetLootSlotInfo(i)
		local link = GetLootSlotLink(i)
		--HugeLoot:Print("Processing item "..i.." with name "..name)
		
		if not(ITEMS_TO_NOT_ANNOUNCE[name]) and quality >= minItemQualityToAnnounce and link ~= nil then
			lootMessage = lootMessage..link
		end
		
		if quality >= minItemQualityToMasterLoot then 
			numItemsToMasterLoot = numItemsToMasterLoot + 1
			local priorityEntry = prioritySet[name]
			
			if priorityEntry ~= nil then 					
				masterLootCandidates[name] = {
					["link"] = link,
					["priority"] = priorityEntry.priority.." > Open Roll",
					["note"] = priorityEntry.note,
					["icon"] = icon
				}
			else
				HugeLoot:Print("Stats for "..name)
				local specTable = GetItemStats(link)
				for k, v in pairs(specTable) do
					HugeLoot:Print("Key: "..k.." | Value: "..v)
				end
				if #specTable >= 1 then 
					masterLootCandidates[name] = {
						["link"] = link,
						["priority"] = specTable[0],
						["note"] = "",
						["icon"] = icon
					}
				else 
					masterLootCandidates[name] = {
						["link"] = link,
						["priority"] = DEFAULT_PRIORITY,
						["note"] = "",
						["icon"] = icon
					}
				end
			end
		end
	end
	
	-- Announce the links. Only do so once per GUID
	-- FIXME Character limit could be a problem
	if doAnnnounce and guid ~= nil and not(announcedGuids[guid]) and string.len(lootMessage) ~= 0 then
		announcedGuids[guid] = true
		SendChatMessage(lootMessage, CHANNEL_TO_ANNOUNCE);
	end
	
	if numItemsToMasterLoot >= 1 then 
		showLootFrame(masterLootCandidates)
	end
end

function showLootFrame(loot) 
	--HugeLoot:Print("Showing loot")
	local currentItem = {}	
	
	local baseContainer = AceGUI:Create("Frame")
	baseContainer:SetTitle("Huge Loot")
	local lootName = UnitName("target")
	if lootName == nil then 
		lootName = "Unknown"
	end
	baseContainer:SetStatusText("Currently looting "..lootName)
	baseContainer:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)
	baseContainer:SetLayout("Fill")

	--baseContainer:SetAutoAdjustHeight(true)
	
	local lootFrame = AceGUI:Create("ScrollFrame")
	lootFrame:SetLayout("List")
	baseContainer:AddChild(lootFrame)

	local rollMonitorFrame = CreateFrame("Frame")
	rollMonitorFrame:RegisterEvent("CHAT_MSG_SYSTEM") -- Fired on receiving an emote chat message
	rollMonitorFrame:SetScript("OnEvent", function(self, event, ...)
		if event == "CHAT_MSG_SYSTEM" then
			local text, playerName = ...
			local splitText = mySplit(text, " ")
			-- Only handle valid rolls of 1-100
			if "rolls" == splitText[2] and "(1-100)" == splitText[4] and currentItem["rollMonitor"] ~= nil then
				local newRoll = tonumber(splitText[3])
				local playerName = splitText[1]
				if newRoll > currentItem.maxRoll then
					currentItem.rolls[newRoll] = playerName
					currentItem.maxRoll = newRoll
				elseif newRoll == currentItem.maxRoll then
					currentItem.rolls[newRoll] = currentItem.rolls[newRoll].." + "..playerName
				end
				
				currentItem.rollMonitor:SetText(currentItem.rolls[newRoll].." - "..newRoll)
			end
		end
	end)
	
	-- For each item, add a label, then a button for each step in prio, followed by the note.
	for name, item in pairs(loot) do 
		if item.priority == nil or string.len(item.priority) == 0 then 
			item.priority = DEFAULT_PRIORITY
		end
	
		local itemGroup = AceGUI:Create("SimpleGroup") 
		itemGroup:SetFullWidth(true)
		--itemGroup:SetHeight(100)
		itemGroup:SetLayout("Flow")
		
		lootFrame:AddChild(itemGroup)
		local itemIcon = AceGUI:Create("Icon") 
		itemIcon:SetWidth(25)
		itemIcon:SetImageSize(20, 20)
		itemIcon:SetImage(item.icon)
		itemGroup:AddChild(itemIcon)
		
		local itemLabel = AceGUI:Create("Label") 
		itemLabel:SetText(item.link)
		itemLabel:SetWidth(130)
		itemGroup:AddChild(itemLabel)
		
		local rollMonitor = AceGUI:Create("InteractiveLabel") 
		rollMonitor:SetText("None")
		rollMonitor:SetWidth(120)
		itemGroup:AddChild(rollMonitor)
		
		local splitPriority = mySplit(item.priority, ">")
		for i = 1, #splitPriority do
			local line = splitPriority[i]
			
			local button = AceGUI:Create("Button") 
			button:SetText(line)
			button:SetWidth(135)
			button:SetCallback("OnClick", function() 
				currentItem = item
				currentItem.rollMonitor = rollMonitor
				currentItem.rolls = {}
				currentItem.maxRoll = 0
				SendChatMessage(item.link..line, CHANNEL_TO_MASTER_LOOT);
			end)
			itemGroup:AddChild(button)
		end
		

		local itemNote = AceGUI:Create("Label") 
		itemNote:SetText(item.note)
		itemGroup:AddChild(itemNote)
	end
end

function processRoll(playerName, rollAmount) 
	HugeLoot:Print("Received roll from "..playerName.." for value "..rollAmount)
end

-- Blindly copied from stack overflow, review if it works poorly
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