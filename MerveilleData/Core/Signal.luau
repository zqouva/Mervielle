--!strict

local FreeRunnerThread: thread? = nil

local function acquireRunnerAndCall(fn: (...any) -> (), ...: any)
	local acquired = FreeRunnerThread
	FreeRunnerThread = nil
	fn(...)
	FreeRunnerThread = acquired
end

local function runEventHandlerInFreeThread()
	while true do
		acquireRunnerAndCall(coroutine.yield())
	end
end

local Connection = {}
Connection.__index = Connection

local SignalClass = {}
SignalClass.__index = SignalClass

export type Connection = typeof(setmetatable(
	{} :: {
		signal: Signal,
		listener: (...any) -> (),
		next: Connection?,
		isConnected: boolean,
	},
	Connection
))

export type Signal = typeof(setmetatable(
	{} :: {
		head: Connection?,
		listenerCount: number,
	},
	SignalClass
))

function Connection.Disconnect(self: Connection)
	if self.isConnected == false then
		return
	end

	self.isConnected = false
	self.signal.listenerCount -= 1

	if self.signal.head == self then
		self.signal.head = self.next
		return
	end

	local previous = self.signal.head
	while previous ~= nil and previous.next ~= self do
		previous = previous.next
	end
	if previous ~= nil then
		previous.next = self.next
	end
end

function SignalClass.new(): Signal
	return setmetatable({
		head = nil,
		listenerCount = 0,
	}, SignalClass)
end

function SignalClass.Connect(self: Signal, listener: (...any) -> ()): Connection
	assert(type(listener) == "function", "[Merveille/Signal] listener must be a function")

	local connection = setmetatable({
		signal = self,
		listener = listener,
		next = self.head,
		isConnected = true,
	}, Connection)

	self.head = connection
	self.listenerCount += 1
	return connection
end

function SignalClass.Fire(self: Signal, ...: any)
	local item = self.head
	while item ~= nil do
		if item.isConnected then
			if FreeRunnerThread == nil then
				FreeRunnerThread = coroutine.create(runEventHandlerInFreeThread)
			end
			task.spawn(FreeRunnerThread :: thread, item.listener, ...)
		end
		item = item.next
	end
end

function SignalClass.Wait(self: Signal): ...any
	local thread = coroutine.running()
	local connection: Connection? = nil
	connection = self:Connect(function(...: any)
		(connection :: Connection):Disconnect()
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function SignalClass.GetListenerCount(self: Signal): number
	return self.listenerCount
end

return table.freeze({
	new = SignalClass.new,
})
