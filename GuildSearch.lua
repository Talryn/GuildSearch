GuildSearch = LibStub("AceAddon-3.0"):NewAddon("GuildSearch", "AceConsole-3.0", "AceEvent-3.0")

local L = LibStub("AceLocale-3.0"):GetLocale("GuildSearch", true)

local LDB = LibStub("LibDataBroker-1.1")
local icon = LibStub("LibDBIcon-1.0")

local GREEN = "|cff00ff00"
local YELLOW = "|cffffff00"
local BLUE = "|cff0198e1"
local ORANGE = "|cffff9933"
local WHITE = "|cffffffff"

local WHITE_VALUE = {
    ["r"] = 1.0,
	["g"] = 1.0,
	["b"] = 1.0,
	["a"] = 1.0
}

local defaults = {
	profile = {
		minimap = {
			hide = true,
		},
		verbose = true,
		searchNames = true,
		searchNotes = true,
		searchOfficerNotes = true,
		searchRank = false,
		searchClass = false
	}
}

local options = {
    name = "Guild Search",
    handler = GuildSearch,
    type = 'group',
    args = {
		displayheader = {
			order = 0,
			type = "header",
			name = "General Options",
		},
	    minimap = {
            name = L["Minimap Button"],
            desc = L["Toggle the minimap button"],
            type = "toggle",
            set = "SetMinimapButton",
            get = "GetMinimapButton",
			order = 10
        },
	    verbose = {
            name = L["Verbose"],
            desc = L["Toggles the display of informational messages"],
            type = "toggle",
            set = "SetVerbose",
            get = "GetVerbose",
			order = 15
        },
		displayheader2 = {
			order = 20,
			type = "header",
			name = L["Search Options"],
		},
        searchNames = {
            name = L["Search Names"],
            desc = L["When checked, searches include the character name."],
            type = "toggle",
            set = "SetSearchNames",
            get = "GetSearchNames",
			order = 30
        },
        searchNotes = {
            name = L["Search Notes"],
            desc = L["When checked, searches include the notes."],
            type = "toggle",
            set = "SetSearchNotes",
            get = "GetSearchNotes",
			order = 40
        },
        searchOfficerNotes = {
            name = L["Search Officer Notes"],
            desc = L["When checked, searches include the officer notes."],
            type = "toggle",
            set = "SetSearchOfficerNotes",
            get = "GetSearchOfficerNotes",
			order = 50
        },
        searchRank = {
            name = L["Search Rank"],
            desc = L["When checked, searches include the guild ranks."],
            type = "toggle",
            set = "SetSearchRank",
            get = "GetSearchRank",
			order = 60
        },
        searchClass = {
            name = L["Search Class"],
            desc = L["When checked, searches include the character's class."],
            type = "toggle",
            set = "SetSearchClass",
            get = "GetSearchClass",
			order = 70
        }
    }
}

local guildSearchLDB = nil
local searchTerm = nil
local guildFrame = nil
local guildData = {}

function GuildSearch:OnInitialize()
    -- Called when the addon is loaded
    self.db = LibStub("AceDB-3.0"):New("GuildSearchDB", defaults, "Default")

    -- Register the options table
    LibStub("AceConfig-3.0"):RegisterOptionsTable("GuildSearch", options)
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions(
	    "GuildSearch", "Guild Search")

	-- Create the guild frame
	guildFrame = self:CreateGuildFrame()

	-- Register the command line option
	self:RegisterChatCommand("gsearch", "GuildSearchHandler")	

	-- Create the LDB launcher
	guildSearchLDB = LDB:NewDataObject("GuildSearch",{
		type = "launcher",
		icon = "Interface\\Icons\\INV_Scroll_03.blp",
		OnClick = function(clickedframe, button)
			if self:IsWindowVisible() then
				self:HideGuildWindow()
			else
				self:GuildSearchHandler("")
			end
		end,
		OnTooltipShow = function(tooltip)
			if tooltip and tooltip.AddLine then
				tooltip:AddLine(GREEN .. "Guild Search")
				tooltip:AddLine(YELLOW .. L["Left click"] .. " " .. WHITE
					.. L["to open/close the window"])
			end
		end
	})
	icon:Register("GuildSearchLDB", guildSearchLDB, self.db.profile.minimap)
end

function GuildSearch:GuildSearchHandler(input)
	searchTerm = string.lower(input)
	
	-- Show the guild frame
	guildFrame:Show()

	-- Need to turn on offline display to be able to seach them
	SetGuildRosterShowOffline(true)

	-- Update the guild roster
	if IsInGuild() then
		GuildRoster()
	end
end

function GuildSearch:OnEnable()
    -- Called when the addon is enabled

	-- Register to get the update event
	self:RegisterEvent("GUILD_ROSTER_UPDATE")
end

function GuildSearch:OnDisable()
    -- Called when the addon is disabled
	self:UnregisterEvent("GUILD_ROSTER_UPDATE")
end

function GuildSearch:PopulateGuildData()
	wipe(guildData)
	
	if IsInGuild() then
		local numMembers = GetNumGuildMembers()
		for index = 1, numMembers do
			local name, rank, rankIndex, level, class, zone, note, 
				officernote, online, status, classFileName = GetGuildRosterInfo(index)
				table.insert(guildData, {name,level,note,officernote,rank,classFileName})
		end
	end

	-- Update the guild data now
	if guildFrame then
		guildFrame.table:SetData(guildData, true)
	end
end

function GuildSearch:GUILD_ROSTER_UPDATE()
	-- The guild roster data is now available
	self:PopulateGuildData()
end

function GuildSearch:CreateGuildFrame()
	local guildwindow = CreateFrame("Frame", "GuildSearchWindow", UIParent)
	guildwindow:SetFrameStrata("DIALOG")
	guildwindow:SetToplevel(true)
	guildwindow:SetWidth(700)
	guildwindow:SetHeight(450)
	guildwindow:SetPoint("CENTER", UIParent)
	guildwindow:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})

	local ScrollingTable = LibStub("ScrollingTable");

	local cols = {}
	cols[1] = {
		["name"] = L["Name"],
		["width"] = 100,
		["align"] = "LEFT",
		["color"] = function(data, cols, realrow, column, table)
			local className = string.upper(data[realrow][6])
			if className == "DEATH KNIGHT" then
				className = "DEATHKNIGHT"
			end
			return RAID_CLASS_COLORS[className] or WHITE_VALUE
		end,
--		["color"] = {
--			["r"] = 1.0,
--			["g"] = 1.0,
--			["b"] = 1.0,
--			["a"] = 1.0
--		},
		["colorargs"] = nil,
		["bgcolor"] = {
			["r"] = 0.0,
			["g"] = 0.0,
			["b"] = 0.0,
			["a"] = 1.0
		},
		["defaultsort"] = "dsc",
		["sort"] = "dsc",
		["DoCellUpdate"] = nil,
	}
	cols[2] = {
		["name"] = L["Level"],
		["width"] = 40,
		["align"] = "LEFT",
		["color"] = {
			["r"] = 1.0,
			["g"] = 1.0,
			["b"] = 1.0,
			["a"] = 1.0
		},
		["colorargs"] = nil,
		["bgcolor"] = {
			["r"] = 0.0,
			["g"] = 0.0,
			["b"] = 0.0,
			["a"] = 1.0
		},
		["DoCellUpdate"] = nil,
	}
	cols[3] = {
		["name"] = L["Note"],
		["width"] = 220,
		["align"] = "LEFT",
		["color"] = {
			["r"] = 1.0,
			["g"] = 1.0,
			["b"] = 1.0,
			["a"] = 1.0
		},
		["colorargs"] = nil,
		["bgcolor"] = {
			["r"] = 0.0,
			["g"] = 0.0,
			["b"] = 0.0,
			["a"] = 1.0
		},
		["DoCellUpdate"] = nil,
	}
	cols[4] = {
		["name"] = L["Officer Note"],
		["width"] = 200,
		["align"] = "LEFT",
		["color"] = {
			["r"] = 1.0,
			["g"] = 1.0,
			["b"] = 1.0,
			["a"] = 1.0
		},
		["colorargs"] = nil,
		["bgcolor"] = {
			["r"] = 0.0,
			["g"] = 0.0,
			["b"] = 0.0,
			["a"] = 1.0
		},
		["DoCellUpdate"] = nil,
	}
	cols[5] = {
		["name"] = L["Rank"],
		["width"] = 60,
		["align"] = "LEFT",
		["color"] = {
			["r"] = 1.0,
			["g"] = 1.0,
			["b"] = 1.0,
			["a"] = 1.0
		},
		["colorargs"] = nil,
		["bgcolor"] = {
			["r"] = 0.0,
			["g"] = 0.0,
			["b"] = 0.0,
			["a"] = 1.0
		},
		["DoCellUpdate"] = nil,
	}

	local table = ScrollingTable:CreateST(cols, 19, nil, nil, guildwindow);

	local headertext = guildwindow:CreateFontString("GS_Main_HeaderText", guildwindow, "GameFontNormalLarge")
	headertext:SetPoint("TOP", guildwindow, "TOP", 0, -20)
	headertext:SetText(L["Guild Search"])

	local searchterm = CreateFrame("EditBox", nil, guildwindow, "InputBoxTemplate")
	searchterm:SetFontObject(ChatFontNormal)
	searchterm:SetWidth(300)
	searchterm:SetHeight(35)
	searchterm:SetPoint("TOPLEFT", guildwindow, "TOPLEFT", 30, -50)
	searchterm:SetScript("OnShow", function() this:SetFocus() end)
	searchterm:SetScript("OnEnterPressed", function() table:SortData() end)
	searchterm:SetScript("OnEscapePressed", function() this:SetText(""); this:GetParent():Hide(); end)

	table.frame:SetPoint("TOP", searchterm, "BOTTOM", 0, -20)
	table.frame:SetPoint("LEFT", guildwindow, "LEFT", 25, 0)

	local searchbutton = CreateFrame("Button", nil, guildwindow, "UIPanelButtonTemplate")
	searchbutton:SetText(L["Search"])
	searchbutton:SetWidth(100)
	searchbutton:SetHeight(20)
	searchbutton:SetPoint("LEFT", searchterm, "RIGHT", 10, 0)
	searchbutton:SetScript("OnClick", function() table:SortData() end)

	local clearbutton = CreateFrame("Button", nil, guildwindow, "UIPanelButtonTemplate")
	clearbutton:SetText(L["Clear"])
	clearbutton:SetWidth(100)
	clearbutton:SetHeight(20)
	clearbutton:SetPoint("LEFT", searchbutton, "RIGHT", 10, 0)
	clearbutton:SetScript("OnClick", function() searchterm:SetText(""); table:SortData(); end)

	local closebutton = CreateFrame("Button", nil, guildwindow, "UIPanelButtonTemplate")
	closebutton:SetText(L["Close"])
	closebutton:SetWidth(90)
	closebutton:SetHeight(20)
	closebutton:SetPoint("BOTTOM", guildwindow, "BOTTOM", 0, 20)
	closebutton:SetScript("OnClick", function() this:GetParent():Hide(); end)

	guildwindow.table = table
	guildwindow.searchterm = searchterm
	
	table:SetFilter(
		function(self, row)
			local searchterm = searchterm:GetText()
			if searchterm and #searchterm > 0 then
				term = string.lower(searchterm)
				if (GuildSearch:GetSearchNames() and 
					string.find(string.lower(row[1]), term)) or
					(GuildSearch:GetSearchNotes() and 
				  	 string.find(string.lower(row[3]), term)) or
					(GuildSearch:GetSearchOfficerNotes() and 
					 string.find(string.lower(row[4]), term)) or 
					(GuildSearch:GetSearchRank() and 
					 string.find(string.lower(row[5]), term)) or			
					(GuildSearch:GetSearchClass() and 
					 string.find(string.lower(row[6]), term)) then
					return true
				end

				return false
			else
				return true
			end
		end
	)
	
	guildwindow:Hide()
	
	return guildwindow
end

function GuildSearch:IsWindowVisible()
	if guildFrame then
		return guildFrame:IsVisible()
	else
		return false
	end
end

function GuildSearch:HideGuildWindow()
	if guildFrame then
		guildFrame:Hide()
	end
end

function GuildSearch:SetMinimapButton(info, value)
	-- Reverse the value since the stored value is to hide it and not show it
    self.db.profile.minimap.hide = not value
	if self.db.profile.minimap.hide then
		icon:Hide("GuildSearchLDB")
	else
		icon:Show("GuildSearchLDB")
	end
end

function GuildSearch:GetMinimapButton(info)
	-- Reverse the value since the stored value is to hide it and not show it
    return not self.db.profile.minimap.hide
end

function GuildSearch:SetVerbose(info, value)
    self.db.profile.verbose = value
end

function GuildSearch:GetVerbose(info)
    return self.db.profile.verbose
end

function GuildSearch:SetSearchNames(info, value)
    self.db.profile.searchNames = value
end

function GuildSearch:GetSearchNames(info)
    return self.db.profile.searchNames
end

function GuildSearch:SetSearchNotes(info, value)
    self.db.profile.searchNotes = value
end

function GuildSearch:GetSearchNotes(info)
    return self.db.profile.searchNotes
end

function GuildSearch:SetSearchOfficerNotes(info, value)
    self.db.profile.searchOfficerNotes = value
end

function GuildSearch:GetSearchOfficerNotes(info)
    return self.db.profile.searchOfficerNotes
end

function GuildSearch:SetSearchRank(info, value)
    self.db.profile.searchRank = value
end

function GuildSearch:GetSearchRank(info)
    return self.db.profile.searchRank
end

function GuildSearch:SetSearchClass(info, value)
    self.db.profile.searchClass = value
end

function GuildSearch:GetSearchClass(info)
    return self.db.profile.searchClass
end
