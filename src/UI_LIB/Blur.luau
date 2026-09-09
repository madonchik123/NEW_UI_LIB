local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Core = require(script.Parent.Core)

local Blur = {}

local EDGE_INSET = 3
local PLANE_GAP = 0.001
local PLANE_THICKNESS = 0.001
local GLASS_TRANSPARENCY = 0.9999999

function Blur.new(window)
	assert(window.Root and window.Gui, "Blur requires an initialized window")
	local scope = Core.scope(window.Scope)
	local self = { Scope = scope, Enabled = false, Plane = nil, Effect = nil }
	local activeScope = nil
	local cameraScope = nil
	local camera = nil
	local plane = nil
	local effect = nil
	local drawn = false
	local previousDepth = nil

	local function clearCamera()
		if cameraScope then
			cameraScope:Destroy()
			cameraScope = nil
		end
		camera = nil
		plane = nil
		effect = nil
		self.Plane = nil
		self.Effect = nil
		drawn = false
		previousDepth = nil
	end

	local function setDrawn(visible)
		if drawn ~= visible then
			drawn = visible
			plane.Transparency = if visible then GLASS_TRANSPARENCY else 1
			effect.Enabled = visible
		end
	end

	local function render()
		if not scope.Alive or not camera or not plane or not effect then
			return
		end
		if not window.Root.Visible or not window.Gui.Enabled or not window:GetVisible() then
			setDrawn(false)
			return
		end
		local position = window.Root.AbsolutePosition - window.Gui.AbsolutePosition
		local size = window.Root.AbsoluteSize
		local viewport = camera.ViewportSize
		local left = math.max(0, position.X + EDGE_INSET)
		local top = math.max(0, position.Y + EDGE_INSET)
		local right = math.min(viewport.X, position.X + size.X - EDGE_INSET)
		local bottom = math.min(viewport.Y, position.Y + size.Y - EDGE_INSET)
		if viewport.X <= 1 or viewport.Y <= 1 or right <= left or bottom <= top then
			setDrawn(false)
			return
		end

		local depth = math.abs(camera.NearPlaneZ) + PLANE_GAP
		if previousDepth ~= depth then
			previousDepth = depth
			effect.FocusDistance = depth + 0.002
			effect.InFocusRadius = depth + 0.001
		end
		local cameraFrame = camera.CFrame

		local firstRay = camera:ViewportPointToRay(left, top)
		local lastRay = camera:ViewportPointToRay(right, bottom)
		local firstDirection = cameraFrame:VectorToObjectSpace(firstRay.Direction)
		local lastDirection = cameraFrame:VectorToObjectSpace(lastRay.Direction)
		local firstX = firstDirection.X * depth / -firstDirection.Z
		local firstY = firstDirection.Y * depth / -firstDirection.Z
		local lastX = lastDirection.X * depth / -lastDirection.Z
		local lastY = lastDirection.Y * depth / -lastDirection.Z
		plane.Size = Vector3.new(lastX - firstX, firstY - lastY, PLANE_THICKNESS)
		plane.CFrame = cameraFrame * CFrame.new((firstX + lastX) * 0.5, (firstY + lastY) * 0.5, -depth)
		setDrawn(true)
	end

	local function attachCamera(nextCamera)
		if camera == nextCamera then
			return
		end
		clearCamera()
		if not nextCamera or not activeScope or not activeScope.Alive then
			return
		end
		camera = nextCamera
		cameraScope = Core.scope(activeScope)
		plane = Core.new("Part", {
			Name = "UI_LIB_BlurPlane",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Glass,
			Color = Color3.new(1, 1, 1),
			Reflectance = 0,
			Transparency = 1,
			Size = Vector3.new(1, 1, PLANE_THICKNESS),
		}, nextCamera)
		cameraScope:Add(plane)
		effect = Core.new("DepthOfFieldEffect", {
			Name = "UI_LIB_DepthOfField",
			Enabled = false,
			FarIntensity = 0,
			NearIntensity = 1,
			FocusDistance = 0.103,
			InFocusRadius = 0.102,
		}, nextCamera)
		cameraScope:Add(effect)
		self.Plane = plane
		self.Effect = effect
		cameraScope:Add(nextCamera.Destroying:Connect(function()
			if camera == nextCamera then
				clearCamera()
			end
		end))
	end

	function self:SetEnabled(enabled)
		enabled = enabled == true
		if not scope.Alive or self.Enabled == enabled then
			return
		end
		self.Enabled = enabled
		if activeScope then
			activeScope:Destroy()
			activeScope = nil
			clearCamera()
		end
		if not enabled then
			return
		end
		activeScope = Core.scope(scope)
		attachCamera(Workspace.CurrentCamera)
		activeScope:Add(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			attachCamera(Workspace.CurrentCamera)
		end))
		render()
		activeScope:Add(RunService.PreRender:Connect(render))
	end

	function self:Destroy()
		scope:Destroy()
	end

	scope:Add(function()
		self.Enabled = false
		if activeScope then
			activeScope:Destroy()
			activeScope = nil
		end
		clearCamera()
	end)
	return self
end

return Blur
