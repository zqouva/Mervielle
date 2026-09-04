--!strict

-->	["result"]
-->	Rust-style result carrier.
-->	Use this when an operation can fail and you want the value and failure state
-->	to stay explicit without comparing magic nil shapes.

local Result = {}
Result.__index = Result

function Result.ok(value: any)
	return setmetatable({
		_tag = "Ok",
		_value = value,
		_error = nil,
	}, Result)
end

function Result.err(reason: any)
	return setmetatable({
		_tag = "Err",
		_value = nil,
		_error = reason,
	}, Result)
end

function Result:isOk(): boolean
	return self._tag == "Ok"
end

function Result:isErr(): boolean
	return self._tag == "Err"
end

function Result:unwrap()
	assert(self._tag == "Ok", `[Merveille/Result] called unwrap() on Err: {tostring(self._error)}`)
	return self._value
end

function Result:unwrapErr()
	assert(self._tag == "Err", "[Merveille/Result] called unwrapErr() on Ok")
	return self._error
end

function Result:unwrapOr(fallback: any)
	if self._tag == "Ok" then
		return self._value
	end
	return fallback
end

function Result:map(fn: (any) -> any)
	if self._tag == "Ok" then
		return Result.ok(fn(self._value))
	end
	return self
end

function Result:mapErr(fn: (any) -> any)
	if self._tag == "Err" then
		return Result.err(fn(self._error))
	end
	return self
end

function Result:match(onOk: (any) -> any, onErr: (any) -> any)
	if self._tag == "Ok" then
		return onOk(self._value)
	end
	return onErr(self._error)
end

return table.freeze({
	ok = Result.ok,
	err = Result.err,
})
