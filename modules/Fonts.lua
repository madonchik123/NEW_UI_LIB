return function(require)
	local Fonts = {}

	Fonts.Options = table.freeze({ "Roboto", "Montserrat", "Builder Sans", "Gotham", "Code" })

	local families = {
		Roboto = "rbxasset://fonts/families/Roboto.json",
		Montserrat = "rbxasset://fonts/families/Montserrat.json",
	}

	local legacy = {
		["Builder Sans"] = { Enum.Font.BuilderSans, Enum.Font.BuilderSansBold },
		Gotham = { Enum.Font.Gotham, Enum.Font.GothamBold },
		Code = { Enum.Font.Code, Enum.Font.Code },
	}

	function Fonts.name(value)
		if typeof(value) == "Font" then
			for name, family in pairs(families) do
				if value.Family == family then
					return name
				end
			end
		elseif typeof(value) == "EnumItem" then
			if value == Enum.Font.Roboto then
				return "Roboto"
			end
			for name, variants in pairs(legacy) do
				if value == variants[1] or value == variants[2] then
					return name
				end
			end
		elseif type(value) == "string" and (families[value] or legacy[value]) then
			return value
		end
		return nil
	end

	function Fonts.resolve(value, bold)
		if type(value) == "string" then
			local family = families[value]
			if family then
				return Font.new(family, bold and Enum.FontWeight.Bold or Enum.FontWeight.Regular, Enum.FontStyle.Normal)
			end
			local variants = legacy[value]
			if not variants then
				return nil
			end
			return variants[bold and 2 or 1]
		end
		if typeof(value) ~= "Font" and not (typeof(value) == "EnumItem" and value.EnumType == Enum.Font) then
			return nil
		end
		if bold then
			return Fonts.bold(value)
		end
		return value
	end

	function Fonts.bold(value)
		value = Fonts.resolve(value)
		if not value then
			return nil
		end
		if typeof(value) == "Font" then
			return Font.new(value.Family, Enum.FontWeight.Bold, value.Style)
		end
		local name = Fonts.name(value)
		if name then
			return Fonts.resolve(name, true)
		end
		local face = if typeof(value) == "Font" then value else Font.fromEnum(value)
		return Font.new(face.Family, Enum.FontWeight.Bold, face.Style)
	end

	return Fonts
end
