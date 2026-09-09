local Core = require(script.Parent.Core)
local LegacyHost = {}
function LegacyHost.mount(window)
	local host = Core.new("Frame", {
		Name = "LegacyOverlayHost",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		ZIndex = 2,
	}, window.Gui)
	local scale = Core.new("UIScale", {}, host)
	local function synchronize()
		if not window.Scope.Alive then
			return
		end
		host.AnchorPoint = window.Root.AnchorPoint
		host.Position = window.Root.Position
		host.Size = window.Root.Size
		scale.Scale = window.ScaleObject.Scale
		host.Visible = window.Visible and not window.Locked and window.Root.Visible
	end
	for _, property in ipairs({ "Position", "Size", "AnchorPoint", "Visible", "GroupTransparency" }) do
		window.Scope:Add(window.Root:GetPropertyChangedSignal(property):Connect(synchronize))
	end
	window.Scope:Add(window.ScaleObject:GetPropertyChangedSignal("Scale"):Connect(synchronize))
	synchronize()
	window._main = host
	window.SyncLegacyHost = synchronize
	return host
end
return LegacyHost
