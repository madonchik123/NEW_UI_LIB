local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Core = require(script.Parent.Core)
local Icons = require(script.Parent.Icons)
local Container = require(script.Parent.Containers)
local Blur = require(script.Parent.Blur)
local Motion = require(script.Parent.Motion)
local Tooltips = require(script.Parent.Tooltips)
local Search = require(script.Parent.Search)
local ThemeAliases = require(script.Parent.ThemeAliases)

local Window = {}
Window.__index = Window

local function utility(window, parent, iconName, position)
	local button = Core.new("TextButton", {
		Name = iconName,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Position = position,
		Size = UDim2.fromOffset(32, 32),
	}, parent)
	local icon = Icons.create(window, button, iconName)
	icon.Position = UDim2.fromOffset(8, 8)
	Core.round(button, window)
	window.Scope:Add(button.MouseEnter:Connect(function()
		Core.tween(window, button, { BackgroundTransparency = 0.2 })
	end))
	window.Scope:Add(button.MouseLeave:Connect(function()
		Core.tween(window, button, { BackgroundTransparency = 1 })
	end))
	Core.bind(window, button, "BackgroundColor3", "SurfaceHover")
	return button
end

function Window:Tooltip(target, text, scope)
	return self.Tooltips:Bind(target, text, scope or self.Scope)
end

function Window:SetToggleKey(key)
	if type(key) == "string" then
		key = Enum.KeyCode[key]
	end
	assert(typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode, "Expected a keyboard key")
	self.ToggleKey = key
end

function Window:RegisterControl(control, options, kind)
	options = options or {}
	if
		control.ConfigRegistered
		or control.Persist == false
		or control.Configurable == false
		or options.Persist == false
		or options.Configurable == false
		or not control.Get
		or not control.Set
		or not self.Config
	then
		return
	end
	local explicit = options.Flag or options.ConfigKey or options.SaveKey
	local names = { options.Name or options.Title or control.Root.Name }
	local parent = control.Parent
	while parent and parent ~= self do
		if parent.Name then
			table.insert(names, 1, parent.Name)
		elseif parent.Root then
			table.insert(names, 1, parent.Root.Name)
		end
		parent = parent.Parent
	end
	local id = explicit or table.concat(names, "/")
	local ok, message = self.Config:Register(id, kind or control.Kind or "control", function()
		return (control.GetConfigValue or control.Get)(control)
	end, function(value, silent)
		(control.SetConfigValue or control.Set)(control, value, silent)
	end, control.Scope, options)
	control.ConfigRegistered = self.Config.Items[id] ~= nil and ok ~= false
	control.ConfigId = control.ConfigRegistered and id or nil
	if not control.ConfigRegistered then
		warn("[Unknown Hub] " .. tostring(message))
	end
end

function Window:ControlChanged(control)
	if self.Config and control.ConfigRegistered then
		self.Config:Changed()
	end
end

function Window:Register(object, name, description)
	if name == "" then
		return
	end
	self.SearchEntries[object] = { Name = name, Description = description or "" }
	object.Scope:Add(function()
		self.SearchEntries[object] = nil
	end)
end

function Window:Reveal(object)
	local page = object.Page or (self.Pages[object] and object or nil)
	if page and page.Disabled then
		return
	end
	if page then
		self:SelectPage(page)
	end
	if object.Reveal then
		object:Reveal()
	end
	local parent = object.Parent
	while parent and parent ~= self do
		if parent.Reveal then
			parent:Reveal()
		end
		if parent.SetExpanded then
			parent:SetExpanded(true)
		end
		parent = parent.Parent
	end
	if object.SetExpanded then
		object:SetExpanded(true)
	end
	self:CloseSearch()
	if self.RevealScope then
		self.RevealScope:Destroy()
	end
	local revealScope = Core.scope(self.Scope)
	self.RevealScope = revealScope
	local remaining = self.Theme.AnimationSpeed + 0.05
	local connection
	connection = RunService.Heartbeat:Connect(function(delta)
		remaining -= delta
		if remaining > 0 then
			return
		end
		connection:Disconnect()
		revealScope.Resources[connection] = nil
		if not object.Scope.Alive or (page and self.SelectedPage ~= page) then
			revealScope:Destroy()
			return
		end
		local scroll = object.Root.Parent
		while scroll and not scroll:IsA("ScrollingFrame") do
			scroll = scroll.Parent
		end
		if scroll then
			local targetY = object.Root.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
			scroll.CanvasPosition = Vector2.new(0, math.max(0, targetY - 20 * self.ScaleObject.Scale))
		end
		local flash = Core.new("UIStroke", {
			Name = "SearchHighlight",
			Color = self.Theme.Accent,
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, object.Root)
		revealScope:Add(flash)
		Core.tween(self, flash, { Transparency = 1 }, 1.5)
		local tween = self.Tweens[flash]
		if tween then
			tween.Completed:Once(function()
				revealScope:Destroy()
			end)
		else
			revealScope:Destroy()
		end
	end)
	revealScope:Add(connection)
end

function Window:Search(query)
	return Search.query(self, query)
end

function Window:SelectPage(page)
	assert(self.Pages[page], "Page belongs to another window or has been destroyed")
	if page.Disabled then
		return
	end
	self.SelectedPage = page
	for other in pairs(self.Pages) do
		other.Root.Visible = other == page
		other.NavigationBorder.Transparency = other == page and 0.2 or 1
		Core.bind(self, other.Navigation, "BackgroundColor3", other == page and "SurfaceActive" or "Sidebar")
		Core.tween(self, other.Navigation, { BackgroundTransparency = other == page and 0 or 1 })
	end
	self.Breadcrumb.Text = (page.Breadcrumb or self.Title) .. "  /  " .. page.Name
	self.Subtitle.Text = page.Subtitle or ""
	self.Breadcrumb.Size = UDim2.new(page.Subtitle and 0.65 or 1, -14, 1, 0)
	self:CloseSearch()
	if self.Tooltips then
		self.Tooltips:Hide()
	end
	page.Root.ScrollBarImageTransparency = 0.3
end

function Window:DeselectPage()
	if self.SelectedPage and self.SelectedPage.Scope.Alive then
		self.SelectedPage.Root.Visible = false
		self.SelectedPage.Navigation.BackgroundTransparency = 1
	end
	self.SelectedPage = nil
	if self.Scope.Alive then
		self.Breadcrumb.Text = self.Title
		self.Subtitle.Text = ""
	end
end

function Window:Page(options)
	assert(options and options.Name, "Page requires Name")
	local groupName = options.Group or "workspace"
	local group = self.Groups[groupName]
	if not group then
		self.GroupCount += 1
		group = Core.new("Frame", {
			Name = groupName,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = ({ workspace = 10, automation = 20, personal = 90 })[string.lower(groupName)]
				or self.GroupCount + 30,
		}, self.Navigation)
		Core.list(group, 3)
		local heading = Core.text(self, group, string.lower(groupName), 10, "TextMuted")
		heading.Size = UDim2.new(1, 0, 0, 15)
		heading.LayoutOrder = -1
		self.Groups[groupName] = group
	end
	local button = Core.new("TextButton", {
		Name = options.Name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, self.Theme.NavHeight),
	}, group)
	Core.round(button, self)
	Core.bind(self, button, "BackgroundColor3", "Sidebar")
	local icon = Icons.create(self, button, options.Icon or "home")
	icon.Position = UDim2.fromOffset(8, 7)
	local label = Core.text(self, button, options.Name, 11)
	Core.bind(self, label, "Font", "FontBold")
	label.Position = UDim2.fromOffset(31, 0)
	label.Size = UDim2.new(1, -35, 1, 0)
	local page = Container.page(self, options, button)
	page.NavigationBorder = Core.stroke(button, self)
	page.NavigationBorder.Transparency = 1
	self.Pages[page] = true
	self:Tooltip(button, options.Tooltip or options.Name, page.Scope)
	page.Scope:Add(button.Activated:Connect(function()
		page:Select()
	end))
	page.Scope:Add(button.MouseEnter:Connect(function()
		if not page.Disabled and self.SelectedPage ~= page and UserInputService.MouseEnabled then
			Core.bind(self, button, "BackgroundColor3", "SurfaceHover")
			Core.tween(self, button, { BackgroundTransparency = 0.4 })
		end
	end))
	page.Scope:Add(button.MouseLeave:Connect(function()
		if self.SelectedPage ~= page then
			Core.tween(self, button, { BackgroundTransparency = 1 })
		end
	end))
	local setDisabled = page.SetDisabled
	function page:SetDisabled(value)
		setDisabled(self, value)
		label.TextTransparency = self.Disabled and 0.6 or 0
	end
	page:SetDisabled(options.Disabled)
	if not self.SelectedPage and not page.Disabled then
		page:Select()
	end
	return page
end

function Window:SetTheme(patch)
	patch = ThemeAliases.patch(patch)
	for token, value in pairs(patch) do
		self.Theme[token] = value
	end
	for instance, bindings in pairs(self.Bindings) do
		local tween = self.Tweens[instance]
		if tween then
			for _, token in pairs(bindings) do
				if patch[token] ~= nil then
					tween:Cancel()
					tween:Destroy()
					self.Tweens[instance] = nil
					if instance == self.Root then
						self.Root.Visible = self.Visible
						self.Root.GroupTransparency = self.Visible and 0 or 1
					end
					break
				end
			end
		end
		for property, token in pairs(bindings) do
			if patch[token] ~= nil then
				local value = self.Theme[token]
				instance[property] = property == "CornerRadius" and UDim.new(0, value) or value
			end
		end
	end
	if patch.SidebarWidth or patch.HeaderHeight or patch.NavHeight then
		self:Fit()
	end
	if self.Config then
		self.Config:ApplyTheme()
		if self.Config.Initialized then
			self.Config:Changed()
		end
	end
end

function Window:Fit()
	if not self.Scope.Alive then
		return
	end
	local viewport = self.Gui.AbsoluteSize
	if viewport.X <= 0 or viewport.Y <= 0 then
		return
	end
	self.IsMobile = self.ForceMobile
		or (UserInputService.TouchEnabled and (viewport.X < 950 or not UserInputService.KeyboardEnabled))
	local minimum = self.IsMobile and Vector2.new(340, 280) or self.MinimumSize
	local scale = math.min(self.UserScale, (viewport.X - 24) / minimum.X, (viewport.Y - 24) / minimum.Y)
	self.ScaleObject.Scale = math.max(0.25, scale)
	local desiredWidth = self.IsMobile and math.min(self.DesiredSize.X, 596) or self.DesiredSize.X
	local desiredHeight = self.DesiredSize.Y
	if self.IsMobile and viewport.Y > viewport.X then
		desiredHeight = math.max(desiredHeight, math.min(720, (viewport.Y - 24) / self.ScaleObject.Scale))
	end
	local width = math.clamp(desiredWidth, minimum.X, math.max(minimum.X, (viewport.X - 24) / self.ScaleObject.Scale))
	local height = math.clamp(desiredHeight, minimum.Y, math.max(minimum.Y, (viewport.Y - 24) / self.ScaleObject.Scale))
	self.Root.Size = UDim2.fromOffset(width, height)
	local sidebar = width < 570 and 116 or self.Theme.SidebarWidth
	self.Sidebar.Size = UDim2.new(0, sidebar, 1, 0)
	self.Header.Position = UDim2.fromOffset(sidebar, 0)
	self.Header.Size = UDim2.new(1, -sidebar, 0, self.Theme.HeaderHeight)
	self.Content.Position = UDim2.fromOffset(sidebar, self.Theme.HeaderHeight)
	self.Content.Size = UDim2.new(1, -sidebar, 1, -self.Theme.HeaderHeight)
	if self.FitSearch then
		self.FitSearch()
	end
	local actual = Vector2.new(width, height) * self.ScaleObject.Scale
	local position = self.Root.Position
	if position.X.Scale == 0 and position.Y.Scale == 0 then
		self.Root.Position = UDim2.fromOffset(
			math.clamp(position.X.Offset, 8, math.max(8, viewport.X - actual.X - 8)),
			math.clamp(position.Y.Offset, 8, math.max(8, viewport.Y - actual.Y - 8))
		)
	end
end

function Window:SetScale(value)
	assert(type(value) == "number" and value > 0, "Scale must be positive")
	self.UserScale = math.clamp(value, 0.5, 2)
	self:Fit()
end

function Window:Resize(width, height)
	self.DesiredSize = Vector2.new(math.max(340, width), math.max(280, height))
	self:Fit()
end

function Window:GetVisible()
	return self.Scope.Alive and self.Visible and not self.Locked
end
function Window:SetVisible(visible)
	if not self.Scope.Alive or self.Locked then
		return
	end
	self.Visible = visible == true
	if self.SyncLegacyHost then
		self.SyncLegacyHost()
	end
	if self.Tooltips then
		self.Tooltips:Hide()
	end
	if self.StopMotion then
		self.StopMotion()
	end
	if self.RestoreButton then
		self.RestoreButton.Visible = not self.Visible
	end
	if self.Blur then
		self.Blur:SetEnabled(self.Visible and self.BlurEnabled)
	end
	if self.CaptureKeybind and not self.Visible then
		self.CaptureKeybind:CancelListening()
	end
	self.Root.Visible = true
	Core.tween(self, self.Root, { GroupTransparency = self.Visible and 0 or 1 })
	if not self.Visible then
		self:CloseSearch()
		local focused = UserInputService:GetFocusedTextBox()
		if focused and focused:IsDescendantOf(self.Root) then
			focused:ReleaseFocus()
		end
	end
	local transition = self.Tweens[self.Root]
	if transition then
		transition.Completed:Once(function(state)
			if self.Scope.Alive and state == Enum.PlaybackState.Completed then
				self.Root.Visible = self.Visible
			end
		end)
	end
end
function Window:Open()
	self:SetVisible(true)
end
function Window:Close()
	self:SetVisible(false)
end
function Window:Toggle()
	self:SetVisible(not self.Visible)
end

function Window:Destroy()
	if self.Destroying or not self.Scope.Alive then
		return
	end
	self.Destroying = true
	self._destroyed = true
	if self.Config then
		self.Config:Flush()
		self.Config:Destroy()
	end
	if self.KeySystem then
		self.KeySystem:Destroy()
	end
	for _, tween in pairs(self.Tweens) do
		tween:Cancel()
		tween:Destroy()
	end
	table.clear(self.Tweens)
	self.Scope:Destroy()
	table.clear(self.Bindings)
	table.clear(self.Pages)
	table.clear(self.SearchEntries)
	table.clear(self.Groups)
end

function Window:SetBlur(enabled)
	self.BlurEnabled = enabled == true
	if not self.Blur then
		self.Blur = Blur.new(self)
	end
	self.Blur:SetEnabled(self.Visible and self.BlurEnabled)
end

function Window:SetProfile(description, status)
	if description then
		self.ProfileDescription = description
	end
	if status then
		self.ProfileStatus.Text = status
	end
end

function Window:Modal(options)
	return Container.modal(self, options or {})
end

function Window.new(options, theme, scope)
	local self = setmetatable({
		Scope = scope,
		Theme = table.clone(theme),
		Bindings = {},
		Tweens = {},
		Pages = {},
		Groups = {},
		SearchEntries = {},
		GroupCount = 0,
		Visible = true,
		Title = options.Title or options.Name or "Unknown Hub",
		UserScale = options.Scale or 1,
		ForceMobile = options.ForceMobile == true,
		MinimumSize = Vector2.new(
			math.max(340, tonumber(options.MinWidth) or 340),
			math.max(280, tonumber(options.MinHeight) or 280)
		),
		Legacy = options._Legacy == true,
	}, Window)
	local size = options.Size or UDim2.fromOffset(760, 500)
	local parent = options.Parent or Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Gui = Core.new("ScreenGui", {
		Name = options.Name or "Unknown Hub",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = options.DisplayOrder or 20,
	}, parent)
	scope:Add(self.Gui)
	self._sg = self.Gui
	self._destroyed = false
	self.IsMobile = self.ForceMobile
		or (UserInputService.TouchEnabled and (self.Gui.AbsoluteSize.X < 950 or not UserInputService.KeyboardEnabled))
	if self.IsMobile then
		self.Theme.ControlHeight = math.max(32, self.Theme.ControlHeight)
		self.Theme.NavHeight = math.max(34, self.Theme.NavHeight)
		self.Theme.BodySize = math.max(12, self.Theme.BodySize)
	end
	scope:Add(self.Gui.Destroying:Connect(function()
		self:Destroy()
	end))
	self.DesiredSize = Vector2.new(
		size.X.Offset + size.X.Scale * self.Gui.AbsoluteSize.X,
		size.Y.Offset + size.Y.Scale * self.Gui.AbsoluteSize.Y
	)
	if self.IsMobile then
		self.DesiredSize = Vector2.new(
			math.min(self.DesiredSize.X, 596, math.max(340, self.Gui.AbsoluteSize.X - 24)),
			self.Gui.AbsoluteSize.Y > self.Gui.AbsoluteSize.X and math.min(720, self.Gui.AbsoluteSize.Y - 24)
				or self.DesiredSize.Y
		)
	end
	self.Root = Core.new("CanvasGroup", {
		Name = "Window",
		Size = UDim2.fromOffset(760, 500),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
	}, self.Gui)
	Core.bind(self, self.Root, "BackgroundColor3", "Background")
	Core.bind(self, self.Root, "BackgroundTransparency", "WindowTransparency")
	Core.round(self.Root, self)
	Core.stroke(self.Root, self)
	self.ScaleObject = Core.new("UIScale", { Scale = self.UserScale }, self.Root)
	self.Input = Core.input(self)
	self.Tooltips = Tooltips.new(self)
	self.ToggleKey = options.ToggleKey or Enum.KeyCode.RightShift
	local topLine = Core.new(
		"Frame",
		{ Name = "AccentLine", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), ZIndex = 10 },
		self.Root
	)
	Core.bind(self, topLine, "BackgroundColor3", "Accent")
	topLine.Visible = false
	self.Sidebar =
		Core.new("Frame", { Name = "Sidebar", Size = UDim2.new(0, 146, 1, 0), BorderSizePixel = 0 }, self.Root)
	Core.bind(self, self.Sidebar, "BackgroundColor3", "Sidebar")
	Core.bind(self, self.Sidebar, "BackgroundTransparency", "PanelTransparency")
	local edge = Core.new(
		"Frame",
		{ BorderSizePixel = 0, Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0) },
		self.Sidebar
	)
	Core.bind(self, edge, "BackgroundColor3", "Border")
	local logo = Icons.create(self, self.Sidebar, "logo", "Text")
	logo.Position = UDim2.fromOffset(12, 15)
	local branding = Core.text(self, self.Sidebar, string.upper(options.Title or options.Name or "Unknown Hub"), 10)
	Core.bind(self, branding, "Font", "FontBold")
	branding.Position = UDim2.fromOffset(34, 0)
	branding.Size = UDim2.new(1, -38, 0, 44)
	self.Navigation = Core.new("ScrollingFrame", {
		Name = "Navigation",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(10, 51),
		Size = UDim2.new(1, -20, 1, -113),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 0,
	}, self.Sidebar)
	Core.list(self.Navigation, 0)
	local profile = Core.new("TextButton", {
		Name = "Profile",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 10, 1, -50),
		Size = UDim2.new(1, -20, 0, 40),
	}, self.Sidebar)
	Core.bind(self, profile, "BackgroundColor3", "Surface")
	Core.round(profile, self)
	local avatar = Core.text(
		self,
		profile,
		string.upper(string.sub(options.Username or Players.LocalPlayer.DisplayName, 1, 1)),
		13,
		"Accent"
	)
	avatar.Position = UDim2.fromOffset(10, 6)
	avatar.Size = UDim2.fromOffset(20, 26)
	local username = Core.text(self, profile, options.Username or Players.LocalPlayer.DisplayName, 10)
	username.Position = UDim2.fromOffset(36, 5)
	username.Size = UDim2.new(1, -40, 0, 16)
	local status = Core.text(self, profile, options.Status or "Online", 9, "TextMuted")
	status.Position = UDim2.fromOffset(36, 20)
	status.Size = UDim2.new(1, -40, 0, 14)
	self.ProfileButton = profile
	self.ProfileStatus = status
	self.Header = Core.new("Frame", { Name = "Header", BackgroundTransparency = 1 }, self.Root)
	local dragArea = Core.new(
		"Frame",
		{ Name = "DragArea", Active = true, BackgroundTransparency = 1, Size = UDim2.new(1, -84, 1, 0) },
		self.Header
	)
	self.Breadcrumb = Core.text(self, dragArea, self.Title, 13)
	self.Breadcrumb.Position = UDim2.fromOffset(14, 0)
	self.Breadcrumb.Size = UDim2.new(0.65, -14, 1, 0)
	self.Subtitle = Core.text(self, dragArea, options.Subtitle or "", 10, "TextMuted")
	self.Subtitle.Position = UDim2.fromScale(0.65, 0)
	self.Subtitle.Size = UDim2.fromScale(0.35, 1)
	self.Subtitle.TextXAlignment = Enum.TextXAlignment.Right
	local search = utility(self, self.Header, "search", UDim2.new(1, -78, 0, 5))
	local close = utility(self, self.Header, "minimize", UDim2.new(1, -40, 0, 5))
	search.Name = "SearchButton"
	close.Name = "MinimizeButton"
	self.SearchButton, self.MinimizeButton = search, close
	self:Tooltip(search, "Search all features · Ctrl+K", scope)
	self:Tooltip(close, "Minimize", scope)
	self.Content =
		Core.new("Frame", { Name = "Content", BackgroundTransparency = 1, ClipsDescendants = true }, self.Root)
	local grip = Core.new("TextButton", {
		Name = "Resize",
		Text = "◢",
		TextSize = 11,
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -18, 1, -18),
		Size = UDim2.fromOffset(16, 16),
		ZIndex = 12,
	}, self.Root)
	Core.bind(self, grip, "TextColor3", "TextMuted")
	Search.mount(self)
	Motion.bindWindow(self, dragArea, grip)
	scope:Add(search.Activated:Connect(function()
		self:OpenSearch()
	end))
	scope:Add(close.Activated:Connect(function()
		self:Close()
	end))
	scope:Add(self.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:Fit()
	end))
	self.Input:Subscribe(scope, {
		Began = function(input, processed)
			if self.CaptureKeybind or self.ConsumedKeybindInput == input then
				return
			end
			if self:HandleSearchInput(input) then
				return
			end
			if processed or UserInputService:GetFocusedTextBox() then
				return
			end
			if input.KeyCode == self.ToggleKey then
				self:Toggle()
			end
			if
				self.Visible
				and input.KeyCode == Enum.KeyCode.K
				and (
					UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
				)
			then
				self:OpenSearch()
			end
		end,
	})

	self.RestoreButton = Core.new("TextButton", {
		Name = "RestoreUI",
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		Position = UDim2.new(0, 14, 0.5, -24),
		Size = UDim2.fromOffset(48, 48),
		BorderSizePixel = 0,
		ZIndex = 80,
	}, self.Gui)
	Core.bind(self, self.RestoreButton, "BackgroundColor3", "Surface")
	Core.round(self.RestoreButton, self)
	Core.stroke(self.RestoreButton, self)
	local restoreIcon = Icons.create(self, self.RestoreButton, "logo", "Text", 22)
	restoreIcon.Position = UDim2.fromOffset(13, 13)
	self:Tooltip(self.RestoreButton, "Open Unknown Hub", scope)
	scope:Add(self.RestoreButton.Activated:Connect(function()
		self:Open()
	end))
	self:Tooltip(profile, "Profile", scope)
	self:Fit()
	return self
end

return Window
