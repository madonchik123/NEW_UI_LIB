return function(require)
	local Players = game:GetService("Players")
	local Core = require("Core")
	local GameCatalog = require("GameCatalog")
	local Account = require("Account")
	local Overview = {}
	local function compact(card, gap)
		card.Body.UIListLayout.Padding = UDim.new(0, gap or 0)
		return card
	end
	function Overview.mount(window, options)
		options = options or {}
		local player = Players.LocalPlayer
		local username = player.Name
		local overview = window:Page({ Name = "Overview", Icon = "home", Group = "Workspace" })
		local avatarImage = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
		local avatar = Core.new("ImageLabel", {
			Name = "Avatar",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(24, 28),
			Position = UDim2.fromOffset(7, 6),
			Image = avatarImage,
		}, window.ProfileButton)
		window.ProfileButton:FindFirstChild("Text").Visible = false
		local welcome = overview:Card({ Title = "Welcome", Header = false, Collapsible = false })
		local hero = welcome:Custom({ Name = "Welcome to Unknown Hub", Height = 72 })
		Core.new("ImageLabel", {
			Name = "Avatar",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(48, 56),
			Position = UDim2.fromOffset(0, 8),
			Image = avatarImage,
		}, hero.Body)
		local title = Core.text(window, hero.Body, "Welcome to Unknown Hub, @" .. username, 13)
		title.Position = UDim2.fromOffset(62, 0)
		title.Size = UDim2.new(1, -62, 0, 20)
		local function fitWelcome()
			title.Text = hero.Root.AbsoluteSize.X < 330 and ("Welcome, @" .. username)
				or ("Welcome to Unknown Hub, @" .. username)
		end
		hero.Scope:Add(hero.Root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWelcome))
		fitWelcome()
		local method = Core.text(window, hero.Body, "", 11)
		method.Position = UDim2.fromOffset(62, 25)
		method.Size = UDim2.new(1, -62, 0, 16)
		local executions = Core.text(window, hero.Body, "", 11)
		executions.Position = UDim2.fromOffset(62, 43)
		executions.Size = UDim2.new(1, -62, 0, 15)
		local remaining = Core.text(window, hero.Body, "", 11)
		remaining.Position = UDim2.fromOffset(62, 59)
		remaining.Size = UDim2.new(1, -62, 0, 14)
		Account.mount(window, { Access = method, Session = executions, Remaining = remaining }, options.SessionStats)
		local left, right = overview:Columns()
		local credits = compact(left:Card({ Title = "Credits", Icon = "user" }))
		local creditText = credits:Custom({ Name = "Credits text", Height = 28 })
		local creditLabel = Core.text(
			window,
			creditText.Body,
			"Credits to the Unknown Hub developers.\nThanks for supporting Unknown Hub :)",
			11
		)
		creditLabel.TextWrapped = true
		creditLabel.TextTruncate = Enum.TextTruncate.None
		creditLabel.Size = UDim2.fromScale(1, 1)
		local gameCard = compact(left:Card({ Title = "Game", Icon = "game" }))
		local gameInfo = gameCard:Custom({ Name = "Game information", Height = 55 })
		local information = Core.text(window, gameInfo.Body, "", 11)
		information.TextYAlignment = Enum.TextYAlignment.Top
		information.TextTruncate = Enum.TextTruncate.None
		information.Size = UDim2.fromScale(1, 1)
		local version = right:Card({ Title = "Version", Icon = "version", Expanded = false })
		version:InfoRow({ Name = "Library version", Value = window.Version or "2.0.0" })

		local supported = options.SupportedGames or GameCatalog.rows(GameCatalog.Snapshot)
		local gameList = right:ListCard({
			Title = "Games Supported",
			Icon = "game",
			Items = supported,
			Height = 145,
			Footer = tostring(#supported) .. " games / scroll to view",
		})
		if #supported == 0 then
			gameList:Label({ Name = "No game modules loaded" })
		end
		if not options.SupportedGames then
			Core.delay(gameList.Scope, 0, function()
				local storage = window.Config.Storage
				if not storage.GetGames then
					return
				end
				local ok, games = storage:GetGames()
				if ok and gameList.Scope.Alive then
					gameList:SetItems(GameCatalog.rows(games))
					gameList:SetFooter(tostring(#games) .. " games / scroll to view")
				end
			end)
		end

		local started = os.clock()
		local function update()
			if not overview.Scope.Alive then
				return
			end
			local seconds = math.floor(os.clock() - started)
			local elapsed =
				string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
			information.Text = "Time elapsed: "
				.. elapsed
				.. "\nPlace version: "
				.. game.PlaceVersion
				.. "\nPlace ID: "
				.. game.PlaceId
				.. "\nServer: "
				.. "Live"
			Core.delay(overview.Scope, 1, update)
		end
		update()
		overview:Select()
		return { Page = overview, Games = gameList, Welcome = welcome, Account = window.Account }
	end

	return Overview
end
