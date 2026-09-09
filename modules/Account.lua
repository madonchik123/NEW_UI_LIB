return function(require)
	local Core = require("Core")

	local Account = {}
	Account.__index = Account

	local accessNames = {
		premium = "Premium",
		lootlabs = "Free",
		developer = "Developer",
		["local"] = "Local",
	}

	local function finite(value)
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end

	local function duration(seconds)
		seconds = math.max(0, math.floor(seconds))
		return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
	end

	function Account:GetStatus()
		local now = os.clock()
		local keys = self.Window.KeySystem
		local enabled = keys ~= nil and keys.Enabled == true
		local verified = not enabled or keys.Verified == true
		local metadata = keys and keys.Metadata
		if metadata ~= self.Metadata then
			self.Metadata = metadata
			self.MetadataTime = keys and keys.MetadataReceivedAt or now
			local seconds = type(metadata) == "table" and metadata.secondsRemaining
			self.InitialRemaining = if finite(seconds) then math.max(0, seconds) else nil
		end
		metadata = if type(metadata) == "table" then metadata else nil
		local keyType = metadata and metadata.keyType
		local noExpiry = verified and enabled and metadata ~= nil and metadata.noExpiry == true
		local remaining = if verified
				and enabled
				and not noExpiry
				and self.InitialRemaining ~= nil
			then math.max(0, math.ceil(self.InitialRemaining - (now - self.MetadataTime)))
			else nil
		local access = if not enabled
			then "No key required"
			elseif not verified then "Unverified"
			else accessNames[keyType] or "Verified"
		local remainingText = if noExpiry then "Lifetime" elseif remaining ~= nil then duration(remaining) else "—"
		return table.freeze({
			Access = access,
			Enabled = enabled,
			Verified = verified,
			KeyType = keyType,
			NoExpiry = noExpiry,
			RemainingSeconds = remaining,
			RemainingText = remainingText,
			ExpiresAt = metadata and metadata.expiresAt,
			HwidBound = metadata and metadata.hwidBound,
			SessionSeconds = math.max(0, math.floor(now - self.StartedAt)),
			Executions = self.Executions,
		})
	end

	function Account:_render()
		if not self.Scope.Alive then
			return
		end
		local status = self:GetStatus()
		local labels = self.Labels
		local access = "Access: " .. status.Access
		local remaining = "Remaining time: " .. status.RemainingText
		local session = if status.Executions ~= nil
			then "Executions: " .. tostring(status.Executions)
			else "Session time: " .. duration(status.SessionSeconds)
		if labels.Access.Text ~= access then
			labels.Access.Text = access
		end
		if labels.Remaining.Text ~= remaining then
			labels.Remaining.Text = remaining
		end
		if labels.Session.Text ~= session then
			labels.Session.Text = session
		end
		local color = if not status.Enabled then "TextSecondary" elseif status.Verified then "Success" else "Warning"
		if self.AccessColor ~= color then
			self.AccessColor = color
			Core.bind(self.Window, labels.Access, "TextColor3", color)
		end
	end

	function Account:SetStats(stats)
		if not self.Scope.Alive or type(stats) ~= "table" then
			return false
		end
		local executions = stats.Executions
		if executions ~= nil and (not finite(executions) or executions < 0) then
			return false
		end
		self.Executions = if executions ~= nil then math.floor(executions) else nil
		self:_render()
		return true
	end

	function Account:Destroy()
		self.Scope:Destroy()
	end

	function Account.mount(window, labels, options)
		options = options or {}
		assert(labels and labels.Access and labels.Remaining and labels.Session, "Account requires three status labels")
		if window.Account then
			window.Account:Destroy()
		end
		local scope = Core.scope(window.Scope)
		local self = setmetatable({
			Window = window,
			Labels = labels,
			Scope = scope,
			StartedAt = os.clock(),
			MetadataTime = os.clock(),
		}, Account)
		local function setStats(_, stats)
			return self:SetStats(stats)
		end
		window.Account = self
		window.SetSessionStats = setStats
		scope:Add(function()
			if window.Account == self then
				window.Account = nil
			end
			if window.SetSessionStats == setStats then
				window.SetSessionStats = nil
			end
			self.Metadata = nil
		end)
		for _, label in ipairs({ labels.Access, labels.Remaining, labels.Session }) do
			scope:Add(label.Destroying:Connect(function()
				self:Destroy()
			end))
		end
		if window.KeySystem then
			window.KeySystem:Subscribe(scope, function()
				self:_render()
			end)
		end
		if options.SessionStats then
			self:SetStats(options.SessionStats)
		elseif options.Executions ~= nil then
			self:SetStats(options)
		end
		local function tick()
			if not scope.Alive then
				return
			end
			self:_render()
			if scope.Alive then
				Core.delay(scope, 1, tick)
			end
		end
		tick()
		return self
	end

	return Account
end
