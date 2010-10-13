local GuildSearch = LibStub("AceAddon-3.0"):NewAddon("GuildSearch", "AceConsole-3.0", "AceEvent-3.0")

local ADDON_NAME = ...
local ADDON_VERSION = "@project-version@"

-- Local versions for performance
local tinsert = table.insert

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
		searchClass = false,
		patternMatching = false
	}
}

local options

function GuildSearch:GetOptions()
    if not options then
        options = {
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
                    set = function(info,val)
                        	-- Reverse the value since the stored value is to hide it
                            self.db.profile.minimap.hide = not val
                        	if self.db.profile.minimap.hide then
                        		icon:Hide("GuildSearchLDB")
                        	else
                        		icon:Show("GuildSearchLDB")
                        	end
                          end,
                    get = function(info)
                	        -- Reverse the value since the stored value is to hide it
                            return not self.db.profile.minimap.hide
                          end,
        			order = 10
                },
        	    verbose = {
                    name = L["Verbose"],
                    desc = L["Toggles the display of informational messages"],
                    type = "toggle",
                    set = function(info, val) self.db.profile.verbose = val end,
                    get = function(info) return self.db.profile.verbose end,
        			order = 20
                },
        		displayheader2 = {
        			order = 100,
        			type = "header",
        			name = L["Search Options"],
        		},
                searchNames = {
                    name = L["Search Names"],
                    desc = L["When checked, searches include the character name."],
                    type = "toggle",
                    set = function(info, val) self.db.profile.searchNames = val end,
                    get = function(info) return self.db.profile.searchNames end,
        			order = 110
                },
                searchNotes = {
                    name = L["Search Notes"],
                    desc = L["When checked, searches include the notes."],
                    type = "toggle",
                    set = function(info, val) self.db.profile.searchNotes = val end,
                    get = function(info) return self.db.profile.searchNotes end,
        			order = 120
                },
                searchOfficerNotes = {
                    name = L["Search Officer Notes"],
                    desc = L["When checked, searches include the officer notes."],
                    type = "toggle",
                    set = function(info, val) self.db.profile.searchOfficerNotes = val end,
                    get = function(info) return self.db.profile.searchOfficerNotes end,
        			order = 130
                },
                searchRank = {
                    name = L["Search Rank"],
                    desc = L["When checked, searches include the guild ranks."],
                    type = "toggle",
                    set = function(info, val) self.db.profile.searchRank = val end,
                    get = function(info) return self.db.profile.searchRank end,
        			order = 140
                },
                searchClass = {
                    name = L["Search Class"],
                    desc = L["When checked, searches include the character's class."],
                    type = "toggle",
                    set = function(info, val) self.db.profile.searchClass = val end,
                    get = function(info) return self.db.profile.searchClass end,
        			order = 150
                },
                patternMatching = {
                    name = L["Enable Pattern Matching"],
                    desc = L["Enables pattern matching when searching the guild data."],
                    type = "toggle",
                    set = function(info, val) self.db.profile.patternMatching = val end,
                    get = function(info) return self.db.profile.patternMatching end,
        			order = 160
                },
            }
        }
    end

    return options
end

local guildSearchLDB = nil
local searchTerm = nil
local guildFrame = nil
local guildData = {}

function GuildSearch:OnInitialize()
    -- Called when the addon is loaded
    self.db = LibStub("AceDB-3.0"):New("GuildSearchDB", defaults, "Default")

    -- Register the options table
    LibStub("AceConfig-3.0"):RegisterOptionsTable("GuildSearch", self:GetOptions())
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
		    if button == "RightButton" then
    			local optionsFrame = InterfaceOptionsFrame

    			if optionsFrame:IsVisible() then
    				optionsFrame:Hide()
    			else
    			    self:HideGuildWindow()
    				InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    			end
            elseif button == "LeftButton" then
    			if self:IsWindowVisible() then
    				self:HideGuildWindow()
    			else
        			local optionsFrame = InterfaceOptionsFrame
    			    optionsFrame:Hide()
    				self:GuildSearchHandler("")
    			end
            end
		end,
		OnTooltipShow = function(tooltip)
			if tooltip and tooltip.AddLine then
				tooltip:AddLine(GREEN .. "Guild Search".." "..ADDON_VERSION)
				tooltip:AddLine(YELLOW .. L["Left click"] .. " " .. WHITE
					.. L["to open/close the window"])
				tooltip:AddLine(YELLOW .. L["Right click"] .. " " .. WHITE
					.. L["to open/close the configuration."])
			end
		end
	})
	icon:Register("GuildSearchLDB", guildSearchLDB, self.db.profile.minimap)
end

function GuildSearch:GuildSearchHandler(input)
	searchTerm = input:lower()
	
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
			local className = data[realrow][6]:upper()
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
	searchterm:SetScript("OnShow", function(this) this:SetFocus() end)
	searchterm:SetScript("OnEnterPressed", function(this) table:SortData() end)
	searchterm:SetScript("OnEscapePressed",
	    function(this)
	        this:SetText("")
	        this:GetParent():Hide()
	    end)

	table.frame:SetPoint("TOP", searchterm, "BOTTOM", 0, -20)
	table.frame:SetPoint("LEFT", guildwindow, "LEFT", 25, 0)

	local searchbutton = CreateFrame("Button", nil, guildwindow, "UIPanelButtonTemplate")
	searchbutton:SetText(L["Search"])
	searchbutton:SetWidth(100)
	searchbutton:SetHeight(20)
	searchbutton:SetPoint("LEFT", searchterm, "RIGHT", 10, 0)
	searchbutton:SetScript("OnClick", function(this) table:SortData() end)

	local clearbutton = CreateFrame("Button", nil, guildwindow, "UIPanelButtonTemplate")
	clearbutton:SetText(L["Clear"])
	clearbutton:SetWidth(100)
	clearbutton:SetHeight(20)
	clearbutton:SetPoint("LEFT", searchbutton, "RIGHT", 10, 0)
	clearbutton:SetScript("OnClick",
	    function(this)
	        searchterm:SetText("")
	        table:SortData()
	    end)

	local closebutton = CreateFrame("Button", nil, guildwindow, "UIPanelButtonTemplate")
	closebutton:SetText(L["Close"])
	closebutton:SetWidth(90)
	closebutton:SetHeight(20)
	closebutton:SetPoint("BOTTOM", guildwindow, "BOTTOM", 0, 20)
	closebutton:SetScript("OnClick", function(this) this:GetParent():Hide(); end)

	guildwindow.table = table
	guildwindow.searchterm = searchterm
	
	table:SetFilter(
		function(self, row)
			local term = searchterm:GetText()
			local profile = GuildSearch.db.profile
			if term and #term > 0 then
				term = term:lower()
				local plain = not GuildSearch.db.profile.patternMatching
				if ((profile.searchNames and row[1]:lower():find(term,1,plain)) or
					(profile.searchNotes and row[3]:lower():find(term,1,plain)) or
					(profile.searchOfficerNotes and row[4]:lower():find(term,1,plain)) or 
					(profile.searchRank and row[5]:lower():find(term,1,plain)) or			
					(profile.searchClass and row[6]:lower():find(term,1,plain))) then
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
