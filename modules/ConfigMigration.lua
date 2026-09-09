return function(require)
	local Migration = {}
	local kinds = {
		toggle = "Toggle",
		slider = "Slider",
		input = "Textbox",
		textbox = "Textbox",
		dropdown = "Dropdown",
		multi = "MultiDropdown",
		multidropdown = "MultiDropdown",
		colorpicker = "ColorPicker",
		keybind = "Keybind",
	}

	local function finite(value)
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end

	local function pack(value, depth, seen, budget)
		depth, seen, budget = depth or 0, seen or {}, budget or { Count = 0 }
		budget.Count += 1
		assert(depth <= 16 and budget.Count <= 16384, "Legacy value exceeds structure limits")
		if type(value) == "boolean" then
			return value
		end
		if type(value) == "string" then
			assert(#value <= 16384, "Legacy string is too long")
			return value
		end
		if type(value) == "number" then
			assert(finite(value), "Legacy number is invalid")
			return value
		end
		assert(type(value) == "table" and not seen[value] and getmetatable(value) == nil, "Unsupported legacy value")
		if value.__type == "Color3" then
			assert(finite(value.R) and finite(value.G) and finite(value.B), "Invalid legacy color")
			return { Tag = "Color3", Value = { value.R, value.G, value.B } }
		end
		seen[value] = true
		local entries = {}
		for key, child in pairs(value) do
			assert(
				(type(key) == "string" and #key <= 256) or (finite(key) and key % 1 == 0),
				"Invalid legacy table key"
			)
			assert(#entries < 2048, "Too many legacy table entries")
			table.insert(entries, { Key = key, Value = pack(child, depth + 1, seen, budget) })
		end
		seen[value] = nil
		return { Tag = "Table", Value = entries }
	end

	function Migration.Convert(payload, items)
		local ok, document, note = pcall(function()
			assert(
				type(payload) == "table" and payload.Version == nil and getmetatable(payload) == nil,
				"Not a legacy configuration"
			)
			local lookup = {}
			for id, item in pairs(items or {}) do
				lookup[id] = { Id = id, Item = item }
				for _, alias in ipairs(item.Options and item.Options.Aliases or {}) do
					if not lookup[alias] then
						lookup[alias] = { Id = id, Item = item }
					end
				end
			end
			local profile = {}
			local preferences = { ActiveProfile = "Default", LoadSettings = true, Values = {} }
			local interface = { Tag = "Table", Value = {} }
			local count = 0
			local mapped = {}
			for id, entry in pairs(payload) do
				count += 1
				assert(count <= 2048 and type(id) == "string" and #id > 0 and #id <= 256, "Invalid legacy control ID")
				assert(
					type(entry) == "table"
						and type(entry.type) == "string"
						and #entry.type > 0
						and #entry.type <= 64
						and entry.value ~= nil,
					"Invalid legacy control entry"
				)
				local value = entry.value
				local match = lookup[id]
				local target = match and match.Id or id
				local kind = match and match.Item.Kind or kinds[entry.type:lower()] or entry.type
				local encoded
				if kind == "ColorPicker" and type(value) == "table" and value.R ~= nil then
					assert(finite(value.R) and finite(value.G) and finite(value.B), "Invalid legacy colorpicker value")
					assert(
						value.R >= 0
							and value.R <= 255
							and value.G >= 0
							and value.G <= 255
							and value.B >= 0
							and value.B <= 255,
						"Legacy color exceeds RGB bounds"
					)
					encoded = { Tag = "Color3", Value = { value.R / 255, value.G / 255, value.B / 255 } }
				else
					encoded = pack(value)
				end
				mapped[id] = target
				if id == "__uilib.settings.auto_save" then
					assert(type(value) == "boolean", "Invalid legacy autosave setting")
					preferences.AutoSave = value
				elseif id == "__uilib.settings.content_scale" then
					assert(finite(value) and value > 0, "Invalid legacy content scale")
					table.insert(interface.Value, { Key = "Scale", Value = value })
				elseif id == "__uilib.settings.toggle_key" then
					assert(
						type(value) == "string" and #value <= 64 and value:match("^[%w_]+$"),
						"Invalid legacy toggle key"
					)
					table.insert(
						interface.Value,
						{ Key = "ToggleKey", Value = { Tag = "EnumItem", Enum = "Enum.KeyCode", Value = value } }
					)
				else
					local destination = match
							and match.Item.Options
							and match.Item.Options.Preference
							and preferences.Values
						or profile
					assert(destination[target] == nil, "Duplicate migrated config ID")
					destination[target] = { Type = kind, Value = encoded }
				end
			end
			for id, entry in pairs(payload) do
				local parentId = id:match("^__uilib%.bind%.(.+)$")
				local target = parentId and profile[mapped[parentId] or parentId]
				if target and target.Type == "Toggle" and type(entry.value) == "table" then
					target.Value = {
						Tag = "Table",
						Value = {
							{ Key = "Value", Value = target.Value },
							{ Key = "Keybind", Value = pack(entry.value) },
						},
					}
					profile[mapped[id] or id] = nil
				end
			end
			if #interface.Value > 0 then
				preferences.Values.__window = { Type = "interface", Value = interface }
			end
			return {
				Version = 1,
				Preferences = preferences,
				Profiles = { Default = profile },
				ThemeProfiles = {},
				Data = {},
			},
				"Imported " .. count .. " legacy entries."
		end)
		if not ok then
			return false, nil, "Invalid legacy configuration: " .. tostring(document)
		end
		return true, document, note
	end

	return Migration
end
