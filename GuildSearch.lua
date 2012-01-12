local GuildSearch = LibStub("AceAddon-3.0"):NewAddon("GuildSearch", "AceConsole-3.0", "AceEvent-3.0")

local ADDON_NAME = ...
local ADDON_VERSION = "@project-version@"

-- Local versions for performance
local tinsert = table.insert

local L = LibStub("AceLocale-3.0"):GetLocale("GuildSearch", true)
local AGU = LibStub("AceGUI-3.0")
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
		verbose = false,
		searchNames = true,
		searchNotes = true,
		searchOfficerNotes = true,
		searchRank = false,
		searchClass = false,
		patternMatching = false,
		remember_main_pos = true,
		lock_main_window = false,
		main_window_x = 0,
		main_window_y = 0,
	}
}

local guildSearchLDB = nil
local searchTerm = nil
local guildFrame = nil
local guildData = {}
local memberDetailFrame = nil
local guildRanks = {}

local NAME_COL = 1
local NOTE_COL = 3
local ONOTE_COL = 4
local RANK_COL = 5
local LASTONLINE_COL = 6
local RANKNUM_COL = 8
local INDEX_COL = 9

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

            }
        }
    end

    return options
end

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

	-- Register to get the ranks event
	self:RegisterEvent("GUILD_RANKS_UPDATE")
	
	memberDetailFrame = self:CreateMemberDetailsFrame()
end

function GuildSearch:OnDisable()
    -- Called when the addon is disabled
	self:UnregisterEvent("GUILD_ROSTER_UPDATE")

    -- Called when the addon is disabled
	self:UnregisterEvent("GUILD_RANKS_UPDATE")
end

function GuildSearch:PopulateGuildRanks()
    local numRanks = GuildControlGetNumRanks()
    local name

    wipe(guildRanks)

    for i = 1, numRanks do
        name = GuildControlGetRankName(i)
        guildRanks[i] = name
    end

    self:RefreshMemberDetails()
end

function GuildSearch:PopulateGuildData()
	wipe(guildData)
	
	if IsInGuild() then
		local numMembers = GetNumGuildMembers()
		for index = 1, numMembers do
			local name, rank, rankIndex, level, class, zone, note, 
				officernote, online, status, classFileName = GetGuildRosterInfo(index)

                local years, months, days, hours = GetGuildRosterLastOnline(index)
                local lastOnline = 0
                local lastOnlineDate = ""
                if online then
                    lastOnline = time()
                    lastOnlineDate = date("%Y/%m/%d %H:%M", lastOnline)
                elseif years and months and days and hours then
                    local diff = (((years*365)+(months*30)+days)*24+hours)*60*60
                    lastOnline = time() - diff
                    lastOnlineDate = date("%Y/%m/%d %H:00", lastOnline)
                end

				tinsert(guildData, 
				    {name,level,note,officernote,rank,
				     lastOnlineDate, classFileName, rankIndex, index})
		end
	end

    self:RefreshMemberDetails()

	-- Update the guild data now
	if guildFrame and guildFrame.table then
		guildFrame.table:SetData(guildData, true)
		self:UpdateRowCount()
	end
end

function GuildSearch:GUILD_RANKS_UPDATE(event, ...)
    self:PopulateGuildRanks()
end

function GuildSearch:GUILD_ROSTER_UPDATE(event, ...)
    local arg1 = ...
    if (arg1) then
        -- Clear the current selection in the window as it will change
        if guildFrame and guildFrame.table then
            guildFrame.table:ClearSelection()
        end
        GuildRoster()
    end
	self:PopulateGuildData()
end

local invalidRankFmt = "Attempt to set member rank to an invalid rank. (%s)"
local changingRankFmt = "Changing rank for %s from %s to %s."
local noRankFoundFmt = "Invalid rank returned for roster id. (%s)"
function GuildSearch:UpdateMemberDetail(name, publicNote, officerNote, newRankIndex)
	if not IsInGuild() or name == nil or #name == 0 then
        return false
    end

	local numMembers = GetNumGuildMembers()
	local i = 0
	local charname, rank, rankIndex, level, class, zone, note, 
		officernote, online, status, classFileName

    while name ~= charname and i < numMembers do
        i = i + 1
		charname, rank, rankIndex, level, class, zone, note, officernote,
			online, status, classFileName = GetGuildRosterInfo(i)
	end
    
    if name == charname and i > 0 then
        if publicNote and CanEditPublicNote() then
            GuildRosterSetPublicNote(i, publicNote)
        end

        if officerNote and CanEditOfficerNote() then
            GuildRosterSetOfficerNote(i, officerNote)
        end

        if newRankIndex then
            newRankIndex = newRankIndex + 1

            local numRanks = GuildControlGetNumRanks()
            if newRankIndex < 0 or newRankIndex > numRanks then
                GuildSearch:Print(invalidRankFmt:format(newRankIndex or "nil"))
                return
            end

            if rankIndex then
                rankIndex = rankIndex + 1
                if rankIndex ~= newRankIndex then
                    if GuildSearch.db.profile.verbose then
                        GuildSearch:Print(
                            changingRankFmt:format(charname, rankIndex, newRankIndex))
                    end
                    SetGuildMemberRank(i, newRankIndex)
                end
            else
                GuildSearch:Print(noRankFoundFmt:format(i))
            end
        end
    end
end

function GuildSearch:RemoveGuildMember(name)
    if CanGuildRemove() then
        GuildUninvite(name)
        memberDetailFrame:Hide()
    end
end

function GuildSearch:StaticPopupRemoveGuildMember(name)
	StaticPopupDialogs["GuildSearch_RemoveGuildMember"] = 
	    StaticPopupDialogs["GuildSearch_RemoveGuildMember"] or {
					text = L["GUILD_REMOVE_CONFIRMATION"], 
					button1 = ACCEPT, 
					button2 = CANCEL,
					whileDead = true,
					hideOnEscape = true,
					showAlert = true,
					timeout = 0,
                    enterClicksFirstButton = false,
					OnAccept = function(self, data) 
					    GuildSearch:RemoveGuildMember(data)
					end,
				}
    local dialog = StaticPopup_Show("GuildSearch_RemoveGuildMember", name)
    if dialog then
        dialog.data = name
    end
end

function GuildSearch:CreateMemberDetailsFrame()
	local detailwindow = CreateFrame("Frame", "GuildSearch_DetailsWindow", UIParent)
	detailwindow:SetFrameStrata("DIALOG")
	detailwindow:SetToplevel(true)
	detailwindow:SetWidth(400)
	detailwindow:SetHeight(320)
	detailwindow:SetPoint("CENTER", UIParent)
	detailwindow:SetBackdrop(
		{bgFile="Interface\\ChatFrame\\ChatFrameBackground", 
	    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", tile=true,
		tileSize=32, edgeSize=32, insets={left=11, right=12, top=12, bottom=11}})
	detailwindow:SetBackdropColor(0,0,0,1)

    detailwindow.name = ""
	detailwindow.memberRank = 1
	detailwindow.index = 0

	local savebutton = CreateFrame("Button", nil, detailwindow, "UIPanelButtonTemplate")
	savebutton:SetText(L["Save"])
	savebutton:SetWidth(100)
	savebutton:SetHeight(20)
	savebutton:SetPoint("BOTTOM", detailwindow, "BOTTOM", -60, 20)
	savebutton:SetScript("OnClick",
	    function(this)
	        local frame = this:GetParent()
	        local publicNote = frame.publicnote:GetText()
	        local officerNote = frame.officernote:GetText()
            local rank = UIDropDownMenu_GetSelectedID(frame.rankDropdown)
	        self:UpdateMemberDetail(
	            frame.charname:GetText(), publicNote, officerNote, rank)
	        frame:Hide()
	    end)

	local cancelbutton = CreateFrame("Button", nil, detailwindow, "UIPanelButtonTemplate")
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

    local rankDropdown = CreateFrame("Button", "GS_RankDropDown", detailwindow, "UIDropDownMenuTemplate")
    rankDropdown:ClearAllPoints()
    rankDropdown:SetPoint("TOPLEFT", rankLabel, "TOPRIGHT", 7, 5)
    rankDropdown:Show()
    UIDropDownMenu_Initialize(rankDropdown, function(self, level)
        -- The following code is partially copied from Blizzard's code
        -- in Blizzard_GuildRoster.lua

        local numRanks = GuildControlGetNumRanks()
        -- Get the user's rank and adjust to 1-based
        local _, _, userRankIndex = GetGuildInfo("player")
        userRankIndex = userRankIndex + 1
        -- The current member's rank
        local memberRankIndex = self:GetParent().memberRank

        -- Set the highest rank to 1 above the user's rank
        local highestRank = userRankIndex + 1
        -- If the user cannot promote, the highest rank is the current member's rank
        if not CanGuildPromote() then
            highestRank = memberRankIndex
        end
        
        local lowestRank = numRanks
        if not CanGuildDemote() then
            lowestRank = memberRankIndex
        end

        for i = highestRank, lowestRank do
            local info = UIDropDownMenu_CreateInfo()
            info.text = GuildControlGetRankName(i)
            info.value = i
            info.arg1 = i
            info.colorCode = WHITE
            info.checked = i == memberRankIndex
            info.func = function(self) 
                UIDropDownMenu_SetSelectedValue(rankDropdown, self.value)
            end
            -- If not the current rank, then check if the rank is allowed to be set
            -- In addition to rank restrictions, an authenticator can prohibit too
            if not info.checked then
                local allowed, reason = 
                    IsGuildRankAssignmentAllowed(memberRankIndex, i);
                if not allowed and reason == "authenticator" then
                    info.disabled = true;
                    info.tooltipWhileDisabled = 1;
                    info.tooltipTitle = GUILD_RANK_UNAVAILABLE;
                    info.tooltipText = GUILD_RANK_UNAVAILABLE_AUTHENTICATOR;
                    info.tooltipOnButton = 1;
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetWidth(rankDropdown, 100);
    UIDropDownMenu_SetButtonWidth(rankDropdown, 124)
    UIDropDownMenu_SetSelectedValue(rankDropdown, 0)
    UIDropDownMenu_JustifyText(rankDropdown, "LEFT")

	local removebutton = CreateFrame("Button", nil, detailwindow, "UIPanelButtonTemplate")
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

    local publicNoteContainer = CreateFrame("Frame", nil, detailwindow)
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

    local noteScrollArea = CreateFrame("ScrollFrame", "GS_MemberDetails_PublicNoteScroll", detailwindow, "UIPanelScrollFrameTemplate")
    noteScrollArea:SetPoint("TOPLEFT", publicNoteContainer, "TOPLEFT", 6, -6)
    noteScrollArea:SetPoint("BOTTOMRIGHT", publicNoteContainer, "BOTTOMRIGHT", -6, 6)

	local notebox = CreateFrame("EditBox", "GS_MemberDetails_PublicNoteBox", detailwindow)
	notebox:SetFontObject(ChatFontNormal)
	notebox:SetMultiLine(true)
	notebox:SetAutoFocus(true)
	notebox:SetWidth(300)
	notebox:SetHeight(2*14)
	notebox:SetMaxLetters(0)
	notebox:SetScript("OnShow", function(this) notebox:SetFocus() end)
	notebox:SetScript("OnEscapePressed",
	    function(this)
	        this:SetText("")
	        this:GetParent():GetParent():Hide()
	    end)
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

    local officerNoteContainer = CreateFrame("Frame", nil, detailwindow)
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

    local onoteScrollArea = CreateFrame("ScrollFrame", "GS_MemberDetails_OfficerNoteScroll", detailwindow, "UIPanelScrollFrameTemplate")
    onoteScrollArea:SetPoint("TOPLEFT", officerNoteContainer, "TOPLEFT", 6, -6)
    onoteScrollArea:SetPoint("BOTTOMRIGHT", officerNoteContainer, "BOTTOMRIGHT", -6, 6)

	local onotebox = CreateFrame("EditBox", "GS_MemberDetails_OfficerNoteBox", detailwindow)
	onotebox:SetFontObject(ChatFontNormal)
	onotebox:SetMultiLine(true)
	onotebox:SetAutoFocus(true)
	onotebox:SetWidth(300)
	onotebox:SetHeight(2*14)
	onotebox:SetMaxLetters(0)
	--onotebox:SetScript("OnShow", function(this) onotebox:SetFocus() end)
	onotebox:SetScript("OnEscapePressed",
	    function(this)
	        this:SetText("")
	        this:GetParent():GetParent():Hide()
	    end)
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

    detailwindow:SetMovable()
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
		EditNoteFrame = nil
	end)
    MemberDetailsFrame = frame

    local text =  AGU:Create("Label")
    text:SetText(name)
    text:SetFont(GameFontNormalLarge:GetFont())
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
    notebox:SetText(note)
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
    onotebox:SetText(note)
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
    	UIDropDownMenu_SetSelectedValue(memberDetailFrame.rankDropdown, memberRankIndex)
    	if guildRanks[memberRankIndex] then
            UIDropDownMenu_SetText(
                memberDetailFrame.rankDropdown, WHITE..guildRanks[memberRankIndex].."|r")
        end

        local _, _, userRankIndex = GetGuildInfo("player")

        if rank <= userRankIndex then
            -- Disable since you cannot change an equal or higher ranked char.
            memberDetailFrame.rankDropdown:Disable()
        elseif CanGuildPromote() or CanGuildDemote() then
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

            if CanEditPublicNote() then
                detailwindow.publicnote:Enable()
            else
                detailwindow.publicnote:Disable()
            end

            if CanEditOfficerNote() then
                detailwindow.officernote:Enable()
            else
                detailwindow.officernote:Disable()
            end

            if CanGuildRemove() then
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

function GuildSearch:CreateGuildFrame()
	local guildwindow = CreateFrame("Frame", "GuildSearchWindow", UIParent)
	guildwindow:SetFrameStrata("DIALOG")
	guildwindow:SetToplevel(true)
	guildwindow:SetWidth(700)
	guildwindow:SetHeight(450)

	if self.db.profile.remember_main_pos then
        guildwindow:SetPoint("CENTER", UIParent, "CENTER",
            self.db.profile.main_window_x, self.db.profile.main_window_y)
    else
	    guildwindow:SetPoint("CENTER", UIParent)
    end

    guildwindow.lock = self.db.profile.lock_main_window

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
			local className = data[realrow][7]:upper()
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
		["width"] = 180,
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
		["width"] = 120,
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
	cols[6] = {
		["name"] = L["Last Online"],
		["width"] = 100,
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
	searchterm:SetScript("OnEnterPressed",
	    function(this)
	        table:SortData()
	        self:UpdateRowCount()
	    end)
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
	searchbutton:SetScript("OnClick",
	    function(this)
	        table:SortData()
	        self:UpdateRowCount()
	    end)

	local clearbutton = CreateFrame("Button", nil, guildwindow, "UIPanelButtonTemplate")
	clearbutton:SetText(L["Clear"])
	clearbutton:SetWidth(100)
	clearbutton:SetHeight(20)
	clearbutton:SetPoint("LEFT", searchbutton, "RIGHT", 10, 0)
	clearbutton:SetScript("OnClick",
	    function(this)
	        searchterm:SetText("")
	        table:SortData()
	        self:UpdateRowCount()
	    end)

	local rowcounttext = guildwindow:CreateFontString("GS_Main_RowCountText", guildwindow, "GameFontNormalSmall")
	rowcounttext:SetPoint("BOTTOMLEFT", guildwindow, "BOTTOMLEFT", 20, 20)

	local editbutton = CreateFrame("Button", nil, guildwindow, "UIPanelButtonTemplate")
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

	local closebutton = CreateFrame("Button", nil, guildwindow, "UIPanelButtonTemplate")
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
				if ((profile.searchNames and row[1]:lower():find(term,1,plain)) or
					(profile.searchNotes and row[3]:lower():find(term,1,plain)) or
					(profile.searchOfficerNotes and row[4]:lower():find(term,1,plain)) or 
					(profile.searchRank and row[5]:lower():find(term,1,plain)) or			
					(profile.searchClass and row[7]:lower():find(term,1,plain))) then
					return true
				end

				return false
			else
				return true
			end
		end
	)

    guildwindow.lock = self.db.profile.lock_main_window

    guildwindow:SetMovable()
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
    			local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
    			local x, y = self:GetCenter()
    			x, y = x * scale, y * scale
    			x = x - GetScreenWidth()/2
    			y = y - GetScreenHeight()/2
    			x = x / self:GetScale()
    			y = y / self:GetScale()
    			GuildSearch.db.profile.main_window_x, 
    			    GuildSearch.db.profile.main_window_y = x, y
    			self:SetUserPlaced(false);
            end
        end)
    guildwindow:EnableMouse(true)

	guildwindow:Hide()
	
	return guildwindow
end

function GuildSearch:UpdateRowCount()
    local table = guildFrame.table
    local count = 0
    if table and table.filtered and type(table.filtered) == "table" then
        count = #table.filtered
    end
    
    guildFrame.rowcount:SetText(count.." results")
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
