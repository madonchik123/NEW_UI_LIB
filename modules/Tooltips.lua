return function(require)
	local UserInputService = game:GetService("UserInputService")
	local Core = require("Core")
	local Tooltips = {}
	Tooltips.__index = Tooltips

	function Tooltips.new(window)
		local self = setmetatable({ Window = window }, Tooltips)
		local label = Core.text(window, window.Gui, "", 11)
		label.Name = "Tooltip"
		label.Visible = false
		label.ZIndex = 100
		label.BackgroundTransparency = 0.04
		label.TextWrapped = true
		label.TextTruncate = Enum.TextTruncate.None
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.Size = UDim2.fromOffset(0, 0)
		Core.new("UISizeConstraint", { MaxSize = Vector2.new(280, 140) }, label)
		Core.bind(window, label, "BackgroundColor3", "Surface")
		Core.round(label, window)
		Core.stroke(label, window)
		Core.pad(label, 8)
		self.Label = label
		return self
	end

	function Tooltips:Hide()
		if self.Pending then
			self.Pending()
			self.Pending = nil
		end
		self.Target = nil
		self.Label.Visible = false
	end

	function Tooltips:Bind(target, value, scope)
		if value == false or value == nil or value == "" then
			return
		end
		local function hide()
			if self.Target == target then
				self:Hide()
			end
		end
		local function show()
			self:Hide()
			self.Target = target
			self.Pending = Core.delay(scope, 0.45, function()
				self.Pending = nil
				if not scope.Alive or not self.Window.Scope.Alive or self.Target ~= target or not target.Parent then
					return
				end
				local content = value
				if type(value) == "function" then
					local success, result = pcall(value)
					if not success then
						return
					end
					content = result
				end
				if
					not scope.Alive
					or not self.Window.Scope.Alive
					or self.Target ~= target
					or not self.Window.Gui.Enabled
				then
					return
				end
				local ancestor = target
				while ancestor and ancestor ~= self.Window.Gui do
					if ancestor:IsA("GuiObject") and not ancestor.Visible then
						return
					end
					ancestor = ancestor.Parent
				end
				if not ancestor then
					return
				end
				local label = self.Label
				label.Text = tostring(content or "")
				local position = target.AbsolutePosition - self.Window.Gui.AbsolutePosition
				local viewport = self.Window.Gui.AbsoluteSize
				local width = math.min(280, #label.Text * 6 + 16)
				label.Position = UDim2.fromOffset(
					math.clamp(
						position.X + target.AbsoluteSize.X / 2 - width / 2,
						8,
						math.max(8, viewport.X - width - 8)
					),
					math.clamp(position.Y + target.AbsoluteSize.Y + 7, 8, math.max(8, viewport.Y - 70))
				)
				label.Visible = true
			end)
		end
		scope:Add(target.MouseEnter:Connect(function()
			if UserInputService.MouseEnabled then
				show()
			end
		end))
		scope:Add(target.MouseLeave:Connect(hide))
		scope:Add(target.SelectionGained:Connect(show))
		scope:Add(target.SelectionLost:Connect(hide))
		scope:Add(target.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				show()
			end
		end))
		scope:Add(target.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				hide()
			end
		end))
		scope:Add(hide)
	end

	return Tooltips
end
