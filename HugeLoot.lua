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
local ITEM_TO_ALWAYS_MASTER_LOOT = {
	["Onyxia Hide Backpack"] = true
}
local announcedGuids = {}
local prioritySet = {}
local isShowing = false
currentItems = nil
currentItemIndex = nil

-- Register for events
local frame = CreateFrame("Frame")
frame:RegisterEvent("LOOT_OPENED") -- Fired on user opening a loot panel
frame:RegisterEvent("CHAT_MSG_LOOT") -- Fired on someone receiving loot
frame:RegisterEvent("CHAT_MSG_SYSTEM") -- Fired on receiving an system chat message
frame:SetScript("OnEvent", function(self, event, ...)
	if event == "LOOT_OPENED" then 
		processLoot()
	elseif event == "CHAT_MSG_LOOT" then 
		if not(isMasterLooter) then return end
		message, two, _, _, receiver = ...
		if string.find(message, "receive") and receiver ~= nil then
			saveLootedItem(string.match(message, "%[(.*)"), receiver)
		end
	elseif event == "CHAT_MSG_SYSTEM" then
		local text, playerName = ...
		local splitText = mySplit(text, " ")
		-- Only handle valid rolls of 1-100
		if string.find(text, "rolls") and "(1-100)" == splitText[4] and currentItemIndex ~= nil and currentItems[currentItemIndex]["rollMonitor"] ~= nil then
			local newRoll = tonumber(splitText[3])
			local playerName = splitText[1]
			if newRoll > currentItems[currentItemIndex].maxRoll then
				currentItems[currentItemIndex].rolls[newRoll] = playerName
				currentItems[currentItemIndex].maxRoll = newRoll
			elseif newRoll == currentItems[currentItemIndex].maxRoll then
				currentItems[currentItemIndex].rolls[newRoll] = currentItems[currentItemIndex].rolls[newRoll].." + "..playerName
			end
			
			showRoll(currentItems[currentItemIndex])
		end
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

	HugeLoot:RegisterChatCommand("hgl", "ProcessCommand")
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
	elseif string.find(input, "end") then
		endRoll()
		
	elseif input == "help" then 
		HugeLoot:Print("/hgl config -- Opens/closes the config menu")
		HugeLoot:Print("/hgl help -- Prints a list of commands")
		HugeLoot:Print("/hgl priority {itemName} -- Returns the priority information for the given item")
		HugeLoot:Print("/hgl end -- End the current roll")
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

-- Finds the class restriction for then item in the given loot slot, if it exists. Nil otherwise
-- Inspired by https://wowwiki.fandom.com/wiki/UIOBJECT_GameTooltip
local function findClassForSlot(slot) 
	CreateFrame( "GameTooltip", "MyScanningTooltip", nil, "GameTooltipTemplate" ); -- Tooltip name cannot be nil
	MyScanningTooltip:SetOwner( WorldFrame, "ANCHOR_NONE" );
	-- Allow tooltip SetX() methods to dynamically add new lines based on these
	MyScanningTooltip:AddFontStrings(
		MyScanningTooltip:CreateFontString( "$parentTextLeft1", nil, "GameTooltipText" ),
		MyScanningTooltip:CreateFontString( "$parentTextRight1", nil, "GameTooltipText" ) 
	);
	
	MyScanningTooltip:ClearLines() 
	MyScanningTooltip:SetLootItem(slot)
	
	local class = nil
	for i = 1, MyScanningTooltip:NumLines() do
		local mytext=_G["MyScanningTooltipTextLeft"..i] 
		if mytext ~= nil then 
			local status, text = pcall(function() return mytext:GetText() end)
			if status and string.find(text, "Classes") then 
				class = mySplit(text, " ")[2]
			end
		end
	end
	
	MyScanningTooltip:Hide()
	
	return class
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
	local currentLootInfo = GetLootInfo()
	local masterLootCandidates = {}
	local numItemsToMasterLoot = 0
	for i = 1, #currentLootInfo do
		local icon, name, _, _, quality = GetLootSlotInfo(i)
		local link = GetLootSlotLink(i)
		HugeLoot:Print("Processing item "..i.." with name "..name)
		
		if not(ITEMS_TO_NOT_ANNOUNCE[name]) and quality >= minItemQualityToAnnounce and link ~= nil then
			lootMessage = lootMessage..link
		end
		
		if quality >= minItemQualityToMasterLoot or ITEM_TO_ALWAYS_MASTER_LOOT[name] ~= nil then 
			numItemsToMasterLoot = numItemsToMasterLoot + 1
			local priorityEntry = prioritySet[name]
			
			--HugeLoot:Print("Adding entry")
			
			--FIXME duplicates
			if priorityEntry ~= nil then 					
				masterLootCandidates[numItemsToMasterLoot] = {
					["name"] = name,
					["link"] = link,
					["priority"] = priorityEntry.priority.." > Roll",
					["note"] = priorityEntry.note,
					["icon"] = icon
				}
			else
				local class = findClassForSlot(i)
				if class == "Warrior" then 
					class = "Warr Tank > Fury"
				end
				if class ~= nil then 
					masterLootCandidates[numItemsToMasterLoot] = {
						["name"] = name,
						["link"] = link,
						["priority"] = class,
						["note"] = "",
						["icon"] = icon
					}
				else 
					masterLootCandidates[numItemsToMasterLoot] = {
						["name"] = name,
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
	-- FIXME Character limit is a problem
	if doAnnnounce and guid ~= nil and not(announcedGuids[guid]) and string.len(lootMessage) ~= 0 then
		announcedGuids[guid] = true
		SendChatMessage(lootMessage, CHANNEL_TO_ANNOUNCE);
	end
	
	if numItemsToMasterLoot >= 1 then 
		currentItems = masterLootCandidates
		showLootFrame()
	end
end

function showRoll(item) 
	if item.rollMonitor ~= nil then 
		if item.maxRoll ~= 0 then 
			item.rollMonitor:SetText(item.rolls[item.maxRoll].." - "..item.maxRoll)
		else 
			item.rollMonitor:SetText("None")
		end
		
		local setColor = false
		for i = 1, GetNumGroupMembers() do 
			local unitId = UnitId(raid..i)
			if UnitName(unitId) == item.roll[item.maxRoll] then
				local class = UnitClass(unitId)
				local color = RAID_CLASS_COLORS[class]
				
				HugeLoot:Print(color)
				for k, v in pairs(color) do
					HugeLoot:Print("k: "..key.." | v: "..v)
				end
				
				local r, g, b = GetClassColor(class)
				
				setColor = true
				item.rollMonitor:SetColor(r, g, b)
			end
		end
		
		--Default color to white if no class color found
		--if not(setColor) then item.rollMonitor:SetColor(255, 255, 255) end
	end
end

function saveLootedItem(item, name) 
	local itemHistoryDB = HugeLoot.db.profile.lootHistory
	if itemHistoryDB == nil then
		itemHistoryDB = {}
	end
	
	local dbEntry = {
		["item"] = item,
		["name"] = name
	}
	
	if currentItems ~= nil then 
		for i = 1, #currentItems do
			local inList = currentItems[i]
			if string.find(item, inList.name) and inList.rolls[inList.maxRoll] == name then
				dbEntry["details"] = inList
				break
			end
		end
	end
	
	itemHistoryDB[date("%y-%m-%d %H:%M:%S")] = dbEntry
	HugeLoot.db.profile.lootHistory = itemHistoryDB
end

function showLootFrame() 	
	if isShowing or currentItems == nil then
		return
	else 
		isShowing = true
	end
	
	local baseContainer = AceGUI:Create("Frame")
	baseContainer:SetTitle("Huge Loot")
	local lootName = UnitName("target")
	if lootName == nil then 
		lootName = "Unknown"
	end
	baseContainer:SetStatusText("Currently looting "..lootName)
	baseContainer:SetCallback("OnClose", function(widget) 
		AceGUI:Release(widget) 
		isShowing = false
		currentItemIndex = nil
		currentItems = nil
	end)
	baseContainer:SetLayout("Fill")
	
	local lootFrame = AceGUI:Create("ScrollFrame")
	lootFrame:SetLayout("List")
	baseContainer:AddChild(lootFrame)
	
	-- For each item, add a label, roll manipulator buttons, roll monitor, then a button for each step in prio, followed by the note.
	for i = 1, #currentItems do
		local item = currentItems[i]
		if item.priority == nil or string.len(item.priority) == 0 then 
			item.priority = DEFAULT_PRIORITY
		end
	
		local itemGroup = AceGUI:Create("SimpleGroup") 
		itemGroup:SetFullWidth(true)
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
		
		local assignButton = AceGUI:Create("Button") 
		assignButton:SetText("A")
		assignButton:SetWidth(25)
		assignButton:SetCallback("OnClick", function() 
			itemGroup:Disable()
		end)
		itemGroup:AddChild(assignButton)
				
		local removeRollerButton = AceGUI:Create("Button") 
		removeRollerButton:SetText("X")
		removeRollerButton:SetWidth(25)
		removeRollerButton:SetCallback("OnClick", function() 
			item.rolls[item.maxRoll] = nil
			local newMax = 0
			for roll, name in pairs(item.rolls) do 
				if roll > newMax and name ~= nil then
					newMax = roll
				end
			end
			item.maxRoll = newMax
			showRoll(item)
		end)
		itemGroup:AddChild(removeRollerButton)
		
		local rollMonitor = AceGUI:Create("InteractiveLabel") 
		rollMonitor:SetText("None")
		rollMonitor:SetWidth(120)
		itemGroup:AddChild(rollMonitor)
		
		item.rollMonitor = rollMonitor
		item.rolls = {}
		item.maxRoll = 0
				
		local splitPriority = mySplit(item.priority, ">")
		for j = 1, #splitPriority do
			local line = trim(splitPriority[j])
			
			local button = AceGUI:Create("Button") 
			button:SetText(line)
			button:SetWidth(135)
			button:SetCallback("OnClick", function() 
				currentItemIndex = i				
				SendChatMessage(item.link.." "..line, CHANNEL_TO_MASTER_LOOT)
			end)
			itemGroup:AddChild(button)
		end

		local itemNote = AceGUI:Create("Label") 
		itemNote:SetText(item.note)
		itemGroup:AddChild(itemNote)
		
		local lootHistoryButton = AceGUI:Create("Button") 
		lootHistoryButton:SetText("LT")
		lootHistoryButton:SetWidth(50)
		lootHistoryButton:SetCallback("OnClick", function() 
			if item.maxRoll ~= nil then 
				showLootHistory(item.rolls[item.maxRoll])
			end
		end)
		itemGroup:AddChild(lootHistoryButton)
	end
	
	local endButton = AceGUI:Create("Button") 
	endButton:SetText("End Roll")
	endButton:SetWidth(100)
	endButton:SetCallback("OnClick", function() 
		endRoll()
	end)
	lootFrame:AddChild(endButton)
end

function endRoll() 
	local item = nil
	if currentItemIndex ~= nil or currentItems ~= nil then item = currentItems[currentItemIndex] end
	if item == nil then item = { ["link"] = ""} end
	--SendChatMessage("/dbm broadcast timer 10 test")
	local elapsed = 10
	C_Timer.NewTicker(1, function() 
		elapsed = elapsed - 1
		if elapsed == 0 then
			SendChatMessage("Rolls for "..item.link.." have closed!", CHANNEL_TO_MASTER_LOOT)
		elseif elapsed == 9 then
			SendChatMessage("Roll for "..item.link.." ends in 10 seconds", CHANNEL_TO_MASTER_LOOT)
		elseif elapsed <= 3 then
			SendChatMessage("Roll for "..item.link.." ends in "..elapsed.." seconds", CHANNEL_TO_MASTER_LOOT)
		end
	end, 10)
end

function showLootHistory(player) 
	if player == nil then return end
	
	local playerLoot = getLootForPlayer(player)
	
	local baseContainer = AceGUI:Create("Frame")
	baseContainer:SetTitle("Loot for "..player)

	for dateTime, item in pairs(playerLoot) do
		local itemLabel = AceGUI:Create("Label") 
		itemLabel:SetText(dateTime)
		itemLabel:SetWidth(130)
		itemGroup:AddChild(itemLabel)
	
		local itemIcon = AceGUI:Create("Icon") 
		itemIcon:SetWidth(25)
		itemIcon:SetImageSize(20, 20)
		if item.details.icon ~= nil then 
			itemIcon:SetImage(item.icon)
		end
		itemGroup:AddChild(itemIcon)
		
		local itemLabel = AceGUI:Create("Label") 
		itemLabel:SetWidth(130)
		if item.details.link ~= nil then
			itemLabel:SetText(item.link)
		else
			itemLabel:SetText(item.item)
		end
		itemGroup:AddChild(itemLabel)
	end
end

function getLootForPlayer(player) 
	local itemHistoryDB = HugeLoot.db.profile.lootHistory
	if itemHistoryDB == nil then return nil end
	
	
	local items = {}
	for dateTime, item in pairs(itemHistoryDB) do 
		if item.name == player then
			items[dateTime] = item
		end
	end
	
	return items
end

function processRoll(playerName, rollAmount) 
	HugeLoot:Print("Received roll from "..playerName.." for value "..rollAmount)
end

-- Taken from http://lua-users.org/wiki/StringTrim
function trim(s)
   return s:match "^%s*(.-)%s*$"
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
