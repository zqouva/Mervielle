--!strict

-->	["option"]
-->	Rust-style option carrier.
-->	Use this when a path may be absent and you want an explicit surface.

local Option = {}
Option.__index = Option

function Option.some(value: any)
	return setmetatable({
		_tag = "Some",
		_value = value,
	}, Option)
end

function Option.none()
	return setmetatable({
		_tag = "None",
		_value = nil,
	}, Option)
end

function Option.from(value: any)
	if value == nil then
		return Option.none()
	end
	return Option.some(value)
end

function Option:isSome(): boolean
	return self._tag == "Some"
end

function Option:isNone(): boolean
	return self._tag == "None"
end

function Option:unwrap()
	assert(self._tag == "Some", "[Merveille/Option] called unwrap() on None")
	return self._value
end

function Option:unwrapOr(fallback: any)
	if self._tag == "Some" then
		return self._value
	end
	return fallback
end

function Option:map(fn: (any) -> any)
	if self._tag == "Some" then
		return Option.some(fn(self._value))
	end
	return self
end

function Option:match(onSome: (any) -> any, onNone: (() -> any)?)
	if self._tag == "Some" then
		return onSome(self._value)
	end
	if onNone ~= nil then
		return onNone()
	end
	return nil
end

return table.freeze({
	some = Option.some,
	none = Option.none,
	from = Option.from,
})
