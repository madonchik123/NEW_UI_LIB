return function(require)
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local TextService = game:GetService("TextService")
	local Core = require("Core")
	local PlayerESP = {}

	local function createGuiEspModule(opts, context)
		opts = opts or {}

		local Players = context.Players or game:GetService("Players")
		local RunService = context.RunService or game:GetService("RunService")
		local TextService = context.TextService or game:GetService("TextService")
		local LocalPlayer = context.Client or Players.LocalPlayer
		local C3 = Color3.fromRGB
		local V2 = Vector2.new
		local WHITE = C3(255, 255, 255)

		local settings = {
			Box = false,
			Name = false,
			Health = false,
			Team = false,
			Tracers = false,
			Skeleton = false,
			HeldItem = false,
			Distance = false,
			Character = false,
			Ultimate = false,
			Skills = false,
			Status = false,
			MaxDistance = opts.MaxDistance or 1000,
			IntelResolver = opts.IntelResolver,
		}

		local tracked = {}
		local textMeasureCache = {}
		local textMeasureCount = 0
		local renderConnection = nil
		local playerRemovingConnection = nil
		local playerEspGui = nil
		local destroyed = false
		local destroyOwner
		local linePoints = {}
		local noSmoothLines = {}
		local LINE_RESET_DISTANCE = 90
		local BOUNDS_RESET_DISTANCE = 90
		local frameSmoothingAlpha = 1
		local frameValueAlpha = 1
		local intelCache = setmetatable({}, { __mode = "k" })
		local INTEL_INTERVAL = tonumber(opts.IntelInterval) or 0.12
		local POSITION_RESPONSE = tonumber(opts.PositionResponse) or 16
		local VALUE_RESPONSE = tonumber(opts.ValueResponse) or 12
		local REFERENCE_BOX_WIDTH = 40
		local REFERENCE_BOX_HEIGHT = 64

		local function getEspGui()
			if destroyed then
				return nil
			end
			local ok, parent = pcall(context.getHiddenParent)
			if not ok or not parent then
				return nil
			end

			if playerEspGui and playerEspGui.Parent == parent then
				return playerEspGui
			end

			local gui = Instance.new("ScreenGui")
			gui.Name = "UnknownHubPlayerEsp"
			gui.IgnoreGuiInset = true
			gui.ResetOnSpawn = false
			gui.DisplayOrder = 100000
			gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			gui.Parent = parent
			gui.Destroying:Once(function()
				if destroyOwner then
					destroyOwner()
				end
			end)
			playerEspGui = gui
			return gui
		end

		local function destroyObject(object)
			if object then
				pcall(function()
					linePoints[object] = nil
					noSmoothLines[object] = nil
					object:Destroy()
				end)
			end
		end

		local function makeLabel(name, color, textSize, zIndex)
			local gui = getEspGui()
			if not gui then
				return nil
			end

			local label = Instance.new("TextLabel")
			label.Name = name
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.BackgroundTransparency = 1
			label.BorderSizePixel = 0
			label.TextColor3 = color
			label.TextSize = textSize
			label.TextStrokeColor3 = C3(0, 0, 0)
			label.TextStrokeTransparency = 0.35
			label.TextWrapped = false
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.Visible = false
			label.ZIndex = zIndex or 120
			label.Size = UDim2.fromOffset(230, textSize + 8)
			label.Parent = gui
			return label
		end

		local function makeSkillTile(index)
			local gui = getEspGui()
			if not gui then
				return nil
			end

			local back = Instance.new("Frame")
			back.Name = "PlayerSkillTile" .. index
			back.BackgroundColor3 = C3(0, 0, 0)
			back.BackgroundTransparency = 0.22
			back.BorderSizePixel = 0
			back.ClipsDescendants = true
			back.Visible = false
			back.ZIndex = 128
			back.Parent = gui

			local stroke = Instance.new("UIStroke")
			stroke.Color = WHITE
			stroke.Transparency = 0
			stroke.Thickness = 1
			stroke.Parent = back

			local fill = Instance.new("Frame")
			fill.Name = "CooldownFill"
			fill.AnchorPoint = Vector2.new(1, 0)
			fill.BackgroundColor3 = C3(255, 0, 0)
			fill.BackgroundTransparency = 0.3
			fill.BorderSizePixel = 0
			fill.Position = UDim2.fromScale(1, 0)
			fill.Size = UDim2.fromScale(0, 1)
			fill.ZIndex = 129
			fill.Parent = back

			local label = Instance.new("TextLabel")
			label.Name = "Value"
			label.BackgroundTransparency = 1
			label.BorderSizePixel = 0
			label.Position = UDim2.fromOffset(1, 0)
			label.Size = UDim2.new(1, -2, 1, 0)
			label.TextColor3 = WHITE
			label.TextSize = 9
			label.TextStrokeColor3 = C3(0, 0, 0)
			label.TextStrokeTransparency = 0.2
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.TextWrapped = false
			label.ZIndex = 130
			label.Parent = back

			local key = Instance.new("TextLabel")
			key.Name = "Key"
			key.BackgroundTransparency = 1
			key.BorderSizePixel = 0
			key.Position = UDim2.fromOffset(2, 1)
			key.Size = UDim2.fromOffset(8, 8)
			key.Text = tostring(index)
			key.TextColor3 = C3(159, 174, 190)
			key.TextSize = 7
			key.TextStrokeTransparency = 0.7
			key.TextXAlignment = Enum.TextXAlignment.Left
			key.TextYAlignment = Enum.TextYAlignment.Top
			key.ZIndex = 131
			key.Visible = false
			key.Parent = back

			return { Back = back, Fill = fill, Label = label, Key = key, Stroke = stroke }
		end

		local function makeLine(name, color, thickness, zIndex)
			local gui = getEspGui()
			if not gui then
				return nil
			end

			local line = Instance.new("Frame")
			line.Name = name
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.BackgroundColor3 = color
			line.BackgroundTransparency = 0.05
			line.BorderSizePixel = 0
			line.Size = UDim2.fromOffset(0, thickness or 1)
			line.Visible = false
			line.ZIndex = zIndex or 110
			line.Parent = gui
			return line
		end

		local function setVisible(object, visible)
			if object then
				if visible ~= true then
					linePoints[object] = nil
				end
				object.Visible = visible == true
			end
		end

		local function hideList(list)
			for _, object in ipairs(list or {}) do
				setVisible(object, false)
			end
		end

		local function snap(value)
			return math.floor((tonumber(value) or 0) + 0.5)
		end

		local function snapPoint(point)
			if not point then
				return nil
			end
			return V2(point.X, point.Y)
		end

		local function smoothPoint(previous, current)
			if not previous then
				return current
			end
			if (current - previous).Magnitude > LINE_RESET_DISTANCE then
				return current
			end
			return previous + ((current - previous) * frameSmoothingAlpha)
		end

		local function updateLine(line, fromPoint, toPoint, color, thickness)
			if not line or not fromPoint or not toPoint then
				if line then
					linePoints[line] = nil
				end
				setVisible(line, false)
				return
			end

			fromPoint = snapPoint(fromPoint)
			toPoint = snapPoint(toPoint)
			if not noSmoothLines[line] then
				local state = linePoints[line] or {}
				fromPoint = smoothPoint(state.From, fromPoint)
				toPoint = smoothPoint(state.To, toPoint)
				linePoints[line] = {
					From = fromPoint,
					To = toPoint,
				}
			end

			local delta = toPoint - fromPoint
			local length = delta.Magnitude
			if length < 1 then
				linePoints[line] = nil
				setVisible(line, false)
				return
			end

			line.BackgroundColor3 = color
			line.Size = UDim2.fromOffset(length, thickness or 1)
			line.Position = UDim2.fromOffset((fromPoint.X + toPoint.X) * 0.5, (fromPoint.Y + toPoint.Y) * 0.5)
			line.Rotation = math.deg((math.atan2 or math.atan)(delta.Y, delta.X))
			line.Visible = true
		end

		local function measureTextWidth(text, textSize, font)
			local key = tostring(font) .. "\0" .. tostring(textSize) .. "\0" .. tostring(text or "")
			local cached = textMeasureCache[key]
			if cached then
				return cached
			end
			if textMeasureCount >= 512 then
				table.clear(textMeasureCache)
				textMeasureCount = 0
			end
			textMeasureCount += 1

			local ok, size = pcall(function()
				return TextService:GetTextSize(text, textSize, font, Vector2.new(1000, textSize + 8))
			end)
			if ok and size then
				textMeasureCache[key] = size.X
				return size.X
			end
			local fallback = #tostring(text or "") * textSize * 0.55
			textMeasureCache[key] = fallback
			return fallback
		end

		local function updateNameLabel(label, text, centerX, top, boxWidth)
			if not label then
				return
			end
			if not settings.Name then
				label.Visible = false
				return
			end

			local maxWidth = 140
			local textSize = 10
			local labelHeight = 16
			label.Text = text
			label.TextSize = textSize
			label.TextColor3 = WHITE
			label.Size = UDim2.fromOffset(maxWidth, labelHeight)
			label.Position = UDim2.fromOffset(centerX, top - (labelHeight * 0.5) - 4)
			label.Visible = true
		end

		local function project(camera, position)
			local point, onScreen = camera:WorldToViewportPoint(position)
			if not onScreen or point.Z <= 0 then
				return nil
			end
			return V2(point.X, point.Y)
		end

		local function updateWorldLine(camera, line, fromPosition, toPosition, color, thickness)
			local fromPoint = fromPosition and project(camera, fromPosition)
			local toPoint = toPosition and project(camera, toPosition)
			updateLine(line, fromPoint, toPoint, color, thickness)
		end

		local function makePlayerData(player)
			if tracked[player] then
				return tracked[player]
			end

			local data = {
				box = {},
				skeleton = {},
				bounds = nil,
			}

			for index = 1, 4 do
				data.box[index] = makeLine("PlayerBoxEspLine", WHITE, 1, 120)
				if data.box[index] then
					noSmoothLines[data.box[index]] = true
				end
			end

			data.tracer = makeLine("PlayerTracerEspLine", WHITE, 1, 110)
			data.healthBack = makeLine("PlayerHealthEspBack", C3(0, 0, 0), 7, 115)
			data.healthFill = makeLine("PlayerHealthEspFill", C3(0, 255, 80), 5, 125)
			data.ultimateBack = makeLine("PlayerUltimateEspBack", C3(0, 0, 0), 4, 115)
			data.ultimateFill = makeLine("PlayerUltimateEspFill", C3(180, 92, 255), 2, 125)
			if data.healthBack then
				noSmoothLines[data.healthBack] = true
			end
			if data.healthFill then
				noSmoothLines[data.healthFill] = true
			end
			if data.ultimateBack then
				noSmoothLines[data.ultimateBack] = true
			end
			if data.ultimateFill then
				noSmoothLines[data.ultimateFill] = true
			end
			data.name = makeLabel("PlayerNameEsp", WHITE, 11, 130)
			data.character = makeLabel("PlayerCharacterEsp", C3(125, 220, 255), 10, 132)
			data.team = makeLabel("PlayerTeamEsp", WHITE, 12, 130)
			data.heldItem = makeLabel("PlayerHeldItemEsp", C3(255, 204, 106), 9, 130)
			data.distance = makeLabel("PlayerDistanceEsp", C3(184, 204, 226), 11, 130)
			data.ultimate = makeLabel("PlayerUltimateEsp", C3(218, 174, 255), 10, 130)
			data.status = makeLabel("PlayerStatusEsp", C3(255, 92, 102), 11, 135)
			data.skillTiles = {}
			for index = 1, 5 do
				data.skillTiles[index] = makeSkillTile(index)
			end
			data.healthRatio = nil
			data.ultimateRatio = nil

			if data.distance then
				data.distance.AnchorPoint = Vector2.new(0, 0.5)
				data.distance.TextXAlignment = Enum.TextXAlignment.Left
				data.distance.Size = UDim2.fromOffset(90, 18)
			end
			if data.ultimate then
				data.ultimate.AnchorPoint = Vector2.new(1, 0.5)
				data.ultimate.TextXAlignment = Enum.TextXAlignment.Right
				data.ultimate.Size = UDim2.fromOffset(90, 18)
			end
			if data.status then
				data.status.AnchorPoint = Vector2.new(0.5, 0.5)
				data.status.TextXAlignment = Enum.TextXAlignment.Center
				data.status.Size = UDim2.fromOffset(180, 16)
			end

			if data.team then
				data.team.AnchorPoint = Vector2.new(0, 0.5)
				data.team.TextXAlignment = Enum.TextXAlignment.Left
				data.team.Size = UDim2.fromOffset(170, 20)
			end
			if data.heldItem then
				data.heldItem.AnchorPoint = Vector2.new(0, 0.5)
				data.heldItem.TextXAlignment = Enum.TextXAlignment.Left
				data.heldItem.Size = UDim2.fromOffset(180, 20)
			end

			tracked[player] = data
			return data
		end

		local function removePlayerData(player)
			local data = tracked[player]
			if not data then
				return
			end

			for _, line in ipairs(data.box or {}) do
				destroyObject(line)
			end
			for _, line in ipairs(data.skeleton or {}) do
				destroyObject(line)
			end
			destroyObject(data.tracer)
			destroyObject(data.healthBack)
			destroyObject(data.healthFill)
			destroyObject(data.ultimateBack)
			destroyObject(data.ultimateFill)
			destroyObject(data.name)
			destroyObject(data.character)
			destroyObject(data.team)
			destroyObject(data.heldItem)
			destroyObject(data.distance)
			destroyObject(data.ultimate)
			destroyObject(data.status)
			for _, tile in ipairs(data.skillTiles or {}) do
				if tile then
					destroyObject(tile.Back)
				end
			end
			intelCache[player] = nil
			tracked[player] = nil
		end

		playerRemovingConnection = Players.PlayerRemoving:Connect(removePlayerData)

		local function hideData(data)
			if not data then
				return
			end

			hideList(data.box)
			hideList(data.skeleton)
			data.bounds = nil
			setVisible(data.tracer, false)
			setVisible(data.healthBack, false)
			setVisible(data.healthFill, false)
			setVisible(data.ultimateBack, false)
			setVisible(data.ultimateFill, false)
			setVisible(data.name, false)
			setVisible(data.character, false)
			setVisible(data.team, false)
			setVisible(data.heldItem, false)
			setVisible(data.distance, false)
			setVisible(data.ultimate, false)
			setVisible(data.status, false)
			for _, tile in ipairs(data.skillTiles or {}) do
				if tile then
					setVisible(tile.Back, false)
				end
			end
		end

		local r6LowerBodyParts = {
			"Left Leg",
			"Right Leg",
		}

		local r15LowerBodyParts = {
			"LeftFoot",
			"RightFoot",
			"LeftLowerLeg",
			"RightLowerLeg",
			"LeftUpperLeg",
			"RightUpperLeg",
		}

		local bodyBoundsPartNames = {
			Head = true,
			Torso = true,
			["Left Arm"] = true,
			["Right Arm"] = true,
			["Left Leg"] = true,
			["Right Leg"] = true,
			UpperTorso = true,
			LowerTorso = true,
			LeftUpperArm = true,
			LeftLowerArm = true,
			LeftHand = true,
			RightUpperArm = true,
			RightLowerArm = true,
			RightHand = true,
			LeftUpperLeg = true,
			LeftLowerLeg = true,
			LeftFoot = true,
			RightUpperLeg = true,
			RightLowerLeg = true,
			RightFoot = true,
		}

		local function getPart(character, name)
			local part = character and character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				return part
			end
			return nil
		end

		local function pointFromPart(part, offset)
			if not part then
				return nil
			end
			return part.CFrame:PointToWorldSpace(offset)
		end

		local function partEnd(part, yScale)
			if not part or not part.Parent then
				return nil
			end
			return pointFromPart(part, Vector3.new(0, part.Size.Y * yScale, 0))
		end

		local function midpoint(a, b, fallback)
			if a and b then
				return (a + b) * 0.5
			end
			return fallback
		end

		local function collectJointPositions(character, jointNames)
			local wanted = {}
			local found = {}
			for _, jointName in ipairs(jointNames) do
				wanted[jointName] = true
			end

			for _, inst in ipairs(character:GetDescendants()) do
				if wanted[inst.Name] and inst:IsA("Motor6D") then
					if inst.Part0 and inst.Part0.Parent then
						found[inst.Name] = inst.Part0.CFrame:PointToWorldSpace(inst.C0.Position)
					elseif inst.Part1 and inst.Part1.Parent then
						found[inst.Name] = inst.Part1.CFrame:PointToWorldSpace(inst.C1.Position)
					end
				end
			end

			return found
		end

		local function getR6SkeletonSegments(character)
			local head = getPart(character, "Head")
			local torso = getPart(character, "Torso")
			local leftArm = getPart(character, "Left Arm")
			local rightArm = getPart(character, "Right Arm")
			local leftLeg = getPart(character, "Left Leg")
			local rightLeg = getPart(character, "Right Leg")

			if not head or not torso then
				return {}
			end

			local torsoSize = torso.Size
			local joints = collectJointPositions(character, {
				"Neck",
				"Left Shoulder",
				"Right Shoulder",
				"Left Hip",
				"Right Hip",
			})

			local neck = joints.Neck or partEnd(torso, 0.5)
			local leftShoulder = joints["Left Shoulder"]
				or pointFromPart(torso, Vector3.new(-torsoSize.X * 0.5, torsoSize.Y * 0.35, 0))
			local rightShoulder = joints["Right Shoulder"]
				or pointFromPart(torso, Vector3.new(torsoSize.X * 0.5, torsoSize.Y * 0.35, 0))
			local leftHip = joints["Left Hip"]
				or pointFromPart(torso, Vector3.new(-torsoSize.X * 0.25, -torsoSize.Y * 0.5, 0))
			local rightHip = joints["Right Hip"]
				or pointFromPart(torso, Vector3.new(torsoSize.X * 0.25, -torsoSize.Y * 0.5, 0))
			local pelvis = midpoint(leftHip, rightHip, partEnd(torso, -0.5))
			local shoulderCenter = midpoint(leftShoulder, rightShoulder, neck)
			local leftArmTop = partEnd(leftArm, 0.5) or leftShoulder
			local leftArmBottom = partEnd(leftArm, -0.5) or leftShoulder
			local rightArmTop = partEnd(rightArm, 0.5) or rightShoulder
			local rightArmBottom = partEnd(rightArm, -0.5) or rightShoulder
			local leftLegTop = partEnd(leftLeg, 0.5) or leftHip
			local leftLegBottom = partEnd(leftLeg, -0.5) or leftHip
			local rightLegTop = partEnd(rightLeg, 0.5) or rightHip
			local rightLegBottom = partEnd(rightLeg, -0.5) or rightHip

			return {
				{ head.Position, neck },
				{ neck, shoulderCenter },
				{ shoulderCenter, pelvis },
				{ leftShoulder, rightShoulder },
				{ leftShoulder, leftArmTop },
				{ leftArmTop, leftArmBottom },
				{ rightShoulder, rightArmTop },
				{ rightArmTop, rightArmBottom },
				{ leftLegTop, rightLegTop },
				{ pelvis, leftLegTop },
				{ leftLegTop, leftLegBottom },
				{ pelvis, rightLegTop },
				{ rightLegTop, rightLegBottom },
			}
		end

		local function getR15SkeletonSegments(character)
			local head = getPart(character, "Head")
			local upperTorso = getPart(character, "UpperTorso")
			local lowerTorso = getPart(character, "LowerTorso")
			local leftUpperArm = getPart(character, "LeftUpperArm")
			local leftLowerArm = getPart(character, "LeftLowerArm")
			local leftHand = getPart(character, "LeftHand")
			local rightUpperArm = getPart(character, "RightUpperArm")
			local rightLowerArm = getPart(character, "RightLowerArm")
			local rightHand = getPart(character, "RightHand")
			local leftUpperLeg = getPart(character, "LeftUpperLeg")
			local leftLowerLeg = getPart(character, "LeftLowerLeg")
			local leftFoot = getPart(character, "LeftFoot")
			local rightUpperLeg = getPart(character, "RightUpperLeg")
			local rightLowerLeg = getPart(character, "RightLowerLeg")
			local rightFoot = getPart(character, "RightFoot")

			if not head or not upperTorso or not lowerTorso then
				return {}
			end

			local joints = collectJointPositions(character, {
				"Neck",
				"Waist",
				"LeftShoulder",
				"LeftElbow",
				"LeftWrist",
				"RightShoulder",
				"RightElbow",
				"RightWrist",
				"LeftHip",
				"LeftKnee",
				"LeftAnkle",
				"RightHip",
				"RightKnee",
				"RightAnkle",
			})

			local neck = joints.Neck or partEnd(upperTorso, 0.5)
			local waist = joints.Waist or midpoint(upperTorso.Position, lowerTorso.Position, partEnd(lowerTorso, 0.5))
			local leftShoulder = joints.LeftShoulder
				or (leftUpperArm and midpoint(upperTorso.Position, leftUpperArm.Position, leftUpperArm.Position))
			local rightShoulder = joints.RightShoulder
				or (rightUpperArm and midpoint(upperTorso.Position, rightUpperArm.Position, rightUpperArm.Position))
			local leftElbow = joints.LeftElbow
				or (
					leftUpperArm
					and leftLowerArm
					and midpoint(leftUpperArm.Position, leftLowerArm.Position, leftLowerArm.Position)
				)
			local rightElbow = joints.RightElbow
				or (
					rightUpperArm
					and rightLowerArm
					and midpoint(rightUpperArm.Position, rightLowerArm.Position, rightLowerArm.Position)
				)
			local leftWrist = joints.LeftWrist
				or (leftLowerArm and leftHand and midpoint(leftLowerArm.Position, leftHand.Position, leftHand.Position))
			local rightWrist = joints.RightWrist
				or (
					rightLowerArm
					and rightHand
					and midpoint(rightLowerArm.Position, rightHand.Position, rightHand.Position)
				)
			local leftHip = joints.LeftHip
				or (leftUpperLeg and midpoint(lowerTorso.Position, leftUpperLeg.Position, leftUpperLeg.Position))
			local rightHip = joints.RightHip
				or (rightUpperLeg and midpoint(lowerTorso.Position, rightUpperLeg.Position, rightUpperLeg.Position))
			local leftKnee = joints.LeftKnee
				or (
					leftUpperLeg
					and leftLowerLeg
					and midpoint(leftUpperLeg.Position, leftLowerLeg.Position, leftLowerLeg.Position)
				)
			local rightKnee = joints.RightKnee
				or (
					rightUpperLeg
					and rightLowerLeg
					and midpoint(rightUpperLeg.Position, rightLowerLeg.Position, rightLowerLeg.Position)
				)
			local leftAnkle = joints.LeftAnkle
				or (leftLowerLeg and leftFoot and midpoint(leftLowerLeg.Position, leftFoot.Position, leftFoot.Position))
			local rightAnkle = joints.RightAnkle
				or (
					rightLowerLeg
					and rightFoot
					and midpoint(rightLowerLeg.Position, rightFoot.Position, rightFoot.Position)
				)
			local shoulderCenter = midpoint(leftShoulder, rightShoulder, neck)
			local hipCenter = midpoint(leftHip, rightHip, lowerTorso.Position)
			local upperTorsoTop = partEnd(upperTorso, 0.5) or neck
			local upperTorsoBottom = partEnd(upperTorso, -0.5) or waist
			local lowerTorsoTop = partEnd(lowerTorso, 0.5) or waist
			local lowerTorsoBottom = partEnd(lowerTorso, -0.5) or hipCenter
			local leftUpperArmTop = partEnd(leftUpperArm, 0.5) or leftShoulder
			local leftUpperArmBottom = partEnd(leftUpperArm, -0.5) or leftElbow
			local leftLowerArmTop = partEnd(leftLowerArm, 0.5) or leftElbow
			local leftLowerArmBottom = partEnd(leftLowerArm, -0.5) or leftWrist
			local rightUpperArmTop = partEnd(rightUpperArm, 0.5) or rightShoulder
			local rightUpperArmBottom = partEnd(rightUpperArm, -0.5) or rightElbow
			local rightLowerArmTop = partEnd(rightLowerArm, 0.5) or rightElbow
			local rightLowerArmBottom = partEnd(rightLowerArm, -0.5) or rightWrist
			local leftUpperLegTop = partEnd(leftUpperLeg, 0.5) or leftHip
			local leftUpperLegBottom = partEnd(leftUpperLeg, -0.5) or leftKnee
			local leftLowerLegTop = partEnd(leftLowerLeg, 0.5) or leftKnee
			local leftLowerLegBottom = partEnd(leftLowerLeg, -0.5) or leftAnkle
			local rightUpperLegTop = partEnd(rightUpperLeg, 0.5) or rightHip
			local rightUpperLegBottom = partEnd(rightUpperLeg, -0.5) or rightKnee
			local rightLowerLegTop = partEnd(rightLowerLeg, 0.5) or rightKnee
			local rightLowerLegBottom = partEnd(rightLowerLeg, -0.5) or rightAnkle

			return {
				{ head.Position, neck },
				{ neck, upperTorsoTop },
				{ upperTorsoTop, upperTorsoBottom },
				{ upperTorsoBottom, lowerTorsoTop },
				{ lowerTorsoTop, lowerTorsoBottom },
				{ leftShoulder, rightShoulder },
				{ shoulderCenter, leftShoulder },
				{ leftShoulder, leftUpperArmTop },
				{ leftUpperArmTop, leftUpperArmBottom },
				{ leftUpperArmBottom, leftLowerArmTop },
				{ leftLowerArmTop, leftLowerArmBottom },
				{ leftLowerArmBottom, leftHand and leftHand.Position },
				{ shoulderCenter, rightShoulder },
				{ rightShoulder, rightUpperArmTop },
				{ rightUpperArmTop, rightUpperArmBottom },
				{ rightUpperArmBottom, rightLowerArmTop },
				{ rightLowerArmTop, rightLowerArmBottom },
				{ rightLowerArmBottom, rightHand and rightHand.Position },
				{ leftHip, rightHip },
				{ hipCenter, leftHip },
				{ leftHip, leftUpperLegTop },
				{ leftUpperLegTop, leftUpperLegBottom },
				{ leftUpperLegBottom, leftLowerLegTop },
				{ leftLowerLegTop, leftLowerLegBottom },
				{ leftLowerLegBottom, leftFoot and leftFoot.Position },
				{ hipCenter, rightHip },
				{ rightHip, rightUpperLegTop },
				{ rightUpperLegTop, rightUpperLegBottom },
				{ rightUpperLegBottom, rightLowerLegTop },
				{ rightLowerLegTop, rightLowerLegBottom },
				{ rightLowerLegBottom, rightFoot and rightFoot.Position },
			}
		end

		local function getSkeletonSegments(character, humanoid)
			if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
				return getR15SkeletonSegments(character)
			end
			return getR6SkeletonSegments(character)
		end

		local function addScreenSegment(segments, fromPoint, toPoint)
			if fromPoint and toPoint then
				table.insert(segments, { fromPoint, toPoint })
			end
		end

		local function bezierPoint(a, b, c, t)
			local inv = 1 - t
			return (a * inv * inv) + (b * 2 * inv * t) + (c * t * t)
		end

		local function addCurveSegments(segments, fromPoint, controlPoint, toPoint, steps)
			steps = steps or 5
			local previous = fromPoint
			for index = 1, steps do
				local current = bezierPoint(fromPoint, controlPoint, toPoint, index / steps)
				addScreenSegment(segments, previous, current)
				previous = current
			end
		end

		local function getStyledSkeletonSegments(camera, character, humanoid, bounds)
			if not camera or not character or not bounds then
				return {}
			end

			local left = bounds.Left
			local right = bounds.Right
			local top = bounds.Top
			local bottom = bounds.Bottom
			local width = right - left
			local height = bottom - top
			if width <= 0 or height <= 0 then
				return {}
			end

			local cx = bounds.CenterX
			local fallback = {
				Head = V2(cx, top + (height * 0.18)),
				Neck = V2(cx, top + (height * 0.29)),
				Waist = V2(cx, top + (height * 0.55)),
				HipCenter = V2(cx, top + (height * 0.66)),
				LeftShoulder = V2(cx - (width * 0.22), top + (height * 0.31)),
				RightShoulder = V2(cx + (width * 0.22), top + (height * 0.31)),
				LeftHip = V2(cx - (width * 0.12), top + (height * 0.66)),
				RightHip = V2(cx + (width * 0.12), top + (height * 0.66)),
				LeftElbow = V2(cx - (width * 0.34), top + (height * 0.47)),
				RightElbow = V2(cx + (width * 0.34), top + (height * 0.47)),
				LeftHand = V2(cx - (width * 0.31), top + (height * 0.66)),
				RightHand = V2(cx + (width * 0.31), top + (height * 0.66)),
				LeftKnee = V2(cx - (width * 0.10), top + (height * 0.82)),
				RightKnee = V2(cx + (width * 0.10), top + (height * 0.82)),
				LeftFoot = V2(cx - (width * 0.13), bottom - (height * 0.05)),
				RightFoot = V2(cx + (width * 0.13), bottom - (height * 0.05)),
			}

			local function screen(position, fallbackPoint)
				return project(camera, position) or fallbackPoint
			end

			local isR15 = humanoid and humanoid.RigType == Enum.HumanoidRigType.R15
			local head = getPart(character, "Head")
			local torso = getPart(character, "Torso")
			local upperTorso = getPart(character, "UpperTorso")
			local lowerTorso = getPart(character, "LowerTorso")
			local headPoint = screen(head and head.Position, fallback.Head)
			local neck
			local waist
			local hipCenter
			local leftShoulder
			local rightShoulder
			local leftHip
			local rightHip
			local leftElbow
			local rightElbow
			local leftHand
			local rightHand
			local leftKnee
			local rightKnee
			local leftFoot
			local rightFoot

			if isR15 then
				local joints = collectJointPositions(character, {
					"Neck",
					"Waist",
					"LeftShoulder",
					"RightShoulder",
					"LeftElbow",
					"RightElbow",
					"LeftWrist",
					"RightWrist",
					"LeftHip",
					"RightHip",
					"LeftKnee",
					"RightKnee",
					"LeftAnkle",
					"RightAnkle",
				})
				local leftUpperArm = getPart(character, "LeftUpperArm")
				local rightUpperArm = getPart(character, "RightUpperArm")
				local leftLowerArm = getPart(character, "LeftLowerArm")
				local rightLowerArm = getPart(character, "RightLowerArm")
				local leftHandPart = getPart(character, "LeftHand")
				local rightHandPart = getPart(character, "RightHand")
				local leftUpperLeg = getPart(character, "LeftUpperLeg")
				local rightUpperLeg = getPart(character, "RightUpperLeg")
				local leftLowerLeg = getPart(character, "LeftLowerLeg")
				local rightLowerLeg = getPart(character, "RightLowerLeg")
				local leftFootPart = getPart(character, "LeftFoot")
				local rightFootPart = getPart(character, "RightFoot")

				neck = screen(joints.Neck or partEnd(upperTorso, 0.5), fallback.Neck)
				waist = screen(
					joints.Waist
						or (
							upperTorso
							and lowerTorso
							and midpoint(upperTorso.Position, lowerTorso.Position, lowerTorso.Position)
						),
					fallback.Waist
				)
				leftShoulder = screen(
					joints.LeftShoulder
						or (
							upperTorso
							and leftUpperArm
							and midpoint(upperTorso.Position, leftUpperArm.Position, leftUpperArm.Position)
						),
					fallback.LeftShoulder
				)
				rightShoulder = screen(
					joints.RightShoulder
						or (
							upperTorso
							and rightUpperArm
							and midpoint(upperTorso.Position, rightUpperArm.Position, rightUpperArm.Position)
						),
					fallback.RightShoulder
				)
				leftHip = screen(
					joints.LeftHip
						or (
							lowerTorso
							and leftUpperLeg
							and midpoint(lowerTorso.Position, leftUpperLeg.Position, leftUpperLeg.Position)
						),
					fallback.LeftHip
				)
				rightHip = screen(
					joints.RightHip
						or (
							lowerTorso
							and rightUpperLeg
							and midpoint(lowerTorso.Position, rightUpperLeg.Position, rightUpperLeg.Position)
						),
					fallback.RightHip
				)
				hipCenter = midpoint(leftHip, rightHip, fallback.HipCenter)
				leftElbow = screen(
					joints.LeftElbow
						or (
							leftUpperArm
							and leftLowerArm
							and midpoint(leftUpperArm.Position, leftLowerArm.Position, leftLowerArm.Position)
						),
					fallback.LeftElbow
				)
				rightElbow = screen(
					joints.RightElbow
						or (
							rightUpperArm
							and rightLowerArm
							and midpoint(rightUpperArm.Position, rightLowerArm.Position, rightLowerArm.Position)
						),
					fallback.RightElbow
				)
				leftHand = screen((leftHandPart and leftHandPart.Position) or joints.LeftWrist, fallback.LeftHand)
				rightHand = screen((rightHandPart and rightHandPart.Position) or joints.RightWrist, fallback.RightHand)
				leftKnee = screen(
					joints.LeftKnee
						or (
							leftUpperLeg
							and leftLowerLeg
							and midpoint(leftUpperLeg.Position, leftLowerLeg.Position, leftLowerLeg.Position)
						),
					fallback.LeftKnee
				)
				rightKnee = screen(
					joints.RightKnee
						or (
							rightUpperLeg
							and rightLowerLeg
							and midpoint(rightUpperLeg.Position, rightLowerLeg.Position, rightLowerLeg.Position)
						),
					fallback.RightKnee
				)
				leftFoot = screen((leftFootPart and leftFootPart.Position) or joints.LeftAnkle, fallback.LeftFoot)
				rightFoot = screen((rightFootPart and rightFootPart.Position) or joints.RightAnkle, fallback.RightFoot)
			else
				local joints = collectJointPositions(character, {
					"Neck",
					"Left Shoulder",
					"Right Shoulder",
					"Left Hip",
					"Right Hip",
				})
				local leftArm = getPart(character, "Left Arm")
				local rightArm = getPart(character, "Right Arm")
				local leftLeg = getPart(character, "Left Leg")
				local rightLeg = getPart(character, "Right Leg")

				neck = screen(joints.Neck or partEnd(torso, 0.5), fallback.Neck)
				waist = screen(torso and torso.Position, fallback.Waist)
				leftShoulder = screen(
					joints["Left Shoulder"]
						or (torso and pointFromPart(torso, Vector3.new(-torso.Size.X * 0.5, torso.Size.Y * 0.35, 0))),
					fallback.LeftShoulder
				)
				rightShoulder = screen(
					joints["Right Shoulder"]
						or (torso and pointFromPart(torso, Vector3.new(torso.Size.X * 0.5, torso.Size.Y * 0.35, 0))),
					fallback.RightShoulder
				)
				leftHip = screen(
					joints["Left Hip"]
						or (torso and pointFromPart(torso, Vector3.new(-torso.Size.X * 0.25, -torso.Size.Y * 0.5, 0))),
					fallback.LeftHip
				)
				rightHip = screen(
					joints["Right Hip"]
						or (torso and pointFromPart(torso, Vector3.new(torso.Size.X * 0.25, -torso.Size.Y * 0.5, 0))),
					fallback.RightHip
				)
				hipCenter = midpoint(leftHip, rightHip, fallback.HipCenter)
				leftElbow = screen(leftArm and leftArm.Position, fallback.LeftElbow)
				rightElbow = screen(rightArm and rightArm.Position, fallback.RightElbow)
				leftHand = screen(partEnd(leftArm, -0.5), fallback.LeftHand)
				rightHand = screen(partEnd(rightArm, -0.5), fallback.RightHand)
				leftKnee = screen(leftLeg and leftLeg.Position, fallback.LeftKnee)
				rightKnee = screen(rightLeg and rightLeg.Position, fallback.RightKnee)
				leftFoot = screen(partEnd(leftLeg, -0.5), fallback.LeftFoot)
				rightFoot = screen(partEnd(rightLeg, -0.5), fallback.RightFoot)
			end

			local shoulderControl = V2(
				(leftShoulder.X + rightShoulder.X) * 0.5,
				math.min(leftShoulder.Y, rightShoulder.Y, neck.Y) - (height * 0.018)
			)
			local hipControl =
				V2((leftHip.X + rightHip.X) * 0.5, math.min(leftHip.Y, rightHip.Y, hipCenter.Y) - (height * 0.01))
			local shoulderJoin = bezierPoint(leftShoulder, shoulderControl, rightShoulder, 0.5)
			local hipJoin = bezierPoint(leftHip, hipControl, rightHip, 0.5)

			local segments = {}
			addScreenSegment(segments, headPoint, neck)
			addCurveSegments(segments, leftShoulder, shoulderControl, rightShoulder, 7)
			addScreenSegment(segments, neck, shoulderJoin)
			addScreenSegment(segments, shoulderJoin, waist)
			addScreenSegment(segments, waist, hipJoin)
			addCurveSegments(segments, leftHip, hipControl, rightHip, 5)
			addCurveSegments(segments, leftShoulder, leftElbow, leftHand, 6)
			addCurveSegments(segments, rightShoulder, rightElbow, rightHand, 6)
			addCurveSegments(segments, leftHip, leftKnee, leftFoot, 5)
			addCurveSegments(segments, rightHip, rightKnee, rightFoot, 5)
			return segments
		end

		local function updateSkeleton(camera, data, character, humanoid, bounds)
			local segments = getStyledSkeletonSegments(camera, character, humanoid, bounds)

			while #data.skeleton < #segments do
				local line = makeLine("PlayerSkeletonEspLine", WHITE, 1, 118)
				if line then
					noSmoothLines[line] = true
				end
				table.insert(data.skeleton, line)
			end

			for index, segment in ipairs(segments) do
				local line = data.skeleton[index]
				if segment and segment[1] and segment[2] then
					updateLine(line, segment[1], segment[2], WHITE, 1)
				else
					setVisible(line, false)
				end
			end

			for index = #segments + 1, #data.skeleton do
				setVisible(data.skeleton[index], false)
			end
		end

		local function getRoot(character)
			return character and character:FindFirstChild("HumanoidRootPart")
		end

		local function getViewportBodyPoint(camera, worldPosition)
			if not worldPosition then
				return nil
			end

			local point = camera:WorldToViewportPoint(worldPosition)
			if point.Z <= 0 then
				return nil
			end
			return V2(point.X, point.Y)
		end

		local function getLowestBodyPoint(character, names)
			local lowestPoint = nil
			local lowestY = nil

			for _, name in ipairs(names) do
				local part = getPart(character, name)
				if part then
					local point = pointFromPart(part, Vector3.new(0, -part.Size.Y * 0.55, 0))
					if not lowestY or point.Y < lowestY then
						lowestPoint = point
						lowestY = point.Y
					end
				end
			end

			return lowestPoint
		end

		local function includeBoundsPoint(bounds, point)
			if not point then
				return
			end

			if not bounds.Left or point.X < bounds.Left then
				bounds.Left = point.X
			end
			if not bounds.Right or point.X > bounds.Right then
				bounds.Right = point.X
			end
			if not bounds.Top or point.Y < bounds.Top then
				bounds.Top = point.Y
			end
			if not bounds.Bottom or point.Y > bounds.Bottom then
				bounds.Bottom = point.Y
			end
			bounds.Count += 1
		end

		local function includeWorldPartBounds(bounds, part)
			if not part or not part.Parent then
				return
			end

			local half = part.Size * 0.5
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local world = part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
						bounds.MinX = bounds.MinX and math.min(bounds.MinX, world.X) or world.X
						bounds.MaxX = bounds.MaxX and math.max(bounds.MaxX, world.X) or world.X
						bounds.MinY = bounds.MinY and math.min(bounds.MinY, world.Y) or world.Y
						bounds.MaxY = bounds.MaxY and math.max(bounds.MaxY, world.Y) or world.Y
						bounds.MinZ = bounds.MinZ and math.min(bounds.MinZ, world.Z) or world.Z
						bounds.MaxZ = bounds.MaxZ and math.max(bounds.MaxZ, world.Z) or world.Z
						bounds.Count += 1
					end
				end
			end
		end

		local function projectWorldBounds(camera, worldBounds)
			local bounds = { Count = 0 }
			for x = -1, 1, 2 do
				for y = -1, 1, 2 do
					for z = -1, 1, 2 do
						local world = Vector3.new(
							x < 0 and worldBounds.MinX or worldBounds.MaxX,
							y < 0 and worldBounds.MinY or worldBounds.MaxY,
							z < 0 and worldBounds.MinZ or worldBounds.MaxZ
						)
						local viewportPoint = camera:WorldToViewportPoint(world)
						if viewportPoint.Z > 0 then
							includeBoundsPoint(bounds, V2(viewportPoint.X, viewportPoint.Y))
						end
					end
				end
			end
			return bounds
		end

		local function smoothNumber(previous, current, alpha)
			if previous == nil then
				return current
			end
			return previous + ((current - previous) * alpha)
		end

		local function smoothBounds(data, bounds)
			if not data or not bounds then
				return bounds
			end

			local previous = data.bounds
			if not previous then
				data.bounds = bounds
				return bounds
			end

			local dx = math.abs((bounds.CenterX or 0) - (previous.CenterX or 0))
			local dy = math.abs((bounds.CenterY or 0) - (previous.CenterY or 0))
			if dx > BOUNDS_RESET_DISTANCE or dy > BOUNDS_RESET_DISTANCE then
				data.bounds = bounds
				return bounds
			end

			local nextBounds = {
				Left = smoothNumber(previous.Left, bounds.Left, frameSmoothingAlpha),
				Right = smoothNumber(previous.Right, bounds.Right, frameSmoothingAlpha),
				Top = smoothNumber(previous.Top, bounds.Top, frameSmoothingAlpha),
				Bottom = smoothNumber(previous.Bottom, bounds.Bottom, frameSmoothingAlpha),
				CenterX = smoothNumber(previous.CenterX, bounds.CenterX, frameSmoothingAlpha),
				CenterY = smoothNumber(previous.CenterY, bounds.CenterY, frameSmoothingAlpha),
			}
			data.bounds = nextBounds
			return nextBounds
		end

		local function getCharacterScreenBounds(camera, character, humanoid)
			local root = getRoot(character)
			if not camera or not root then
				return nil
			end
			local projected, onScreen = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 1.35, 0))
			if not onScreen or projected.Z <= 0 then
				return nil
			end
			local left = snap(projected.X - REFERENCE_BOX_WIDTH * 0.5)
			local top = snap(projected.Y - REFERENCE_BOX_HEIGHT * 0.5)
			local right = left + REFERENCE_BOX_WIDTH
			local bottom = top + REFERENCE_BOX_HEIGHT

			return {
				Left = left,
				Right = right,
				Top = top,
				Bottom = bottom,
				CenterX = (left + right) * 0.5,
				CenterY = (top + bottom) * 0.5,
			}
		end

		local function isAlive(character)
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			return humanoid and humanoid.Health > 0, humanoid
		end

		local function getPlayerColor(player)
			if player.TeamColor then
				return player.TeamColor.Color
			end
			return C3(255, 255, 255)
		end

		local function resolveIntel(player, character)
			local resolver = settings.IntelResolver
			if type(resolver) ~= "function" then
				return nil
			end

			local now = os.clock()
			local cached = intelCache[player]
			if cached and cached.character == character and now - cached.updatedAt < INTEL_INTERVAL then
				return cached.value
			end

			local worker = coroutine.create(resolver)
			local success, value = coroutine.resume(worker, player, character)
			if coroutine.status(worker) ~= "dead" then
				coroutine.close(worker)
				success = false
			end
			value = success and type(value) == "table" and value or nil
			intelCache[player] = {
				character = character,
				updatedAt = now,
				value = value,
			}
			return value
		end

		local function updateSkillTiles(data, skills, right, top, boxHeight)
			local skillCount = 0
			for index = 1, #(data.skillTiles or {}) do
				if type(skills and skills[index]) == "table" then
					skillCount += 1
				end
			end
			local tileSize = skillCount > 0 and boxHeight / skillCount or 0
			for index, tile in ipairs(data.skillTiles or {}) do
				local skill = skills and skills[index]
				if not tile or not settings.Skills or type(skill) ~= "table" then
					if tile then
						tile.Ratio = nil
						setVisible(tile.Back, false)
					end
				else
					local stateName = tostring(skill.State or "PRESENT")
					local remaining = tonumber(skill.Remaining)
					local duration = tonumber(skill.Duration)
					local valueText = ""
					local ratio = 0
					if remaining and remaining > 0 then
						valueText = remaining < 10 and string.format("%.1f", remaining)
							or tostring(math.ceil(remaining))
						ratio = duration and duration > 0 and math.clamp(remaining / duration, 0, 1) or 1
					elseif stateName == "SPENT" then
						valueText = "X"
						ratio = 1
					elseif stateName == "COOLDOWN_UNKNOWN" then
						valueText = "?"
						ratio = 1
					elseif stateName == "MISSING" then
						valueText = "-"
						ratio = 0
					end

					local name = tostring(skill.Name or skill.ShortName or "?")
					local shortName = name
					if tileSize < 25 then
						shortName = string.sub(name, 1, 1)
					elseif tileSize < 40 then
						shortName = string.sub(name, 1, 3)
					end
					if valueText == "" then
						valueText = shortName
					end
					tile.Back.Position = UDim2.fromOffset(right + 2, top + (index - 1) * tileSize)
					tile.Back.Size = UDim2.fromOffset(tileSize, tileSize)
					tile.Label.TextSize = tileSize >= 25 and 10 or 9
					tile.Label.Text = valueText
					tile.Label.TextColor3 = WHITE
					tile.Label.Visible = tileSize >= 15
					tile.Key.Visible = false
					tile.Fill.BackgroundColor3 = C3(255, 0, 0)
					tile.Ratio = tile.Ratio and tile.Ratio + (ratio - tile.Ratio) * frameValueAlpha or ratio
					tile.Fill.Size = UDim2.new(tile.Ratio, 0, 1, 0)
					tile.Stroke.Color = WHITE
					tile.Back.Visible = true
				end
			end
		end

		local function updateIntel(data, intel, distance, bounds)
			local left = bounds.Left
			local right = bounds.Right
			local top = bounds.Top
			local bottom = bounds.Bottom
			local boxWidth = right - left

			if data.distance then
				data.distance.Text = string.format("%.0f studs", distance)
				data.distance.Position = UDim2.fromOffset(left, bottom + 10)
				data.distance.Visible = settings.Distance
			end

			local ultimate = intel and tonumber(intel.Ultimate)
			if settings.Ultimate and ultimate and (ultimate > 0 or intel.UltimateActive) then
				local ultimateRemaining = intel and tonumber(intel.UltimateRemaining)
				local ultimateDuration = intel and tonumber(intel.UltimateDuration)
				local targetRatio = intel.UltimateActive
						and ultimateRemaining
						and ultimateDuration
						and ultimateDuration > 0
						and math.clamp(ultimateRemaining / ultimateDuration, 0, 1)
					or math.clamp(ultimate / 100, 0, 1)
				data.ultimateRatio = smoothNumber(data.ultimateRatio, targetRatio, frameValueAlpha)
				local barY = bottom + 6
				updateLine(data.ultimateBack, V2(left, barY), V2(right, barY), C3(5, 8, 13), 4)
				updateLine(
					data.ultimateFill,
					V2(left, barY),
					V2(left + (boxWidth * data.ultimateRatio), barY),
					intel.UltimateActive and C3(255, 86, 146) or C3(181, 94, 255),
					2
				)
				if data.ultimate then
					data.ultimate.Text = intel.UltimateActive
							and (ultimateRemaining and string.format("ULT %.1fs", ultimateRemaining) or "ULT ACTIVE")
						or string.format("ULT %.0f%%", ultimate)
					data.ultimate.TextColor3 = intel.UltimateActive and C3(255, 111, 158) or C3(218, 174, 255)
					data.ultimate.Position = UDim2.fromOffset(right, barY + 10)
					data.ultimate.Visible = true
				end
			else
				data.ultimateRatio = nil
				setVisible(data.ultimateBack, false)
				setVisible(data.ultimateFill, false)
				setVisible(data.ultimate, false)
			end

			updateSkillTiles(data, intel and intel.Skills, right, top, bottom - top)

			local labelY = top - (settings.Name and 23 or 10)
			if data.character then
				data.character.Text = intel and tostring(intel.CharacterText or "Unknown Character")
					or "Unknown Character"
				local characterColor = intel and intel.CharacterColor
				data.character.TextColor3 = typeof(characterColor) == "Color3" and characterColor or C3(125, 220, 255)
				data.character.Position = UDim2.fromOffset(bounds.CenterX, labelY)
				data.character.Visible = settings.Character
				if settings.Character then
					labelY -= 13
				end
			end

			if data.status then
				local statusText = intel and tostring(intel.StatusText or "") or ""
				data.status.Text = statusText
				local statusColor = intel and intel.StatusColor
				data.status.TextColor3 = typeof(statusColor) == "Color3" and statusColor or C3(255, 92, 102)
				data.status.Position = UDim2.fromOffset(bounds.CenterX, labelY)
				data.status.Visible = settings.Status and statusText ~= ""
			end
		end

		local function updateCornerBox(data, bounds)
			local left = bounds.Left
			local right = bounds.Right
			local top = bounds.Top
			local bottom = bounds.Bottom
			local points = {
				{ V2(left, top), V2(right, top) },
				{ V2(right, top), V2(right, bottom) },
				{ V2(right, bottom), V2(left, bottom) },
				{ V2(left, bottom), V2(left, top) },
			}
			for index, segment in ipairs(points) do
				updateLine(data.box[index], segment[1], segment[2], WHITE, 1)
			end
		end

		local function anyEnabled()
			return settings.Box
				or settings.Name
				or settings.Character
				or settings.Health
				or settings.Team
				or settings.Tracers
				or settings.Skeleton
				or settings.HeldItem
				or settings.Distance
				or settings.Ultimate
				or settings.Skills
				or settings.Status
		end

		local function render(deltaTime)
			if destroyed then
				return
			end
			local safeDelta = math.clamp(tonumber(deltaTime) or (1 / 60), 1 / 240, 0.1)
			frameSmoothingAlpha = 1 - math.exp(-POSITION_RESPONSE * safeDelta)
			frameValueAlpha = 1 - math.exp(-VALUE_RESPONSE * safeDelta)
			local camera = workspace.CurrentCamera
			local localRoot = getRoot(LocalPlayer and LocalPlayer.Character)
			if not camera or not localRoot then
				for _, data in pairs(tracked) do
					hideData(data)
				end
				return
			end

			local seen = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= LocalPlayer then
					seen[player] = true
					local data = makePlayerData(player)
					local character = player.Character
					local alive, humanoid = isAlive(character)
					local root = getRoot(character)
					if not alive or not root then
						hideData(data)
					else
						local distance = (root.Position - localRoot.Position).Magnitude
						if distance > settings.MaxDistance then
							hideData(data)
						else
							local bounds = getCharacterScreenBounds(camera, character, humanoid)
							if not bounds then
								hideData(data)
							else
								bounds = smoothBounds(data, bounds)
								local left = bounds.Left
								local right = bounds.Right
								local top = bounds.Top
								local bottom = bounds.Bottom
								local color = WHITE
								local boxWidth = right - left

								if settings.Box then
									updateCornerBox(data, bounds)
								else
									hideList(data.box)
								end

								updateNameLabel(
									data.name,
									player.DisplayName or player.Name,
									bounds.CenterX,
									top,
									boxWidth
								)

								if data.team then
									data.team.Text = player.Team and player.Team.Name or "No Team"
									data.team.TextColor3 = WHITE
									data.team.Position = UDim2.fromOffset(right + 8, top + 8)
									data.team.Visible = settings.Team
								end

								if settings.Health then
									local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
									data.healthRatio = smoothNumber(data.healthRatio, ratio, frameValueAlpha)
									updateLine(
										data.healthBack,
										V2(left - 8, top - 1),
										V2(left - 8, bottom + 1),
										C3(0, 0, 0),
										7
									)
									updateLine(
										data.healthFill,
										V2(left - 8, bottom),
										V2(left - 8, bottom - (bottom - top) * data.healthRatio),
										C3(0, 255, 80),
										5
									)
								else
									data.healthRatio = nil
									setVisible(data.healthBack, false)
									setVisible(data.healthFill, false)
								end

								if settings.Tracers then
									updateLine(
										data.tracer,
										V2(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y - 8),
										V2(bounds.CenterX, bottom),
										color,
										1
									)
								else
									setVisible(data.tracer, false)
								end

								if settings.Skeleton then
									updateSkeleton(camera, data, character, humanoid, bounds)
								else
									hideList(data.skeleton)
								end

								if data.heldItem then
									local tool = character:FindFirstChildWhichIsA("Tool")
									data.heldItem.Text = tool and tool.Name or ""
									data.heldItem.Position = UDim2.fromOffset(bounds.CenterX, bottom + 24)
									data.heldItem.Visible = settings.HeldItem and tool ~= nil
								end

								local intel = nil
								if settings.Character or settings.Ultimate or settings.Skills or settings.Status then
									intel = resolveIntel(player, character)
								end
								updateIntel(data, intel, distance, bounds)
							end
						end
					end
				end
			end

			for player in pairs(tracked) do
				if not seen[player] or not player.Parent then
					removePlayerData(player)
				end
			end
		end

		local function updateLoop()
			if destroyed then
				return
			end
			if anyEnabled() then
				if not renderConnection then
					renderConnection = RunService.RenderStepped:Connect(function(deltaTime)
						pcall(render, deltaTime)
					end)
				end
				pcall(render, 1 / 60)
			else
				if renderConnection then
					renderConnection:Disconnect()
					renderConnection = nil
				end
				for _, data in pairs(tracked) do
					hideData(data)
				end
			end
		end

		local api = {}
		api.SupportsStructuredSkills = true

		function api:Init()
			updateLoop()
		end

		function api:SetBoxEsp(value)
			settings.Box = value == true
			updateLoop()
		end

		function api:SetNameEsp(value)
			settings.Name = value == true
			updateLoop()
		end

		function api:SetCharacterEsp(value)
			settings.Character = value == true
			updateLoop()
		end

		function api:SetHealthEsp(value)
			settings.Health = value == true
			updateLoop()
		end

		function api:SetTeamEsp(value)
			settings.Team = value == true
			updateLoop()
		end

		function api:SetTracers(value)
			settings.Tracers = value == true
			updateLoop()
		end

		function api:SetSkeletonEsp(value)
			settings.Skeleton = value == true
			updateLoop()
		end

		function api:SetHeldItemEsp(value)
			settings.HeldItem = value == true
			updateLoop()
		end

		function api:SetDistanceEsp(value)
			settings.Distance = value == true
			updateLoop()
		end

		function api:SetUltimateEsp(value)
			settings.Ultimate = value == true
			updateLoop()
		end

		function api:SetSkillsEsp(value)
			settings.Skills = value == true
			updateLoop()
		end

		function api:SetStatusEsp(value)
			settings.Status = value == true
			updateLoop()
		end

		function api:SetIntelResolver(resolver)
			settings.IntelResolver = type(resolver) == "function" and resolver or nil
			table.clear(intelCache)
			updateLoop()
		end

		function api:SetMaxDist(value)
			settings.MaxDistance = tonumber(value) or settings.MaxDistance
			updateLoop()
		end

		function api:Destroy()
			if destroyed then
				return
			end
			destroyed = true
			settings.IntelResolver = nil
			if renderConnection then
				renderConnection:Disconnect()
				renderConnection = nil
			end
			if playerRemovingConnection then
				playerRemovingConnection:Disconnect()
				playerRemovingConnection = nil
			end
			for player in pairs(tracked) do
				removePlayerData(player)
			end
			table.clear(intelCache)
			table.clear(textMeasureCache)
			table.clear(linePoints)
			table.clear(noSmoothLines)
			if playerEspGui then
				destroyObject(playerEspGui)
				playerEspGui = nil
			end
		end
		destroyOwner = function()
			api:Destroy()
		end

		return api
	end

	function PlayerESP.new(window, options)
		options = options or {}
		local api = createGuiEspModule(options, {
			Players = Players,
			RunService = RunService,
			TextService = TextService,
			Client = Players.LocalPlayer,
			getHiddenParent = function()
				return options.Parent or window.Gui.Parent
			end,
		})
		window.Scope:Add(api)
		local destroy = api.Destroy
		function api:Destroy()
			window.Scope.Resources[self] = nil
			destroy(self)
		end
		return api
	end

	local FEATURES = {
		{ "Box", "Box ESP", "SetBoxEsp" },
		{ "Name", "Name ESP", "SetNameEsp" },
		{ "Character", "Character ESP", "SetCharacterEsp" },
		{ "Health", "Health ESP", "SetHealthEsp" },
		{ "Team", "Team ESP", "SetTeamEsp" },
		{ "Tracers", "Tracers", "SetTracers" },
		{ "Skeleton", "Skeleton ESP", "SetSkeletonEsp" },
		{ "HeldItem", "Held Item ESP", "SetHeldItemEsp" },
		{ "Distance", "Distance ESP", "SetDistanceEsp" },
		{ "Ultimate", "Ultimate ESP", "SetUltimateEsp" },
		{ "Skills", "Skills ESP", "SetSkillsEsp" },
		{ "Status", "Status ESP", "SetStatusEsp" },
	}

	function PlayerESP.section(menu, options)
		options = options or {}
		local section = options.Section
			or menu:AddSection({
				Name = options.Name or "Player ESP",
				Icon = options.Icon or "eye",
				Column = options.Column or 1,
			})
		local window = section.Window
		local scope = Core.scope(section.Scope)
		local supplied = options.ESP or options.Esp or options.Module
		local esp = supplied or PlayerESP.new(window, options)
		local state = { Preview = options.PreviewDefault ~= false, MaxDistance = options.MaxDistance or 1000 }
		local api = { ESP = esp, Section = section, State = state, Controls = {}, Scope = scope }
		local function invoke(method, ...)
			if esp and type(esp[method]) == "function" then
				Core.callback(esp[method], esp, ...)
			end
		end
		local preview
		local previewLabels = {}
		local function refresh()
			if not scope.Alive or not preview then
				return
			end
			preview.Root.Visible = state.Preview
			for name, label in pairs(previewLabels) do
				label.Visible = state[name] == true
			end
		end
		local function changed(name, value)
			refresh()
			Core.callback(options["On" .. name .. "Changed"], value, api)
			Core.callback(options.Callback, name, value, api)
		end
		if options.Preview ~= false then
			api.Controls.Preview = section:AddToggle({
				Name = options.PreviewToggleName or "ESP Preview",
				Default = state.Preview,
				Callback = function(value)
					state.Preview = value
					changed("Preview", value)
				end,
			})
		end
		for _, feature in ipairs(FEATURES) do
			local name, label, method = table.unpack(feature)
			state[name] = options[name .. "Default"] == true
			if options[name .. "Control"] ~= false then
				api.Controls[name] = section:AddToggle({
					Name = label,
					Default = state[name],
					Tooltip = "Show " .. string.lower(label) .. " for streamed players within the configured distance.",
					Callback = function(value)
						state[name] = value
						invoke(method, value)
						changed(name, value)
					end,
				})
			end
			invoke(method, state[name])
			if name == "Box" then
				Core.callback(options.AfterBox, section, api)
			end
		end
		if options.MaxDistanceControl ~= false then
			api.Controls.MaxDistance = section:AddSlider({
				Name = "Max Distance",
				Min = options.MinDistance or 100,
				Max = options.MaxDistanceLimit or 5000,
				Default = state.MaxDistance,
				Suffix = options.DistanceSuffix or " studs",
				Callback = function(value)
					state.MaxDistance = value
					invoke("SetMaxDist", value)
					changed("MaxDistance", value)
				end,
			})
		end
		if options.Preview ~= false then
			preview = section:Custom({
				Name = options.PreviewTitle or "ESP Preview",
				Height = options.PreviewHeight or 235,
				Searchable = false,
			})
			local root = preview.Body
			local bounds = Core.new("Frame", {
				Name = "Box",
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.34, 0.16),
				Size = UDim2.fromScale(0.32, 0.64),
			}, root)
			Core.stroke(bounds, window)
			previewLabels.Box = bounds
			local head = Core.new("Frame", {
				Name = "Head",
				Position = UDim2.fromScale(0.45, 0.21),
				Size = UDim2.fromScale(0.1, 0.11),
				BorderSizePixel = 0,
			}, root)
			Core.bind(window, head, "BackgroundColor3", "TextMuted")
			Core.round(head, window)
			local body = Core.new("Frame", {
				Name = "Body",
				Position = UDim2.fromScale(0.4, 0.34),
				Size = UDim2.fromScale(0.2, 0.38),
				BorderSizePixel = 0,
			}, root)
			Core.bind(window, body, "BackgroundColor3", "SurfaceActive")
			Core.round(body, window)
			local labels = {
				Name = { "Player", 0.32, 0.05 },
				Character = { "Character", 0.67, 0.2 },
				Team = { "Team", 0.67, 0.3 },
				HeldItem = { "Held item", 0.3, 0.81 },
				Distance = { "125 studs", 0.3, 0.89 },
				Ultimate = { "Ultimate 75%", 0.02, 0.83 },
				Skills = { "Skill 1 · Skill 2", 0.03, 0.93 },
				Status = { "Ready", 0.67, 0.4 },
			}
			for name, data in pairs(labels) do
				local label = Core.text(window, root, data[1], 10, name == "Status" and "Success" or "TextSecondary")
				label.Position = UDim2.fromScale(data[2], data[3])
				label.Size = UDim2.fromScale(0.35, 0.08)
				previewLabels[name] = label
			end
			local health = Core.new("Frame", {
				Name = "Health",
				Position = UDim2.fromScale(0.29, 0.22),
				Size = UDim2.fromScale(0.015, 0.58),
				BorderSizePixel = 0,
			}, root)
			Core.bind(window, health, "BackgroundColor3", "Success")
			previewLabels.Health = health
			local skeleton = Core.new("Frame", {
				Name = "Skeleton",
				Position = UDim2.fromScale(0.495, 0.34),
				Size = UDim2.fromScale(0.01, 0.38),
				BorderSizePixel = 0,
			}, root)
			Core.bind(window, skeleton, "BackgroundColor3", "Text")
			previewLabels.Skeleton = skeleton
			local tracer = Core.new("Frame", {
				Name = "Tracer",
				Position = UDim2.fromScale(0.495, 0.81),
				Size = UDim2.fromScale(0.005, 0.19),
				BorderSizePixel = 0,
			}, root)
			Core.bind(window, tracer, "BackgroundColor3", "Accent")
			previewLabels.Tracers = tracer
			api.Preview = {
				Frame = preview.Root,
				Box = bounds,
				Refresh = refresh,
				SetVisible = function(_, value)
					state.Preview = value == true
					if api.Controls.Preview then
						api.Controls.Preview:Set(state.Preview)
					end
					refresh()
				end,
			}
			if window.Tooltip then
				window:Tooltip(root, "Preview of player overlay labels and feature visibility.", scope)
			end
		end
		function api:SetEsp(nextEsp)
			if not scope.Alive or nextEsp == esp then
				return self
			end
			if esp and type(esp.Destroy) == "function" then
				Core.callback(esp.Destroy, esp)
			end
			esp = nextEsp
			self.ESP = nextEsp
			invoke("Init")
			for _, feature in ipairs(FEATURES) do
				invoke(feature[3], state[feature[1]])
			end
			invoke("SetMaxDist", state.MaxDistance)
			invoke("SetIntelResolver", options.IntelResolver)
			return self
		end
		function api:GetState()
			return table.clone(state)
		end
		function api:RefreshPreview()
			refresh()
			return self
		end
		function api:Destroy()
			scope:Destroy()
			section:Destroy()
		end
		scope:Add(function()
			if esp and type(esp.Destroy) == "function" then
				Core.callback(esp.Destroy, esp)
			end
			esp = nil
			api.ESP = nil
			table.clear(previewLabels)
		end)
		invoke("Init")
		invoke("SetMaxDist", state.MaxDistance)
		invoke("SetIntelResolver", options.IntelResolver)
		refresh()
		return api
	end

	return PlayerESP
end
