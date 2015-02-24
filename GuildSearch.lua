local _G = getfenv(0)

-- Local versions for performance
local tinsert = table.insert
local string = _G.string
local pairs = _G.pairs
local ipairs = _G.ipairs

local GuildSearch = _G.LibStub("AceAddon-3.0"):NewAddon("GuildSearch", "AceConsole-3.0", "AceEvent-3.0")

local ADDON_NAME, addon = ...
local ADDON_VERSION = "@project-version@"

addon.addonName = "Guild Search"

-- Try to remove the Git hash at the end, otherwise return the passed in value.
local function cleanupVersion(version)
	local iter = string.gmatch(version, "(.*)-[a-z0-9]+$")
	if iter then
		local ver = iter()
		if ver and #ver >= 3 then
			return ver
		end
	end
	return version
end

addon.addonTitle = _G.GetAddOnMetadata(ADDON_NAME,"Title")
addon.addonVersion = cleanupVersion("@project-version@")

addon.CURRENT_BUILD, addon.CURRENT_INTERNAL, 
  addon.CURRENT_BUILD_DATE, addon.CURRENT_UI_VERSION = _G.GetBuildInfo()
addon.WoD = addon.CURRENT_UI_VERSION >= 60000

local L = _G.LibStub("AceLocale-3.0"):GetLocale("GuildSearch", true)
local AGU = _G.LibStub("AceGUI-3.0")
local LDB = _G.LibStub("LibDataBroker-1.1")
local icon = _G.LibStub("LibDBIcon-1.0")

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

local function formatRealmName(realm)
	-- Spaces are removed.
	-- Dashes are removed. (e.g., Azjol-Nerub)
	-- Apostrophe / single quotes are not removed.
	if not realm then return end
	return realm:gsub("[ -]", "")
end

local function parseName(name)
	if not name then return end
	local matches = name:gmatch("([^%-]+)")
	if matches then
		local nameOnly = matches()
		local realm = matches()
		return nameOnly, realm
	end
	return nil
end

local ColumnWidths = {
	["default"] = {
		window = 700,
		name = 110,
		level = 40,
		note = 150,
		onote = 80,
		rank = 60,
		lastOnline = 100,
		optional = 60,
	},
	["1000"] = {
		window = 1000,
		name = 200,
		level = 50,
		note = 200,
		onote = 150,
		rank = 100,
		lastOnline = 100,
		optional = 100,
	},
}

local defaults = {
	profile = {
		minimap = {
			hide = true,
		},
		columnWidths = ColumnWidths["default"],
		verbose = false,
		debug = false,
		searchNames = true,
		searchNotes = true,
		searchOfficerNotes = true,
		searchRank = false,
		searchClass = false,
		searchRealm = false,
		patternMatching = false,
		optionalColumn = "Realm",
		remember_main_pos = true,
		lock_main_window = false,
		main_window_x = 0,
		main_window_y = 0,
		hideOnEsc = true,
	}
}

local guildSearchLDB = nil
local searchTerm = nil
local guildFrame = nil
local guildData = {}
local memberDetailFrame = nil
local guildRanks = {}
local guildRanksRev = {}
local guildRanksAuth = {}
local realmName = _G.GetRealmName()
local realmNameAbbrv = formatRealmName(realmName)
addon.lastUpdate = nil

local NAME_COL = 1
local LEVEL_COL = 2
local NOTE_COL = 3
local ONOTE_COL = 4
local RANK_COL = 5
local LASTONLINE_COL = 6
local OPTIONAL_COL = 7
local REALM_COL = 8
local CLASS_COL = 9
local RANKNUM_COL = 10
local INDEX_COL = 11

local options

function GuildSearch:ResetColumnWidths(name)
	for k, v in pairs(ColumnWidths[name or "default"]) do
		self.db.profile.columnWidths[k] = v
	end
end

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
        	    hideOnEsc = {
                    name = L["Hide on Escape"],
                    desc = L["HideOnEsc_Desc"],
                    type = "toggle",
                    set = function(info, val) self.db.profile.hideOnEsc = val end,
                    get = function(info) return self.db.profile.hideOnEsc end,
        			order = 30
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
                searchRealms = {
                    name = L["Search Realms"],
                    desc = L["SearchRealms_Desc"],
                    type = "toggle",
                    set = function(info, val) self.db.profile.searchRealm = val end,
                    get = function(info) return self.db.profile.searchRealm end,
        			order = 160
                },
                patternMatching = {
                    name = L["Enable Pattern Matching"],
                    desc = L["Enables pattern matching when searching the guild data."],
                    type = "toggle",
                    set = function(info, val) self.db.profile.patternMatching = val end,
                    get = function(info) return self.db.profile.patternMatching end,
        			order = 170
                },
        		headerMainWindow = {
        			order = 200,
        			type = "header",
        			name = L["Main Window"],
        		},
                lock_main_window = {
                    name = L["Lock"],
                    desc = L["Lock_OptionDesc"],
                    type = "toggle",
                    set = function(info,val)
                        self.db.profile.lock_main_window = val
                        guildFrame.lock = val
                    end,
                    get = function(info) return self.db.profile.lock_main_window end,
        			order = 210
                },
                remember_main_pos = {
                    name = L["Remember Position"],
                    desc = L["RememberPosition_OptionDesc"],
                    type = "toggle",
                    set = function(info,val) self.db.profile.remember_main_pos = val end,
                    get = function(info) return self.db.profile.remember_main_pos end,
        			order = 220
                },
        		headerAdvanced = {
        			order = 300,
        			type = "header",
        			name = L["Advanced Settings"],
        		},
        		advancedDesc = {
        			order = 310,
        			type = "description",
        			name = L["Advanced_Desc"],
        		},
				optionalColumn = {
					name = L["Optional Column"],
					desc = L["OptionalColumn_Desc"],
					type = "select",
					values = {
					    ["Realm"] = L["Realm"],
					},
					order = 320,
					set = function(info, val)
					    self.db.profile.optionalColumn = val
					end,
	                get = function(info)
	                    return self.db.profile.optionalColumn
	                end,
				},
        		columnWidthHdr = {
        			order = 400,
        			type = "header",
        			name = L["Column Widths"],
        		},
        		columnWidthDesc = {
        			order = 410,
        			type = "description",
        			name = L["ColumnWidths_Desc"],
        		},
				columnWidthWindow = {
					order = 415,
					name = L["Window"],
					desc = L["Window_Desc"],
					type = "range",
					min = 0,
					max = 3000,
					width = "full",
					step = 1,
					set = function(info, val) 
						self.db.profile.columnWidths.window = val
					end,
					get = function(info,val) return
						self.db.profile.columnWidths.window
					end,
				},
				columnWidthName = {
					order = 420,
					name = L["Name"],
					desc = L["Name"],
					type = "range",
					min = 0,
					max = 300,
					step = 1,
					set = function(info, val) 
						self.db.profile.columnWidths.name = val
					end,
					get = function(info,val) return
						self.db.profile.columnWidths.name
					end,
				},
				columnWidthLevel = {
					order = 430,
					name = L["Level"],
					desc = L["Level"],
					type = "range",
					min = 0,
					max = 300,
					step = 1,
					set = function(info, val) 
						self.db.profile.columnWidths.level = val
					end,
					get = function(info,val) return
						self.db.profile.columnWidths.level
					end,
				},
				columnWidthNote = {
					order = 440,
					name = L["Note"],
					desc = L["Note"],
					type = "range",
					min = 0,
					max = 300,
					step = 1,
					set = function(info, val) 
						self.db.profile.columnWidths.note = val
					end,
					get = function(info,val) return
						self.db.profile.columnWidths.note
					end,
				},
				columnWidthOfficerNote = {
					order = 450,
					name = L["Officer Note"],
					desc = L["Officer Note"],
					type = "range",
					min = 0,
					max = 300,
					step = 1,
					set = function(info, val) 
						self.db.profile.columnWidths.onote = val
					end,
					get = function(info,val) return
						self.db.profile.columnWidths.onote
					end,
				},
				columnWidthRank = {
					order = 460,
					name = L["Rank"],
					desc = L["Rank"],
					type = "range",
					min = 0,
					max = 300,
					step = 1,
					set = function(info, val) 
						self.db.profile.columnWidths.rank = val
					end,
					get = function(info,val) return
						self.db.profile.columnWidths.rank
					end,
				},
				columnWidthLastOnline = {
					order = 470,
					name = L["Last Online"],
					desc = L["Last Online"],
					type = "range",
					min = 0,
					max = 300,
					step = 1,
					set = function(info, val) 
						self.db.profile.columnWidths.lastOnline = val
					end,
					get = function(info,val) return
						self.db.profile.columnWidths.lastOnline
					end,
				},
				columnWidthOptional = {
					order = 480,
					name = L["Optional"],
					desc = L["Optional"],
					type = "range",
					min = 0,
					max = 300,
					step = 1,
					set = function(info, val) 
						self.db.profile.columnWidths.optional = val
					end,
					get = function(info,val) return
						self.db.profile.columnWidths.optional
					end,
				},
				widthReset = {
					name = L["Reset to Defaults"],
					desc = L["Reset_Desc"],
					type = "execute",
					order = 500,
					width = "full",
					func = function()
						self:ResetColumnWidths()
					end,
				},
				widthReset1000 = {
					name = L["Reset to 1000 pixel"],
					desc = L["Reset1000_Desc"],
					type = "execute",
					order = 501,
					width = "full",
					func = function()
						self:ResetColumnWidths("1000")
					end,
				},
				reloadUI = {
					name = L["Reload UI"],
					desc = L["ReloadUI_Desc"],
					type = "execute",
					order = 502,
					width = "full",
					func = function()
						_G.ReloadUI()
					end,
				},
			},
        }
    end

    return options
end

function GuildSearch:OnInitialize()
	-- Called when the addon is loaded
	self.db = _G.LibStub("AceDB-3.0"):New("GuildSearchDB", defaults, "Default")
	self.optionalColumn = self.db.profile.optionalColumn

	-- Register the options table
	_G.LibStub("AceConfig-3.0"):RegisterOptionsTable("GuildSearch", self:GetOptions())
	self.optionsFrame = _G.LibStub("AceConfigDialog-3.0"):AddToBlizOptions(
		"GuildSearch", "Guild Search")

	-- Create the guild frame
	guildFrame = self:CreateGuildFrame()

	-- Register the command line options
	self:RegisterChatCommand("gsearch", "GuildSearchHandler")	
	self:RegisterChatCommand("promotables", "GetPromotable")	

	-- Create the LDB launcher
	guildSearchLDB = LDB:NewDataObject("GuildSearch",{
		type = "launcher",
		icon = "Interface\\Icons\\INV_Scroll_03.blp",
		OnClick = function(clickedframe, button)
			if button == "RightButton" then
				local optionsFrame = _G.InterfaceOptionsFrame

				if optionsFrame:IsVisible() then
					optionsFrame:Hide()
				else
					self:HideGuildWindow()
					_G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
				end
			elseif button == "LeftButton" then
				if self:IsWindowVisible() then
					self:HideGuildWindow()
				else
					local optionsFrame = _G.InterfaceOptionsFrame
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

local function splitWords(str)
  local w = {}
  local function helper(word) _G.table.insert(w, word) return nil end
  str:gsub("(%w+)", helper)
  return w
end

function GuildSearch:GuildSearchHandler(input)
	-- Check for any debugging commands first
	if input and input:trim() ~= "" then
		local cmds = splitWords(input)
		if cmds[1] and cmds[1] == "debug" then
			if cmds[2] and cmds[2] == "on" then
				self.db.profile.debug = true
				self:Print("Debugging on.  Use '/gsearch debug off' to disable.")
				return
			elseif cmds[2] and cmds[2] == "off" then
				self.db.profile.debug = false
				self:Print("Debugging off.")
				return
			end
		end		
	end

	self:ShowAndUpdateGuildFrame(input)
end

function GuildSearch:OnEnable()
	-- Called when the addon is enabled

	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("GUILD_ROSTER_UPDATE")
	self:RegisterEvent("GUILD_RANKS_UPDATE")
	
	memberDetailFrame = self:CreateMemberDetailsFrame()
end

function GuildSearch:OnDisable()
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("GUILD_ROSTER_UPDATE")
	self:UnregisterEvent("GUILD_RANKS_UPDATE")
end

function GuildSearch:PopulateGuildRanks()
	local numRanks = _G.GuildControlGetNumRanks()
	local name

	_G.wipe(guildRanks)

	for i = 1, numRanks do
		name = _G.GuildControlGetRankName(i)
		guildRanks[i] = name
	end

	_G.wipe(guildRanksRev)
	for k,v in pairs(guildRanks) do
		guildRanksRev[v] = k
	end

	_G.wipe(guildRanksAuth)
	for i = 1, numRanks do
		_G.GuildControlSetRank(i)
		local requiresAuth = _G.select(18, _G.GuildControlGetRankFlags()) and 
			true or false
		guildRanksAuth[i] = requiresAuth
	end

	self:RefreshMemberDetails()
end

function GuildSearch:GetPromotable()
	local testRank = nil
	local maxRank = 1
	for k, v in pairs(guildRanksAuth) do
		if v then
			testRank = k
		end
		maxRank = k
	end
	if not testRank then
		self:Print("No authenticated ranks.")
		return
	end
	
	local promotables = {}
	local count = 0
	local numMembers = _G.GetNumGuildMembers()
	for i = 1, numMembers do
		local name, rank, rankIndex = _G.GetGuildRosterInfo(i)
		rankIndex = rankIndex + 1
		if not guildRanksAuth[rankIndex] then
	        local allowed, reason = _G.IsGuildRankAssignmentAllowed(i, testRank);
	        if allowed then
				count = count + 1
				if rankIndex > maxRank then
					self:Print(name)
				end
			end
		end
	end
	self:Print("Promotables: ".._G.tostring(count))
end

local combatTimer = nil
local function CallPopulateGuildData()
	combatTimer = false
	GuildSearch:PopulateGuildData()
end

function GuildSearch:PopulateGuildData()
	if _G.UnitAffectingCombat("player") then
		return
	end

	_G.wipe(guildData)
	
	if _G.IsInGuild() then
		local guildName, gRank, gRankIndex, realm = _G.GetGuildInfo("player")
		local guildRealm = formatRealmName(realm)

		local numMembers = _G.GetNumGuildMembers()
		for index = 1, numMembers do
			local name, rank, rankIndex, level, class, zone, note, 
				officernote, online, status, classFileName = _G.GetGuildRosterInfo(index)

			local nameOnly, realmOnly = parseName(name)
			local charRealm = realmOnly or guildRealm or realmNameAbbrv or ""
      local years, months, days, hours = _G.GetGuildRosterLastOnline(index)
      local lastOnline = 0
      local lastOnlineDate = ""
      if online then
        lastOnline = _G.time()
        lastOnlineDate = _G.date("%Y/%m/%d %H:%M", lastOnline)
      elseif years and months and days and hours then
        local diff = (((years*365)+(months*30)+days)*24+hours)*60*60
        lastOnline = _G.time() - diff
        lastOnlineDate = _G.date("%Y/%m/%d %H:00", lastOnline)
      end

			local optional = ""
			--if self.optionalColumn == "TotalXP" then
			optional = charRealm
			--end

			tinsert(guildData, 
			    {name, level, note, officernote, rank, lastOnlineDate, 
					optional, charRealm, classFileName, rankIndex, index})
		end
		addon.lastUpdate = _G.time()
	end

	self:RefreshMemberDetails()

	-- Update the guild data now
	if guildFrame and guildFrame.table then
		guildFrame.table:SetData(guildData, true)
		self:UpdateRowCount()
	end
end

function GuildSearch:PLAYER_REGEN_DISABLED()
	self:UnregisterEvent("GUILD_ROSTER_UPDATE")
end

function GuildSearch:PLAYER_REGEN_ENABLED()
	if self:IsWindowVisible() then
		self:RegisterEvent("GUILD_ROSTER_UPDATE")
	end
end

function GuildSearch:GUILD_RANKS_UPDATE(event, ...)
	self:PopulateGuildRanks()
end

function GuildSearch:GUILD_ROSTER_UPDATE(event, update, ...)
	if _G.UnitAffectingCombat("player") then return end

	-- If the window isn't shown, don't update the data unless it was never updated.
	if not self:IsWindowVisible() then
		if addon.lastUpdate then
			return
		else
			self:UnregisterEvent("GUILD_ROSTER_UPDATE")
		end
	end

	if update then
		-- Clear the current selection in the window as it will change
		if guildFrame and guildFrame.table then
			guildFrame.table:ClearSelection()
		end
		_G.GuildRoster()
	end

	self:PopulateGuildData()
end

local invalidRankFmt = "Attempt to set member rank to an invalid rank. (%s)"
local changingRankFmt = "Changing rank for %s from %s to %s."
local noRankFoundFmt = "Invalid rank returned for roster id. (%s)"
function GuildSearch:UpdateMemberDetail(name, publicNote, officerNote, newRankIndex)
	if not _G.IsInGuild() or name == nil or #name == 0 then
        return false
    end

	local numMembers = _G.GetNumGuildMembers()
	local i = 0
	local charname, rank, rankIndex, level, class, zone, note, 
		officernote, online, status, classFileName

    while name ~= charname and i < numMembers do
        i = i + 1
		charname, rank, rankIndex, level, class, zone, note, officernote,
			online, status, classFileName = _G.GetGuildRosterInfo(i)
	end
    
    if name == charname and i > 0 then
        if publicNote and _G.CanEditPublicNote() then
            _G.GuildRosterSetPublicNote(i, publicNote)
        end

        if officerNote and _G.CanEditOfficerNote() then
            _G.GuildRosterSetOfficerNote(i, officerNote)
        end

        if newRankIndex then
            local numRanks = _G.GuildControlGetNumRanks()

            if newRankIndex < 0 or newRankIndex > numRanks then
                self:Print(invalidRankFmt:format(newRankIndex or "nil"))
                return
            end

            if rankIndex then
                rankIndex = rankIndex + 1
                if rankIndex ~= newRankIndex then
                    if self.db.profile.verbose then
                        self:Print(
                            changingRankFmt:format(charname, rankIndex, newRankIndex))
                    end
                    _G.SetGuildMemberRank(i, newRankIndex)
                end
            else
                self:Print(noRankFoundFmt:format(i))
            end
        end
    end
end

function GuildSearch:RemoveGuildMember(name)
    if _G.CanGuildRemove() then
        _G.GuildUninvite(name)
        memberDetailFrame:Hide()
    end
end

function GuildSearch:StaticPopupRemoveGuildMember(name)
	_G.StaticPopupDialogs["GuildSearch_RemoveGuildMember"] = 
	    _G.StaticPopupDialogs["GuildSearch_RemoveGuildMember"] or {
					text = L["GUILD_REMOVE_CONFIRMATION"], 
					button1 = _G.ACCEPT, 
					button2 = _G.CANCEL,
					whileDead = true,
					hideOnEscape = true,
					showAlert = true,
					timeout = 0,
                    enterClicksFirstButton = false,
					OnAccept = function(self, data) 
					    GuildSearch:RemoveGuildMember(data)
					end,
				}
	_G.StaticPopupDialogs["GuildSearch_RemoveGuildMember"].hideOnEscape = 
		self.db.profile.hideOnEsc
    local dialog = _G.StaticPopup_Show("GuildSearch_RemoveGuildMember", name)
    if dialog then
        dialog.data = name
    end
end

function GuildSearch:CreateMemberDetailsFrame()
	local detailwindow = _G.CreateFrame("Frame", "GuildSearch_DetailsWindow", _G.UIParent)
	detailwindow:SetFrameStrata("DIALOG")
	detailwindow:SetToplevel(true)
	detailwindow:SetWidth(400)
	detailwindow:SetHeight(320)
	detailwindow:SetPoint("CENTER", _G.UIParent)
	detailwindow:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	detailwindow:SetBackdropColor(0,0,0,1)

    detailwindow.name = ""
	detailwindow.memberRank = 1
	detailwindow.index = 0

	local savebutton = _G.CreateFrame("Button", nil, detailwindow, "UIPanelButtonTemplate")
	savebutton:SetText(L["Save"])
	savebutton:SetWidth(100)
	savebutton:SetHeight(20)
	savebutton:SetPoint("BOTTOM", detailwindow, "BOTTOM", -60, 20)
	savebutton:SetScript("OnClick",
	    function(this)
	        local frame = this:GetParent()
	        local publicNote = frame.publicnote:GetText()
	        local officerNote = frame.officernote:GetText()
            local rank = _G.UIDropDownMenu_GetSelectedValue(frame.rankDropdown)
	        self:UpdateMemberDetail(
	            frame.charname:GetText(), publicNote, officerNote, rank)
	        frame:Hide()
	    end)

	local cancelbutton = _G.CreateFrame("Button", nil, detailwindow, "UIPanelButtonTemplate")
	cancelbutton:SetText(L["Cancel"])
	cancelbutton:SetWidth(100)
	cancelbutton:SetHeight(20)
	cancelbutton:SetPoint("BOTTOM", detailwindow, "BOTTOM", 60, 20)
	cancelbutton:SetScript("OnClick", function(this) this:GetParent():Hide(); end)

	local headertext = detailwindow:CreateFontString("GS_HeaderText", detailwindow, "GameFontNormalLarge")
	headertext:SetPoint("TOP", detailwindow, "TOP", 0, -20)
	headertext:SetText(L["Guild Member Details"])

	local charname = detailwindow:CreateFontString("GS_CharName", detailwindow, "GameFontNormal")
	charname:SetPoint("BOTTOM", headertext, "BOTTOM", 0, -40)
	charname:SetFont(charname:GetFont(), 14)
	charname:SetTextColor(1.0,1.0,1.0,1)

    local rankLabel = detailwindow:CreateFontString("GS_RankLabel", detailwindow, "GameFontNormal")
	rankLabel:SetPoint("TOP", charname, "BOTTOM", 0, -20)
	rankLabel:SetPoint("LEFT", detailwindow, "LEFT", 20, 0)
	--rankLabel:SetFont(rankLabel:GetFont(), 14)
	--rankLabel:SetTextColor(1.0,1.0,1.0,1)
	rankLabel:SetText(L["Rank"]..":")

    local rankDropdown = _G.CreateFrame("Button", "GS_RankDropDown", detailwindow, "UIDropDownMenuTemplate")
    rankDropdown:ClearAllPoints()
    rankDropdown:SetPoint("TOPLEFT", rankLabel, "TOPRIGHT", 7, 5)
    rankDropdown:Show()
    _G.UIDropDownMenu_Initialize(rankDropdown, function(self, level)
        -- The following code is partially copied from Blizzard's code
        -- in Blizzard_GuildRoster.lua

        local numRanks = _G.GuildControlGetNumRanks()
        -- Get the user's rank and adjust to 1-based
        local _, _, userRankIndex = _G.GetGuildInfo("player")
        userRankIndex = userRankIndex + 1
        -- The current member's rank
        local memberRankIndex = self:GetParent().memberRank

        -- Set the highest rank to 1 above the user's rank
        local highestRank = userRankIndex + 1
        -- If the user cannot promote, the highest rank is the current member's rank
        if (not _G.CanGuildPromote()) or userRankIndex >= memberRankIndex then
            highestRank = memberRankIndex
        end
        
        local lowestRank = numRanks
        if (not _G.CanGuildDemote()) or userRankIndex >= memberRankIndex then
            lowestRank = memberRankIndex
        end

        for i = highestRank, lowestRank do
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text = _G.GuildControlGetRankName(i)
            info.value = i
            info.arg1 = i
            info.colorCode = WHITE
            info.checked = i == memberRankIndex
            info.func = function(self) 
                _G.UIDropDownMenu_SetSelectedValue(rankDropdown, self.value)
            end
            -- If not the current rank, then check if the rank is allowed to be set
            -- In addition to rank restrictions, an authenticator can prohibit too
            if not info.checked then
                local allowed, reason = _G.IsGuildRankAssignmentAllowed(
					(self:GetParent().index or 0), i);
                if not allowed and reason == "authenticator" then
                    info.disabled = true;
                    info.tooltipWhileDisabled = 1;
                    info.tooltipTitle = _G.GUILD_RANK_UNAVAILABLE;
                    info.tooltipText = _G.GUILD_RANK_UNAVAILABLE_AUTHENTICATOR;
                    info.tooltipOnButton = 1;
                end
            end
            _G.UIDropDownMenu_AddButton(info, level)
        end
    end)
    _G.UIDropDownMenu_SetWidth(rankDropdown, 100);
    _G.UIDropDownMenu_SetButtonWidth(rankDropdown, 124)
    _G.UIDropDownMenu_SetSelectedValue(rankDropdown, 0)
    _G.UIDropDownMenu_JustifyText(rankDropdown, "LEFT")

	local removebutton = _G.CreateFrame("Button", nil, detailwindow, "UIPanelButtonTemplate")
	removebutton:SetText(L["Remove"])
	removebutton:SetWidth(100)
	removebutton:SetHeight(20)
	removebutton:SetPoint("TOP", rankLabel, "TOP", 0, 3)
	removebutton:SetPoint("RIGHT", detailwindow, "RIGHT", -30, 0)
	removebutton:SetScript("OnClick",
	    function(this)
	        local frame = this:GetParent()
	        frame:Hide()
        	GuildSearch:StaticPopupRemoveGuildMember(frame.name)
	    end)
	detailwindow.removebutton = removebutton

	local noteHeader = detailwindow:CreateFontString("GS_NoteHeaderText", detailwindow, "GameFontNormal")
	noteHeader:SetPoint("TOPLEFT", rankLabel, "BOTTOMLEFT", 0, -15)
	noteHeader:SetText(L["Public Note"]..":")

    local publicNoteContainer = _G.CreateFrame("Frame", nil, detailwindow)
    publicNoteContainer:SetPoint("TOPLEFT", noteHeader, "BOTTOMLEFT", 0, -8)
    publicNoteContainer:SetHeight(50)
    publicNoteContainer:SetWidth(340)
    --publicNoteContainer:SetPoint("TOPLEFT", detailwindow, "TOPLEFT", 20, -140)
    --publicNoteContainer:SetPoint("BOTTOMRIGHT", detailwindow, "BOTTOMRIGHT", -40, 130)
	publicNoteContainer:SetBackdrop(
		{bgFile="Interface\\Tooltips\\UI-Tooltip-Background", 
	    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true,
		tileSize=16, edgeSize=16, insets={left=4, right=3, top=4, bottom=3}})
	publicNoteContainer:SetBackdropColor(0,0,0,0.9)

    local noteScrollArea = _G.CreateFrame("ScrollFrame", "GS_MemberDetails_PublicNoteScroll", detailwindow, "UIPanelScrollFrameTemplate")
    noteScrollArea:SetPoint("TOPLEFT", publicNoteContainer, "TOPLEFT", 6, -6)
    noteScrollArea:SetPoint("BOTTOMRIGHT", publicNoteContainer, "BOTTOMRIGHT", -6, 6)

	local notebox = _G.CreateFrame("EditBox", "GS_MemberDetails_PublicNoteBox", detailwindow)
	notebox:SetFontObject(_G.ChatFontNormal)
	notebox:SetMultiLine(true)
	notebox:SetAutoFocus(true)
	notebox:SetWidth(300)
	notebox:SetHeight(2*14)
	notebox:SetMaxLetters(0)
	notebox:SetScript("OnShow", function(this) notebox:SetFocus() end)
	if self.db.profile.hideOnEsc then
		notebox:SetScript("OnEscapePressed",
		    function(this)
		        this:SetText("")
		        this:GetParent():GetParent():Hide()
		    end)
	end
	notebox.scrollArea = noteScrollArea
    notebox:SetScript("OnCursorChanged", function(self, _, y, _, cursorHeight)
    	self, y = self.scrollArea, -y
    	local offset = self:GetVerticalScroll()
    	if y < offset then
    		self:SetVerticalScroll(y)
    	else
    		y = y + cursorHeight - self:GetHeight()
    		if y > offset then
    			self:SetVerticalScroll(y)
    		end
    	end
    end)
    noteScrollArea:SetScrollChild(notebox)

	local onoteHeader = detailwindow:CreateFontString("GS_OfficerNoteHeaderText", detailwindow, "GameFontNormal")
	onoteHeader:SetPoint("TOPLEFT", publicNoteContainer, "BOTTOMLEFT", 0, -15)
	onoteHeader:SetText(L["Officer Note"]..":")

    local officerNoteContainer = _G.CreateFrame("Frame", nil, detailwindow)
    officerNoteContainer:SetPoint("TOPLEFT", onoteHeader, "BOTTOMLEFT", 0, -8)
    officerNoteContainer:SetHeight(50)
    officerNoteContainer:SetWidth(340)
    --officerNoteContainer:SetPoint("TOPLEFT", detailwindow, "TOPLEFT", 20, -220)
    --officerNoteContainer:SetPoint("BOTTOMRIGHT", detailwindow, "BOTTOMRIGHT", -40, 50)
	officerNoteContainer:SetBackdrop(
		{bgFile="Interface\\Tooltips\\UI-Tooltip-Background", 
	    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true,
		tileSize=16, edgeSize=16, insets={left=4, right=3, top=4, bottom=3}})
	officerNoteContainer:SetBackdropColor(0,0,0,0.9)

    local onoteScrollArea = _G.CreateFrame("ScrollFrame", "GS_MemberDetails_OfficerNoteScroll", detailwindow, "UIPanelScrollFrameTemplate")
    onoteScrollArea:SetPoint("TOPLEFT", officerNoteContainer, "TOPLEFT", 6, -6)
    onoteScrollArea:SetPoint("BOTTOMRIGHT", officerNoteContainer, "BOTTOMRIGHT", -6, 6)

	local onotebox = _G.CreateFrame("EditBox", "GS_MemberDetails_OfficerNoteBox", detailwindow)
	onotebox:SetFontObject(_G.ChatFontNormal)
	onotebox:SetMultiLine(true)
	onotebox:SetAutoFocus(true)
	onotebox:SetWidth(300)
	onotebox:SetHeight(2*14)
	onotebox:SetMaxLetters(0)
	--onotebox:SetScript("OnShow", function(this) onotebox:SetFocus() end)
	if self.db.profile.hideOnEsc then
		onotebox:SetScript("OnEscapePressed",
		    function(this)
		        this:SetText("")
		        this:GetParent():GetParent():Hide()
		    end)
	end
	onotebox.scrollArea = onoteScrollArea
    onotebox:SetScript("OnCursorChanged", function(self, _, y, _, cursorHeight)
    	self, y = self.scrollArea, -y
    	local offset = self:GetVerticalScroll()
    	if y < offset then
    		self:SetVerticalScroll(y)
    	else
    		y = y + cursorHeight - self:GetHeight()
    		if y > offset then
    			self:SetVerticalScroll(y)
    		end
    	end
    end)
    onoteScrollArea:SetScrollChild(onotebox)

	detailwindow.charname = charname
	detailwindow.publicnote = notebox
	detailwindow.officernote = onotebox
	detailwindow.rankDropdown = rankDropdown

    detailwindow:SetMovable(true)
    detailwindow:RegisterForDrag("LeftButton")
    detailwindow:SetScript("OnDragStart",
        function(this,button)
        	this:StartMoving()
        end)
    detailwindow:SetScript("OnDragStop",
        function(this)
            this:StopMovingOrSizing()
        end)
    detailwindow:EnableMouse(true)

	detailwindow:Hide()

	return detailwindow
end

local MemberDetailsFrame = nil
function GuildSearch:ShowGuildMemberDetailsFrame(name, publicNote, officerNote, rank)
    if MemberDetailsFrame then return end

    local frame = AGU:Create("Frame")
    frame:SetTitle(L["Guild Member Details"])
    frame:SetWidth(400)
    frame:SetHeight(250)
    frame:SetLayout("Flow")
	frame:SetCallback("OnClose", function(widget)
		widget:ReleaseChildren()
		widget:Release()
		MemberDetailsFrame = nil
	end)
    MemberDetailsFrame = frame

    local text =  AGU:Create("Label")
    text:SetText(name)
    text:SetFont(_G.GameFontNormalLarge:GetFont())
    text.label:SetJustifyH("CENTER")
    text:SetFullWidth(true)
    text:SetCallback("OnRelease",
        function(widget)
            widget.label:SetJustifyH("LEFT")
        end
    )
    frame:AddChild(text)

    local spacer = AGU:Create("Label")
    spacer:SetFullWidth(true)
    spacer:SetText(" ")
    frame:AddChild(spacer)

    local notebox = AGU:Create("MultiLineEditBox")
    notebox:SetFullWidth(true)
    notebox:SetText(publicNote)
    notebox:SetLabel(L["Public Note"])
    notebox:SetNumLines(5)
    notebox:SetMaxLetters(0)
    notebox:SetFocus()
    notebox.editBox:HighlightText()
	notebox:SetCallback("OnEnterPressed", function(widget, event, noteText)
        GuildSearch:SavePublicNote(name, noteText)
    end)
    frame:AddChild(notebox)

    local onotebox = AGU:Create("MultiLineEditBox")
    onotebox:SetFullWidth(true)
    onotebox:SetText(officerNote)
    onotebox:SetLabel(L["Officer Note"])
    onotebox:SetNumLines(5)
    onotebox:SetMaxLetters(0)
    onotebox:SetFocus()
    onotebox.editBox:HighlightText()
	onotebox:SetCallback("OnEnterPressed", function(widget, event, noteText)
        GuildSearch:SaveOfficerNote(name, noteText)
    end)
    frame:AddChild(onotebox)

end

function GuildSearch:RefreshMemberDetails()
	if memberDetailFrame and memberDetailFrame:IsShown() then
		local name = memberDetailFrame.name
		local publicNote, officerNote, rank, index
		local found = false

		for i, data in ipairs(guildData) do
			if data and data[NAME_COL] and data[NAME_COL] == name then
				found = true
				publicNote = data[NOTE_COL]
				officerNote = data[ONOTE_COL]
				rank = data[RANKNUM_COL]
				index = data[INDEX_COL]
			end
		end
	    
		if found then
			self:UpdateMemberRank(rank)
		else
			memberDetailFrame:Hide()
		end
	end
end

function GuildSearch:UpdateMemberRank(rank)
    local memberRankIndex = rank + 1
    if memberDetailFrame then
    	_G.UIDropDownMenu_SetSelectedValue(memberDetailFrame.rankDropdown, memberRankIndex)
    	if guildRanks[memberRankIndex] then
            _G.UIDropDownMenu_SetText(
                memberDetailFrame.rankDropdown, WHITE..guildRanks[memberRankIndex].."|r")
        end

        local _, _, userRankIndex = _G.GetGuildInfo("player")

        if rank <= userRankIndex then
            -- Disable since you cannot change an equal or higher ranked char.
            memberDetailFrame.rankDropdown:Disable()
        elseif _G.CanGuildPromote() or _G.CanGuildDemote() then
            memberDetailFrame.rankDropdown:Enable()
        else
            memberDetailFrame.rankDropdown:Disable()
        end
    end
end

function GuildSearch:ShowMemberDetails(name, publicNote, officerNote, rank, index)
    if name and #name > 0 then
        local detailwindow = memberDetailFrame
        if detailwindow then
            detailwindow.name = name
            detailwindow.charname:SetText(name)
            detailwindow.publicnote:SetText(publicNote or "")
            detailwindow.officernote:SetText(officerNote or "")
            detailwindow.memberRank = rank + 1
            detailwindow.index = index

            if _G.CanEditPublicNote() then
                detailwindow.publicnote:Enable()
            else
                detailwindow.publicnote:Disable()
            end

            if _G.CanEditOfficerNote() then
                detailwindow.officernote:Enable()
            else
                detailwindow.officernote:Disable()
            end

            if _G.CanGuildRemove() then
                detailwindow.removebutton:Show()
            else
                detailwindow.removebutton:Hide()
            end

            self:UpdateMemberRank(rank)

            detailwindow:Show()
            detailwindow:Raise()
        end
    end
end

function GuildSearch:ShowAndUpdateGuildFrame(input)
	if _G.UnitAffectingCombat("player") then
		return
	end

	searchTerm = input and input:lower() or ""
	guildFrame.SetSearchTerm(searchTerm)

	-- Show the guild frame
	guildFrame:Show()

	-- Need to turn on offline display to be able to seach them
	_G.SetGuildRosterShowOffline(true)

	-- Update the guild roster
	if _G.IsInGuild() then
		self:RegisterEvent("GUILD_ROSTER_UPDATE")
		_G.GuildRoster()
	end
end

function GuildSearch:CreateGuildFrame()
	local guildwindow = _G.CreateFrame("Frame", "GuildSearchWindow", _G.UIParent)
	guildwindow:SetFrameStrata("DIALOG")
	guildwindow:SetToplevel(true)
	guildwindow:SetWidth(self.db.profile.columnWidths.window)
	guildwindow:SetHeight(450)

	if self.db.profile.remember_main_pos then
		guildwindow:SetPoint("CENTER", _G.UIParent, "CENTER",
		self.db.profile.main_window_x, self.db.profile.main_window_y)
	else
		guildwindow:SetPoint("CENTER", _G.UIParent)
	end

	guildwindow.lock = self.db.profile.lock_main_window

	guildwindow:SetBackdrop(
		{bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})

	local ScrollingTable = _G.LibStub("ScrollingTable");

	local cols = {}
	cols[1] = {
		["name"] = L["Name"],
		["width"] = self.db.profile.columnWidths.name or 50,
		["align"] = "LEFT",
		["color"] = function(data, cols, realrow, column, table)
			local className
			if data[realrow] and data[realrow][CLASS_COL] then
				className = data[realrow][CLASS_COL]:upper()
				if className == "DEATH KNIGHT" then
					className = "DEATHKNIGHT"
				end
			end
			return _G.RAID_CLASS_COLORS[className] or WHITE_VALUE
		end,
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
		["width"] = self.db.profile.columnWidths.level or 50,
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
		["sortnext"]= 1,
		["DoCellUpdate"] = nil,
	}
	cols[3] = {
		["name"] = L["Note"],
		["width"] = self.db.profile.columnWidths.note or 50,
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
		["width"] = self.db.profile.columnWidths.onote or 50,
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
		["width"] = self.db.profile.columnWidths.rank or 50,
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
		["comparesort"] = function (st, rowa, rowb, col)
				local cella, cellb = st:GetCell(rowa, col), st:GetCell(rowb, col);
				local a1, b1 = cella, cellb;
				if _G.type(a1) == 'table' then  
					a1 = a1.value; 
				end
				if _G.type(b1) == 'table' then 
					b1 = b1.value;
				end 
				local column = st.cols[col];
		
				if _G.type(a1) == "function" then 
					if (cella.args) then 
						a1 = a1(_G.unpack(cella.args))
					else
						a1 = a1(st.data, self.cols, rowa, col, st);
					end
				end
				if _G.type(b1) == "function" then 
					if (cellb.args) then 
						b1 = b1(_G.unpack(cellb.args))
					else	
						b1 = b1(st.data, st.cols, rowb, col, st);
					end
				end

				local valuea = guildRanksRev[a1] or 11
				local valueb = guildRanksRev[b1] or 11

				if valuea == valueb then 
					if column.sortnext then
						local nextcol = st.cols[column.sortnext];
						if not(nextcol.sort) then 
							if nextcol.comparesort then 
								return nextcol.comparesort(st, rowa, rowb, column.sortnext);
							else
								return st:CompareSort(rowa, rowb, column.sortnext);
							end
						else
							return false;
						end
					else
						return false; 
					end 
				else
					local direction = column.sort or column.defaultsort or "asc"
					-- The comparisons below are reversed since the numeric 
					-- rank order is reversed (lower is higher). 
					if direction:lower() == "asc" then
						return valuea > valueb
					else
						return valuea < valueb
					end
				end
			end,
		["sort"] = "dsc",
		["sortnext"]= 6,
		["DoCellUpdate"] = nil,
	}
	cols[6] = {
		["name"] = L["Last Online"],
		["width"] = self.db.profile.columnWidths.lastOnline or 50,
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
		["sortnext"]= 1,
		["sort"] = "dsc",
		["DoCellUpdate"] = nil,
	}
	cols[OPTIONAL_COL] = {
		--["name"] = L["Realm"],
		["width"] = self.db.profile.columnWidths.optional or 50,
		["align"] = "RIGHT",
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
		["sortnext"]= 1,
		["sort"] = "dsc",
		["DoCellUpdate"] = nil,
	}

	--if self.optionalColumn == "TotalXP" then
	cols[OPTIONAL_COL].name = L["Realm"]
	cols[OPTIONAL_COL].align = "LEFT"
	--end

	local table = ScrollingTable:CreateST(cols, 19, nil, nil, guildwindow);

	local headertext = guildwindow:CreateFontString("GS_Main_HeaderText",
		guildwindow, "GameFontNormalLarge")
	headertext:SetPoint("TOP", guildwindow, "TOP", 0, -20)
	headertext:SetText(L["Guild Search"])

	local searchterm = _G.CreateFrame("EditBox", nil, guildwindow, "InputBoxTemplate")
	searchterm:SetFontObject(_G.ChatFontNormal)
	searchterm:SetWidth(300)
	searchterm:SetHeight(35)
	searchterm:SetPoint("TOPLEFT", guildwindow, "TOPLEFT", 30, -50)
	searchterm:SetScript("OnShow", function(this) this:SetFocus() end)
	searchterm:SetScript("OnEnterPressed",
	    function(this)
	        table:SortData()
	        self:UpdateRowCount()
	    end)
	if self.db.profile.hideOnEsc then
		searchterm:SetScript("OnEscapePressed",
		    function(this)
		        this:SetText("")
		        this:GetParent():Hide()
		    end)
	end

	table.frame:SetPoint("TOP", searchterm, "BOTTOM", 0, -20)
	table.frame:SetPoint("LEFT", guildwindow, "LEFT", 25, 0)

	guildwindow.SetSearchTerm = function(input)
		if input then
			guildFrame.searchterm:SetText(input)
		end
    guildFrame.table:SortData()
    GuildSearch:UpdateRowCount()
	end

	local searchbutton = _G.CreateFrame("Button", nil, guildwindow,
		"UIPanelButtonTemplate")
	searchbutton:SetText(L["Search"])
	searchbutton:SetWidth(100)
	searchbutton:SetHeight(20)
	searchbutton:SetPoint("LEFT", searchterm, "RIGHT", 10, 0)
	searchbutton:SetScript("OnClick",
		function(this)
			guildFrame.SetSearchTerm()
		end)

	local clearbutton = _G.CreateFrame("Button", nil, guildwindow,
		"UIPanelButtonTemplate")
	clearbutton:SetText(L["Clear"])
	clearbutton:SetWidth(100)
	clearbutton:SetHeight(20)
	clearbutton:SetPoint("LEFT", searchbutton, "RIGHT", 10, 0)
	clearbutton:SetScript("OnClick",
		function(this)
			guildFrame.SetSearchTerm("")
		end)

	local rowcounttext = guildwindow:CreateFontString(
		"GS_Main_RowCountText", guildwindow, "GameFontNormalSmall")
	rowcounttext:SetPoint("BOTTOMLEFT", guildwindow, "BOTTOMLEFT", 20, 20)

	guildwindow.updateTime = guildwindow:CreateFontString(
		"GS_Main_UpdateTimeText", guildwindow, "GameFontNormalSmall")
	guildwindow.updateTime:SetPoint(
		"BOTTOMRIGHT", guildwindow, "BOTTOMRIGHT", -20, 20)

	local editbutton = _G.CreateFrame("Button", nil, guildwindow, "UIPanelButtonTemplate")
	editbutton:SetText(L["Edit"])
	editbutton:SetWidth(90)
	editbutton:SetHeight(20)
	editbutton:SetPoint("BOTTOM", guildwindow, "BOTTOM", -70, 20)
	editbutton:SetScript("OnClick", 
		function(this)
		    local frame = this:GetParent()
			if frame.table:GetSelection() then
				local row = frame.table:GetRow(frame.table:GetSelection())
				if row[NAME_COL] and #row[NAME_COL] > 0 then
					self:ShowMemberDetails(
					    row[NAME_COL], row[NOTE_COL], 
					    row[ONOTE_COL], row[RANKNUM_COL], row[INDEX_COL])
				end
			end
		end)

	local closebutton = _G.CreateFrame("Button", nil, guildwindow, "UIPanelButtonTemplate")
	closebutton:SetText(L["Close"])
	closebutton:SetWidth(90)
	closebutton:SetHeight(20)
	closebutton:SetPoint("BOTTOM", guildwindow, "BOTTOM", 70, 20)
	closebutton:SetScript("OnClick", function(this) this:GetParent():Hide(); end)

	guildwindow.table = table
	guildwindow.searchterm = searchterm
	guildwindow.rowcount = rowcounttext

	table:EnableSelection(true)

    -- Turn off the mouseover highlighting
	table:RegisterEvents({
		["OnEnter"] = function (rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
			return true;
		end,
		["OnLeave"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, ...)
			return true;
		end
	})

	table:SetFilter(
		function(self, row)
			local term = searchterm:GetText()
			local profile = GuildSearch.db.profile
			if term and #term > 0 then
				term = term:lower()
				local plain = not GuildSearch.db.profile.patternMatching
				if ((profile.searchNames and row[NAME_COL]:lower():find(term,1,plain)) or
					(profile.searchNotes and row[NOTE_COL]:lower():find(term,1,plain)) or
					(profile.searchOfficerNotes and row[ONOTE_COL]:lower():find(term,1,plain)) or 
					(profile.searchRank and row[RANK_COL]:lower():find(term,1,plain)) or			
					(profile.searchClass and row[CLASS_COL]:lower():find(term,1,plain)) or
					(profile.searchRealm and row[REALM_COL]:lower():find(term,1,plain))) then
					return true
				end

				return false
			else
				return true
			end
		end
	)

	guildwindow.lock = self.db.profile.lock_main_window

	guildwindow:SetMovable(true)
	guildwindow:RegisterForDrag("LeftButton")
	guildwindow:SetScript("OnDragStart",
		function(self,button)
			if not self.lock then
				self:StartMoving()
			end
		end)
	guildwindow:SetScript("OnDragStop",
		function(self)
			self:StopMovingOrSizing()
			if GuildSearch.db.profile.remember_main_pos then
				local scale = self:GetEffectiveScale() / _G.UIParent:GetEffectiveScale()
				local x, y = self:GetCenter()
				x, y = x * scale, y * scale
				x = x - _G.GetScreenWidth()/2
				y = y - _G.GetScreenHeight()/2
				x = x / self:GetScale()
				y = y / self:GetScale()
				GuildSearch.db.profile.main_window_x, 
				GuildSearch.db.profile.main_window_y = x, y
				self:SetUserPlaced(false);
			end
		end)
	guildwindow:EnableMouse(true)

	guildwindow:Hide()

	guildwindow:HookScript("OnHide", 
		function(self)
			self:UnregisterEvent("GUILD_ROSTER_UPDATE")
		end)

	return guildwindow
end

local resultsFmt = "%d %s"
local timeFmt = "%s: %s"
function GuildSearch:UpdateRowCount()
    local table = guildFrame.table
    local count = 0
    if table and table.filtered and _G.type(table.filtered) == "table" then
        count = #table.filtered
    end
    
    guildFrame.rowcount:SetText(resultsFmt:format(count, L["results"]))
		local updateText = ""
		if addon.lastUpdate then
			updateText = timeFmt:format(L["Last Update"], 
				_G.date("%H:%M:%S", addon.lastUpdate) or "")
		end
		guildFrame.updateTime:SetText(updateText)
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
