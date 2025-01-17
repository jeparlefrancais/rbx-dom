local HttpService = game:GetService("HttpService")

local VERBOSE = false
local ERROR_AT_END = false

local EncodedValue = require(script.Parent.EncodedValue)

local ReflectionClasses = require(script.Parent.ReflectionClasses)

local function verbosePrint(...)
	if VERBOSE then
		print(...)
	end
end

--[[
	Little function for use with pcall to avoid making so many closures.
]]
local function get(parent, key)
	return parent[key]
end

local function getClientVersion()
	local version = string.split(version(), ". ")
	local major = tonumber(version[1])
	local minor = tonumber(version[2])
	local patch = tonumber(version[3])
	local build = tonumber(version[4])

	return {major, minor, patch, build}
end

local propertyBlacklist = {
	-- Mistakes
	RequestQueueSize = true, -- on ContentProvider, mistakenly marked serializable

	-- Stuff that doesn't have meaningful defaults
	ClassName = true,
	Archivable = true,
	Parent = true,
	DataCost = true,
	RobloxLocked = true,
}

local classNameBlacklist = {
	-- Creating a NetworkClient will make HTTP stop working
	NetworkClient = true,
}

local function shouldMeasureProperty(propertyDescriptor)
	if propertyBlacklist[propertyDescriptor.name] then
		return false
	end

	if propertyDescriptor.scriptability ~= "ReadWrite" then
		return false
	end

	return propertyDescriptor.isCanonical
end

--[[
	Grab a copy of an instance of the given type that should have reasonably
	default properties.
]]
local function getDefaultInstance(className)
	if classNameBlacklist[className] then
		return false
	end

	-- Can we construct one of these from Lua?
	local ok, created = pcall(Instance.new, className)
	if ok then
		return created
	end

	-- Guess not, is it a service?
	local ok, service = pcall(game.GetService, game, className)
	if ok then
		return service
	end

	return nil
end

return function(postMessage)
	postMessage(HttpService:JSONEncode({
		type = "Version",
		version = getClientVersion(),
	}))

	for _, class in pairs(ReflectionClasses) do
		local instance = getDefaultInstance(class.name)

		if instance ~= nil then
			local defaultProperties = {}

			local currentClass = class

			while currentClass ~= nil do
				for _, propertyDescriptor in pairs(currentClass.properties) do
					if shouldMeasureProperty(propertyDescriptor) then
						local ok, value = pcall(get, instance, propertyDescriptor.name)

						if ok then
							local ok, encoded = EncodedValue.encode(value, propertyDescriptor.type)

							if ok then
								defaultProperties[propertyDescriptor.name] = encoded
							else
								warn("Couldn't encode property", propertyDescriptor.name, "on class", currentClass.name, encoded)
							end
						else
							verbosePrint("Couldn't read property", propertyDescriptor.name, "on class", class.name)
						end
					end
				end

				currentClass = ReflectionClasses[currentClass.superclass]
			end

			if next(defaultProperties) ~= nil then
				postMessage(HttpService:JSONEncode({
					type = "DefaultProperties",
					className = class.name,
					properties = defaultProperties,
				}))
			end
		end
	end

	if ERROR_AT_END then
		error("Breaking here.")
	end
end