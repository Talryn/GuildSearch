local _G = getfenv(0)

-- Local versions for performance
local tinsert = table.insert
local string = _G.string
local pairs = _G.pairs
local ipairs = _G.ipairs
local type = _G.type

local GuildSearch = _G.LibStub("AceAddon-3.0"):NewAddon("GuildSearch", "AceConsole-3.0", "AceEvent-3.0")
local LibAlts = _G.LibStub("LibAlts-1.0")
local L = _G.LibStub("AceLocale-3.0"):GetLocale("GuildSearch", true)
local AGU = _G.LibStub("AceGUI-3.0")
local LDB = _G.LibStub("LibDataBroker-1.1")
local icon = _G.LibStub("LibDBIcon-1.0")

local ADDON_NAME, addon = ...
local ADDON_VERSION = "@project-version@"

addon.addonName = "Guild Search"
addon.criteria = {
	searchTerm = "",
	oper = 1,
	units = "0",
	mainaltFilter = 1,
}
addon.onlineOperators = {
	">=", 
	"<="
}
addon.mainaltOptions = {
	L["All"],
	L["Mains"],
	L["Alts"],
}

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

function addon.setGuildSource()
	addon.guildSource = LibAlts and addon.guildName and LibAlts.GUILD_PREFIX..addon.guildName or ""
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
local Heights = {
	["default"] = {
		["guildFrame"] = 450,
	},
	["1000"] = {
		["guildFrame"] = 450,
	},		
}

local defaults = {
	profile = {
		minimap = {
			hide = true,
		},
		columnWidths = ColumnWidths["default"],
		heights = Heights["default"],
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
		advanced = false,
	}
}

local guildSearchLDB = nil
local searchTerm = nil
local guildFrame = nil
local guildData = {}
local memberDetailFrame = nil
local bulkUpdateFrame = nil
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
local LASTONLINESECS_COL = 12

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

function GuildSearch:CombatCheck()
	if _G.UnitAffectingCombat("player") then
		self:Print(L["InCombatMessage"])
		return true
	end
	return false
end

function GuildSearch:OnInitialize()
	-- Called when the addon is loaded
	self.db = _G.LibStub("AceDB-3.0"):New("GuildSearchDB", defaults, "Default")
	addon.db = self.db
	self.optionalColumn = self.db.profile.optionalColumn

	-- Register the options table
	_G.LibStub("AceConfig-3.0"):RegisterOptionsTable("GuildSearch", self:GetOptions())
	self.optionsFrame = _G.LibStub("AceConfigDialog-3.0"):AddToBlizOptions(
		"GuildSearch", "Guild Search")

	-- Create the guild frame
	guildFrame = self:CreateGuildFrame()

	-- Register the command line options
	self:RegisterChatCommand("gsearch", "GuildSearchHandler")
	self:RegisterChatCommand("gbulk", "BulkRankUpdate")
	self:RegisterChatCommand("greplace", "SearchReplaceNotes")

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
					if self:CombatCheck() then return end
					_G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
					_G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
				end
			elseif button == "LeftButton" then
				if self:IsWindowVisible() then
					self:HideGuildWindow()
				else
					if self:CombatCheck() then return end
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
	if self:CombatCheck() then return end

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
	bulkUpdateFrame = self:CreateBulkRankUpdateFrame()
	
    addon.guildName = _G.GetGuildInfo("player")
	addon.setGuildSource()
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

		addon.guildName = guildName
		addon.setGuildSource()

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
			elseif not (online and years and months and days and hours) then
				-- If all of these are false/nil then the user is Remote
				lastOnline = _G.time()
				lastOnlineDate = _G.date("%Y/%m/%d %H:%M", lastOnline)
			else
				if self.db.profile.debug then
					local fmt = "Last online not set for %s [%s, %s, %s, %s]"
					self:Print(fmt:format(name, _G.tostring(online), _G.tostring(years), _G.tostring(months),
						_G.tostring(days), _G.tostring(hours)))
				end
			end

			local optional = ""
			optional = charRealm

			tinsert(guildData, 
			    {name, level, note, officernote, rank, lastOnlineDate, 
					optional, charRealm, classFileName, rankIndex, index, lastOnline})
		end
		addon.lastUpdate = _G.time()
	else
		addon.guildName = nil
		addon.guildSource = nil
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

	if update or not addon.lastUpdate then
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

function GuildSearch:BulkRankUpdate()
	if self:CombatCheck() then return end
	if not bulkUpdateFrame then return end
	bulkUpdateFrame:Show()
end

function GuildSearch:BulkUpdateRanks(oldRank, newRank, testing)
	for i = 1, _G.GetNumGuildMembers() do
		local name, rank, rankIndex = _G.GetGuildRosterInfo(i)
		local targetIndex = rankIndex + 1
		if targetIndex == oldRank then
			local allowed, reason = _G.IsGuildRankAssignmentAllowed(i, newRank)
			if allowed then
				if testing then
					self:Print("Updating ".._G.tostring(name))
				else
					_G.SetGuildMemberRank(i, newRank)
				end
			else
				local fmt = "Cannot update %s [%s]"
				self:Print(fmt:format(_G.tostring(name), _G.tostring(reason)))
			end
		end
	end

end

function GuildSearch:SearchReplaceNotes()
	if self:CombatCheck() then return end

    if ReplaceNotesFrame then return end

    local frame = AGU:Create("Frame")
    frame:SetTitle(L["Search"])
    frame:SetWidth(400)
    frame:SetHeight(250)
    frame:SetLayout("Flow")
	frame:SetCallback("OnClose", function(widget)
		widget:ReleaseChildren()
		widget:Release()
		ReplaceNotesFrame = nil
	end)
    ReplaceNotesFrame = frame

    local text =  AGU:Create("Label")
    text:SetText(L["SearchReplaceTitle"])
    --text:SetFont(_G.GameFontNormal:GetFont())
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

    local searchbox = AGU:Create("EditBox")
    searchbox:SetFullWidth(true)
    searchbox:SetText("")
    searchbox:SetLabel(L["Find"])
    searchbox:SetMaxLetters(0)
    searchbox:SetFocus()
    frame:AddChild(searchbox)

    local replacebox = AGU:Create("EditBox")
    replacebox:SetFullWidth(true)
    replacebox:SetText("")
    replacebox:SetLabel(L["Replace"])
    replacebox:SetMaxLetters(0)
    frame:AddChild(replacebox)

    local replaceButton = AGU:Create("Button")
    replaceButton:SetText(L["Replace"])
    replaceButton:SetCallback("OnClick",
        function(widget)
			local search = searchbox:GetText()
			local replace = replacebox:GetText()
            local result = GuildSearch:ReplaceNotes(search, replace, false)
        end)
    frame:AddChild(replaceButton)

    local replaceButton = AGU:Create("Button")
    replaceButton:SetText(L["Test"])
    replaceButton:SetCallback("OnClick",
        function(widget)
			local search = searchbox:GetText()
			local replace = replacebox:GetText()
            local result = GuildSearch:ReplaceNotes(search, replace, true)
			frame:Hide()
        end)
    frame:AddChild(replaceButton)
	
end

function GuildSearch:ReplaceNotes(search, replace, testing)
	for i = 1, _G.GetNumGuildMembers() do
		local name, rank, rankIndex, level, class, zone, note, onote = _G.GetGuildRosterInfo(i)
		if note and note ~= "" then
			local result = note:gsub(search, replace)
			if result and note ~= result then
				if testing then
					local fmt = "Updating public note for %s from '%s' to '%s'."
					self:Print(fmt:format(name, note, result))
				else
					_G.GuildRosterSetPublicNote(i, result)
				end
			end
		end
		if onote and onote ~= "" then
			local result = onote:gsub(search, replace)
			if result and onote ~= result then
				if testing then
					local fmt = "Updating officer note for %s from '%s' to '%s'."
					self:Print(fmt:format(name, onote, result))
				else
					_G.GuildRosterSetOfficerNote(i, result)
				end
			end
		end
	end
end

function GuildSearch:VerifyBulkUpdateRanks(oldRank, newRank)
    _G.StaticPopupDialogs["GUILDSEARCH_BULK_UPDATE"] = _G.StaticPopupDialogs["GUILDSEARCH_BULK_UPDATE"] or {
        text = "Are you sure you want to move members from %s to %s?",
		oldRank = 0,
        newRank = 0,
		showAlert = true,
        button1 = _G.YES,
        button2 = _G.CANCEL,
		button3 = L["Test"],
        hasEditBox = false,
        hasWideEditBox = false,
        enterClicksFirstButton = false,
        OnAccept = function(this)
            self:BulkUpdateRanks(oldRank, newRank, false)
        end,
        OnAlt = function(this)
            self:BulkUpdateRanks(oldRank, newRank, true)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true
    }

	local highestRank = 2
	local lowestRank = _G.GuildControlGetNumRanks()
	if oldRank >= highestRank and oldRank <= lowestRank and 
		newRank >= highestRank and newRank <= lowestRank then
	    _G.StaticPopupDialogs["GUILDSEARCH_BULK_UPDATE"].OnAccept = function(this)
            self:BulkUpdateRanks(oldRank, newRank, false)
        end
	    _G.StaticPopupDialogs["GUILDSEARCH_BULK_UPDATE"].OnAlt = function(this)
            self:BulkUpdateRanks(oldRank, newRank, true)
        end
	    local oldRankText = _G.GuildControlGetRankName(oldRank) or ""
	    local newRankText = _G.GuildControlGetRankName(newRank) or ""
	    _G.StaticPopup_Show("GUILDSEARCH_BULK_UPDATE", oldRankText, newRankText)
	end
end

function GuildSearch:CreateBulkRankUpdateFrame()
	local rankwindow = _G.CreateFrame("Frame", "GuildSearch_RankUpdateWindow", _G.UIParent)
	rankwindow:SetFrameStrata("DIALOG")
	rankwindow:SetToplevel(true)
	rankwindow:SetWidth(350)
	rankwindow:SetHeight(180)
	rankwindow:SetPoint("CENTER", _G.UIParent)
	rankwindow:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	rankwindow:SetBackdropColor(0,0,0,1)

	local savebutton = _G.CreateFrame("Button", nil, rankwindow, "UIPanelButtonTemplate")
	savebutton:SetText(L["Save"])
	savebutton:SetWidth(100)
	savebutton:SetHeight(20)
	savebutton:SetPoint("BOTTOM", rankwindow, "BOTTOM", -60, 20)
	savebutton:SetScript("OnClick",
	    function(this)
	        local frame = this:GetParent()
            local oldRank = _G.UIDropDownMenu_GetSelectedValue(frame.oldRankDropdown)
            local newRank = _G.UIDropDownMenu_GetSelectedValue(frame.newRankDropdown)
	        self:VerifyBulkUpdateRanks(oldRank, newRank)
	        frame:Hide()
	    end)

	local cancelbutton = _G.CreateFrame("Button", nil, rankwindow, "UIPanelButtonTemplate")
	cancelbutton:SetText(L["Cancel"])
	cancelbutton:SetWidth(100)
	cancelbutton:SetHeight(20)
	cancelbutton:SetPoint("BOTTOM", rankwindow, "BOTTOM", 60, 20)
	cancelbutton:SetScript("OnClick", function(this) this:GetParent():Hide(); end)

	local headertext = rankwindow:CreateFontString("GS_HeaderText", nil, "GameFontNormalLarge")
	headertext:SetPoint("TOP", rankwindow, "TOP", 0, -20)
	headertext:SetText(L["Guild Bulk Rank Update"])

    local oldRankLabel = rankwindow:CreateFontString("GS_OldRankLabel", nil, "GameFontNormal")
	oldRankLabel:SetPoint("TOP", headertext, "BOTTOM", 0, -20)
	oldRankLabel:SetPoint("LEFT", rankwindow, "LEFT", 20, 0)
	--rankLabel:SetFont(rankLabel:GetFont(), 14)
	--rankLabel:SetTextColor(1.0,1.0,1.0,1)
	oldRankLabel:SetText(L["Old Rank"]..":")

    local oldRankDropdown = _G.CreateFrame("Button", "GS_OldRankDropDown", rankwindow, "UIDropDownMenuTemplate")
    oldRankDropdown:ClearAllPoints()
    oldRankDropdown:SetPoint("TOPLEFT", oldRankLabel, "TOPRIGHT", 7, 5)
    oldRankDropdown:Show()
    _G.UIDropDownMenu_Initialize(oldRankDropdown, function(self, level)
        -- The following code is partially copied from Blizzard's code
        -- in Blizzard_GuildRoster.lua
        local numRanks = _G.GuildControlGetNumRanks()
        -- Get the user's rank and adjust to 1-based
        local _, _, userRankIndex = _G.GetGuildInfo("player")
        userRankIndex = userRankIndex + 1
        -- Set the highest rank to 1 above the user's rank
        local highestRank = userRankIndex + 1
        -- If the user cannot promote, the highest rank is the current member's rank
        --if (not _G.CanGuildPromote()) or userRankIndex >= memberRankIndex then
        --    highestRank = memberRankIndex
        --end
        local lowestRank = numRanks
        --if (not _G.CanGuildDemote()) or userRankIndex >= memberRankIndex then
        --    lowestRank = memberRankIndex
        --end

        for i = highestRank, lowestRank do
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text = _G.GuildControlGetRankName(i)
            info.value = i
            info.arg1 = i
            info.colorCode = WHITE
            info.checked = false -- i == lowestRank + 1
            info.func = function(self) 
                _G.UIDropDownMenu_SetSelectedValue(oldRankDropdown, self.value)
            end
            _G.UIDropDownMenu_AddButton(info, level)
        end
    end)
    _G.UIDropDownMenu_SetWidth(oldRankDropdown, 100);
    _G.UIDropDownMenu_SetButtonWidth(oldRankDropdown, 124)
    _G.UIDropDownMenu_SetSelectedValue(oldRankDropdown, 0)
    _G.UIDropDownMenu_JustifyText(oldRankDropdown, "LEFT")

    local newRankLabel = rankwindow:CreateFontString("GS_NewRankLabel", nil, "GameFontNormal")
	newRankLabel:SetPoint("TOP", oldRankLabel, "BOTTOM", 0, -20)
	newRankLabel:SetPoint("LEFT", rankwindow, "LEFT", 20, 0)
	--rankLabel:SetFont(rankLabel:GetFont(), 14)
	--rankLabel:SetTextColor(1.0,1.0,1.0,1)
	newRankLabel:SetText(L["New Rank"]..":")

    local newRankDropdown = _G.CreateFrame("Button", "GS_NewRankDropDown", rankwindow, "UIDropDownMenuTemplate")
    newRankDropdown:ClearAllPoints()
    newRankDropdown:SetPoint("TOPLEFT", newRankLabel, "TOPRIGHT", 7, 5)
    newRankDropdown:Show()
    _G.UIDropDownMenu_Initialize(newRankDropdown, function(self, level)
        -- The following code is partially copied from Blizzard's code
        -- in Blizzard_GuildRoster.lua
        local numRanks = _G.GuildControlGetNumRanks()
        -- Get the user's rank and adjust to 1-based
        local _, _, userRankIndex = _G.GetGuildInfo("player")
        userRankIndex = userRankIndex + 1
        -- Set the highest rank to 1 above the user's rank
        local highestRank = userRankIndex + 1
        -- If the user cannot promote, the highest rank is the current member's rank
        --if (not _G.CanGuildPromote()) or userRankIndex >= memberRankIndex then
        --    highestRank = memberRankIndex
        --end
        local lowestRank = numRanks
        --if (not _G.CanGuildDemote()) or userRankIndex >= memberRankIndex then
        --    lowestRank = memberRankIndex
        --end

        for i = highestRank, lowestRank do
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text = _G.GuildControlGetRankName(i)
            info.value = i
            info.arg1 = i
            info.colorCode = WHITE
            info.checked = false --i == lowestRank
            info.func = function(self) 
                _G.UIDropDownMenu_SetSelectedValue(newRankDropdown, self.value)
            end
            _G.UIDropDownMenu_AddButton(info, level)
        end
    end)
    _G.UIDropDownMenu_SetWidth(newRankDropdown, 100);
    _G.UIDropDownMenu_SetButtonWidth(newRankDropdown, 124)
    _G.UIDropDownMenu_SetSelectedValue(newRankDropdown, 0)
    _G.UIDropDownMenu_JustifyText(newRankDropdown, "LEFT")

	rankwindow.newRankDropdown = newRankDropdown
	rankwindow.oldRankDropdown = oldRankDropdown

    rankwindow:SetMovable(true)
    rankwindow:RegisterForDrag("LeftButton")
    rankwindow:SetScript("OnDragStart",
        function(this,button)
        	this:StartMoving()
        end)
    rankwindow:SetScript("OnDragStop",
        function(this)
            this:StopMovingOrSizing()
        end)
    rankwindow:EnableMouse(true)

	rankwindow:Hide()

	return rankwindow

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

	local headertext = detailwindow:CreateFontString("GS_HeaderText", nil, "GameFontNormalLarge")
	headertext:SetPoint("TOP", detailwindow, "TOP", 0, -20)
	headertext:SetText(L["Guild Member Details"])

	local charname = detailwindow:CreateFontString("GS_CharName", nil, "GameFontNormal")
	charname:SetPoint("BOTTOM", headertext, "BOTTOM", 0, -40)
	charname:SetFont(charname:GetFont(), 14)
	charname:SetTextColor(1.0,1.0,1.0,1)

    local rankLabel = detailwindow:CreateFontString("GS_RankLabel", nil, "GameFontNormal")
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

	local noteHeader = detailwindow:CreateFontString("GS_NoteHeaderText", nil, "GameFontNormal")
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

	local onoteHeader = detailwindow:CreateFontString("GS_OfficerNoteHeaderText", nil, "GameFontNormal")
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
	guildFrame = guildwindow
	guildwindow:SetFrameStrata("DIALOG")
	guildwindow:SetToplevel(true)
	guildwindow:SetWidth(self.db.profile.columnWidths.window)
	guildwindow:SetHeight(self.db.profile.heights.guildFrame)

	guildwindow.SetBasicHeight = function(self)
		self:ClearAdvancedSearch()
		self:SetHeight(addon.db.profile.heights.guildFrame)
		self.advancedOptions:Hide()
		self.table.frame:ClearAllPoints()
		self.table.frame:SetPoint("TOP", self.searchterm, "BOTTOM", 0, -25)
		self.table.frame:SetPoint("LEFT", self, "LEFT", 25, 0)
		self.advancedbutton:SetText(L["Advanced"])
	end

	guildwindow.SetAdvancedHeight = function(self)
		self:SetHeight(addon.db.profile.heights.guildFrame + 35)
		self.advancedOptions:Show()
		self.table.frame:ClearAllPoints()
		self.table.frame:SetPoint("TOP", self.advancedOptions, "BOTTOM", 0, -20)
		self.table.frame:SetPoint("LEFT", self, "LEFT", 25, 0)
		self.advancedbutton:SetText(L["Basic"])
	end

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

	cols[OPTIONAL_COL].name = L["Realm"]
	cols[OPTIONAL_COL].align = "LEFT"

	guildwindow.SortData = function(this)
		addon.criteria.searchTerm = guildFrame.searchterm:GetText() or ""
		addon.criteria.oper = _G.UIDropDownMenu_GetSelectedValue(guildFrame.onlineOper) or 1
		addon.criteria.units = _G.tonumber(guildFrame.onlineUnits:GetText()) or 0
	    guildFrame.table:SortData()
	    GuildSearch:UpdateRowCount()
	end

	guildwindow.SetSearchTerm = function(input)
		if input then
			guildFrame.searchterm:SetText(input)
		end
    	guildFrame.SortData()
	end

	guildwindow.ClearSearchTerm = function(this)
        guildFrame.searchterm:SetText("")
		guildFrame.ClearAdvancedSearch()
	end

	guildwindow.ClearAdvancedSearch = function(this)
		guildFrame.onlineUnits:SetText("0")
		addon.criteria.oper = 1
		addon.criteria.mainaltFilter = 1
		_G.UIDropDownMenu_SetText(guildFrame.onlineOper, addon.onlineOperators[1])
		guildFrame.onlineOper.selectedValue = 1
		_G.UIDropDownMenu_SetText(guildFrame.mainaltFilter, addon.mainaltOptions[1])
		guildFrame.mainaltFilter.selectedValue = 1
		--_G.UIDropDownMenu_SetSelectedValue(guildFrame.onlineOper, 1)
		--_G.UIDropDownMenu_SetSelectedValue(guildFrame.mainaltFilter, 1)
	end

	local table = ScrollingTable:CreateST(cols, 19, nil, nil, guildwindow);

	local headertext = guildwindow:CreateFontString("GS_Main_HeaderText", nil, "GameFontNormalLarge")
	headertext:SetPoint("TOP", guildwindow, "TOP", 0, -20)
	headertext:SetText(L["Guild Search"])

	local searchterm = _G.CreateFrame("EditBox", nil, guildwindow, "InputBoxTemplate")
	searchterm:SetFontObject(_G.ChatFontNormal)
	searchterm:SetWidth(300)
	searchterm:SetHeight(35)
	searchterm:SetPoint("TOPLEFT", guildwindow, "TOPLEFT", 30, -50)
	searchterm:SetScript("OnShow", function(this) this:SetFocus() end)
	searchterm:SetScript("OnEnterPressed", guildwindow.SortData)
	if self.db.profile.hideOnEsc then
		searchterm:SetScript("OnEscapePressed",
		    function(this)
		        guildFrame:ClearSearchTerm()
		        guildFrame:Hide()
		    end)
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
			guildFrame.ClearSearchTerm()
			guildFrame.SortData()
		end)

	guildwindow.UpdateAdvancedSearch = function(self)
		if addon.db.profile.advanced then
			self:SetAdvancedHeight()
		else
			self:SetBasicHeight()
		end			
	end
		
	local advancedbutton = _G.CreateFrame("Button", nil, guildwindow,
		"UIPanelButtonTemplate")
	advancedbutton:SetText(L["Advanced"])
	advancedbutton:SetWidth(100)
	advancedbutton:SetHeight(20)
	advancedbutton:SetPoint("LEFT", clearbutton, "RIGHT", 10, 0)
	advancedbutton:SetScript("OnClick",
		function(this)
			addon.db.profile.advanced = not addon.db.profile.advanced
			guildFrame:UpdateAdvancedSearch()
		end)

	local advancedOptions = _G.CreateFrame("Frame", "GuildSearchWindow_AdvOpts", guildwindow)
	advancedOptions:SetHeight(35)
	advancedOptions:SetWidth(self.db.profile.columnWidths.window - 10)
	advancedOptions:SetPoint("TOPLEFT", searchterm, "BOTTOMLEFT", 0, 0)
	--advancedOptions:SetPoint("RIGHT", guildwindow, "RIGHT")

	table.frame:SetPoint("TOP", searchterm, "BOTTOM", 0, -20)
	table.frame:SetPoint("LEFT", guildwindow, "LEFT", 25, 0)

	local onlineHeader = advancedOptions:CreateFontString("GS_OnlineHdrText", nil, "GameFontNormal")
	onlineHeader:SetPoint("LEFT", advancedOptions, "LEFT", 0, 0)
	onlineHeader:SetText(L["Last Online"])

    local onlineOper = _G.CreateFrame("Button", "GS_OnlineOperDropDown", advancedOptions, "UIDropDownMenuTemplate")
    onlineOper:ClearAllPoints()
    onlineOper:SetPoint("LEFT", onlineHeader, "RIGHT", 10, 0)
    onlineOper:Show()
    onlineOper.initializeFunc = function(self, level)
		local setOperValue = function(self)
			addon.criteria.oper = self.value
        	_G.UIDropDownMenu_SetSelectedValue(onlineOper, self.value)
			guildFrame.SortData()
       	end
		local isChecked = function(self)
			return addon.criteria.oper == self.value
		end
        for i, op in ipairs(addon.onlineOperators) do
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text = op
            info.value = i
            info.arg1 = i
            info.colorCode = WHITE
            info.checked = isChecked
            info.func = setOperValue
            _G.UIDropDownMenu_AddButton(info, level)
        end
    end
	_G.UIDropDownMenu_Initialize(onlineOper, onlineOper.initializeFunc)
    _G.UIDropDownMenu_SetWidth(onlineOper, 50);
    _G.UIDropDownMenu_SetButtonWidth(onlineOper, 70)
    _G.UIDropDownMenu_SetSelectedValue(onlineOper, 1)
    _G.UIDropDownMenu_JustifyText(onlineOper, "LEFT")

	local onlineUnits = _G.CreateFrame("EditBox", nil, advancedOptions, "InputBoxTemplate")
	onlineUnits:SetFontObject(_G.ChatFontNormal)
	onlineUnits:SetWidth(40)
	onlineUnits:SetHeight(35)
	onlineUnits:SetPoint("LEFT", onlineOper, "RIGHT", 10, 0)
	onlineUnits:SetNumeric(true)
	onlineUnits:SetText("0")
	onlineUnits:SetScript("OnEnterPressed", guildwindow.SortData)
	if self.db.profile.hideOnEsc then
		onlineUnits:SetScript("OnEscapePressed",
		    function(this)
		        guildFrame:ClearSearchTerm()
		        guildFrame:Hide()
		    end)
	end

	local unitHeader = advancedOptions:CreateFontString("GS_OnlineUnitText", nil, "GameFontNormal")
	unitHeader:SetPoint("LEFT", onlineUnits, "RIGHT", 10, 0)
	unitHeader:SetText(L["days"])

	local mainaltHeader = advancedOptions:CreateFontString("GS_MainAltHdrText", nil, "GameFontNormal")
	mainaltHeader:SetPoint("LEFT", unitHeader, "RIGHT", 20, 0)
	mainaltHeader:SetText(L["Main/Alt"])

    local mainaltFilter = _G.CreateFrame("Button", "GS_MainAltDropDown", advancedOptions, "UIDropDownMenuTemplate")
    mainaltFilter:ClearAllPoints()
    mainaltFilter:SetPoint("LEFT", mainaltHeader, "RIGHT", 0, 0)
    mainaltFilter:Show()
    mainaltFilter.initializeFunc = function(self, level)
		local setValue = function(self) 
			addon.criteria.mainaltFilter = self.value
        	_G.UIDropDownMenu_SetSelectedValue(mainaltFilter, self.value)
			guildFrame.SortData()
       	end
		local isChecked = function(self)
			return addon.criteria.mainaltFilter == self.value
		end
        for i, opt in ipairs(addon.mainaltOptions) do
            local info = _G.UIDropDownMenu_CreateInfo()
            info.text = opt
            info.value = i
            info.arg1 = i
            info.colorCode = WHITE
            info.checked = isChecked
            info.func = setValue
            _G.UIDropDownMenu_AddButton(info, level)
        end
    end
	_G.UIDropDownMenu_Initialize(mainaltFilter, mainaltFilter.initializeFunc)
    _G.UIDropDownMenu_SetWidth(mainaltFilter, 90);
    _G.UIDropDownMenu_SetButtonWidth(mainaltFilter, 110)
    _G.UIDropDownMenu_SetSelectedValue(mainaltFilter, 1)
    _G.UIDropDownMenu_JustifyText(mainaltFilter, "LEFT")

	if not LibAlts then
		mainaltHeader:Hide()
		mainaltFilter:Hide()
	end

	local rowcounttext = guildwindow:CreateFontString(
		"GS_Main_RowCountText", nil, "GameFontNormalSmall")
	rowcounttext:SetPoint("BOTTOMLEFT", guildwindow, "BOTTOMLEFT", 20, 20)

	guildwindow.updateTime = guildwindow:CreateFontString(
		"GS_Main_UpdateTimeText", nil, "GameFontNormalSmall")
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
	guildwindow.onlineUnits = onlineUnits
	guildwindow.onlineOper = onlineOper
	guildwindow.advancedOptions = advancedOptions
	guildwindow.advancedbutton = advancedbutton
	guildwindow.mainaltFilter = mainaltFilter

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
		    addon.guildName = _G.GetGuildInfo("player")
		    addon.guildSource = addon.guildSource or ""
			addon.criteria.searchTerm = guildFrame.searchterm:GetText() or ""
			addon.criteria.oper = addon.criteria.oper or 1
			addon.criteria.units = _G.tonumber(guildFrame.onlineUnits:GetText()) or 0
			for name, func in pairs(addon.SearchCriteria) do
				if func and type(func) == "function" then
					if not func(self, row) then return false end
				end
			end
			return true
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

	guildwindow:UpdateAdvancedSearch()

	guildwindow:Hide()

	guildwindow:HookScript("OnHide", 
		function(self)
			self:UnregisterEvent("GUILD_ROSTER_UPDATE")
		end)

	return guildwindow
end

addon.SearchColumns = {
	["searchNames"] = NAME_COL,
	["searchNotes"] = NOTE_COL,
	["searchOfficerNotes"] = ONOTE_COL,
	["searchRank"] = RANK_COL,
	["searchClass"] = CLASS_COL,
	["searchRealm"] = REALM_COL,
}

addon.SearchCriteria = {
	["Basic Search"] = function(table, row)
		local term = addon.criteria.searchTerm
		local profile = addon.db.profile
		if term and #term > 0 then
			term = term:lower()
			local plain = not profile.patternMatching
			for var, col in pairs(addon.SearchColumns) do
				if profile[var] and row[col]:lower():find(term, 1, plain) then
					return true
				end
			end
			return false
		else
			return true
		end
	end,
	["Last Online"] = function(table, row)
		local oper = addon.criteria.oper
		local units = addon.criteria.units
		if units and units > 0 and (oper == 1 or oper == 2) then
			local days = (_G.time() - row[LASTONLINESECS_COL]) / 86400
			if oper == 1 then
				return days >= units
			else
				return days <= units
			end
		else
			return true
		end 
	end,
	["Main/Alt"] = function(table, row)
		if not LibAlts then return true end
		local filter = addon.criteria.mainaltFilter
		if filter == 2 then
			return not LibAlts:IsAltForSource(row[NAME_COL], addon.guildSource)
			--return LibAlts:IsMainForSource(row[NAME_COL], addon.guildSource)
		elseif filter == 3 then
			return LibAlts:IsAltForSource(row[NAME_COL], addon.guildSource)
		else
			return true
		end 
	end
}

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
