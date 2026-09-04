--!strict

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")

local Signal = require(script.Parent.Signal)
local Codec = require(script.Parent.Codec)
local Wake = require(script.Parent.Wake)
local Vault = require(script.Parent.Vault)
local Arena = require(script.Parent.Arena)
local Result = require(script.Parent.Result)

local Store = {}
Store.__index = Store

local PlaceId = game.PlaceId
local JobId = game.JobId

local ACTIVE_WAKES: {[string]: any} = {}
local STORES: {[string]: any} = {}
local UPDATE_QUEUES: {[string]: {busy: boolean, list: {thread}}} = {}
local MAILBOX_ACKS: {[string]: number} = {}

local MAILBOX_CONNECTED = false
local IS_CLOSING = false
local ACTIVE_LOAD_JOBS = 0
local ACTIVE_SAVE_JOBS = 0
local AUTOSAVE_LOOP_RUNNING = false

local BUFFER_COPY = buffer.copy

local function newPerfCounter()
	return {
		count = 0,
		ok = 0,
		err = 0,
		total = 0,
		max = 0,
		bytes = 0,
	}
end

local function recordPerf(counter: {[string]: number}, seconds: number, ok: boolean, bytes: number?)
	counter.count += 1
	if ok then
		counter.ok += 1
	else
		counter.err += 1
	end
	counter.total += seconds
	if seconds > counter.max then
		counter.max = seconds
	end
	if bytes ~= nil then
		counter.bytes += bytes
	end
end

local function payloadSize(payload: any): number
	if type(payload) == "string" then
		return #payload
	elseif typeof(payload) == "buffer" then
		return buffer.len(payload)
	end
	return 0
end

local function token(storeName: string, key: string): string
	return `{storeName}\0{key}`
end

local function ackKey(storeName: string, key: string, nonce: string): string
	return `{storeName}\0{key}\0{nonce}`
end

local function topicForJob(jobId: string): string
	return `MVR/{jobId}`
end

local function resolveKey(playerOrKey: any): (string, Player?)
	if typeof(playerOrKey) == "Instance" and playerOrKey:IsA("Player") then
		return tostring(playerOrKey.UserId), playerOrKey
	end
	assert(type(playerOrKey) == "string", "[Merveille/Store] open/view/remove expects a Player or string key")
	return playerOrKey, nil
end

local function waitInQueue(queueToken: string)
	local queue = UPDATE_QUEUES[queueToken]
	if queue == nil then
		queue = { busy = false, list = {} }
		UPDATE_QUEUES[queueToken] = queue
	end

	if queue.busy then
		queue.list[#queue.list + 1] = coroutine.running()
		coroutine.yield()
	end

	queue.busy = true
	return function()
		local nextThread = table.remove(queue.list, 1)
		if nextThread ~= nil then
			task.spawn(nextThread)
		else
			UPDATE_QUEUES[queueToken] = nil
		end
	end
end

local function copyBuffer(target: buffer, source: buffer, length: number)
	if length <= 0 then
		return
	end
	if BUFFER_COPY ~= nil then
		BUFFER_COPY(target, 0, source, 0, length)
		return
	end
	for index = 0, length - 1 do
		buffer.writeu8(target, index, buffer.readu8(source, index))
	end
end

local function trimIssues(self: any)
	local now = os.clock()
	while true do
		local first = self._issues[1]
		if first == nil then
			break
		end
		if now - first > self.Options.criticalExpire then
			table.remove(self._issues, 1)
		else
			break
		end
	end

	if self.IsCritical and #self._issues < self.Options.criticalThreshold then
		self.IsCritical = false
		self.OnCritical:Fire(false)
	end
end

local function registerError(self: any, key: string?, message: string)
	warn(`[Merveille] ({self.Name}{if key then ` / {key}` else ""}) {message}`)
	self._issues[#self._issues + 1] = os.clock()
	trimIssues(self)
	if self.IsCritical == false and #self._issues >= self.Options.criticalThreshold then
		self.IsCritical = true
		self.OnCritical:Fire(true)
	end
	self.OnError:Fire(message, self.Name, key)
end

local function encodeRecord(self: any, source: buffer): string
	if self._vaultKey == nil then
		return Codec.encode(source, self.Schema.PageBytes)
	end
	local lane = self._vaultArena:take()
	copyBuffer(lane, source, self.Schema.PageBytes)
	Vault.sealRecord(lane, self._vaultKey, `{HttpService:GenerateGUID(false)}:{os.clock()}:{self.Name}`)
	local encoded = Codec.encode(lane, self.Schema.PageBytes)
	self._vaultArena:give(lane)
	return encoded
end

local function decodeRecord(self: any, payload: any): (buffer?, string?)
	if self._perf.enabled then
		self._perf.decodedBytes += payloadSize(payload)
	end
	local body = Codec.decode(payload, self.Schema.PageBytes)
	local header = Wake.readHeader(body)
	if header.sealed then
		if self._vaultKey == nil then
			return nil, "payload is sealed but this atelier has no vaultKey"
		end
		local ok, reason = Vault.openRecord(body, self._vaultKey)
		if not ok then
			return nil, reason or "vault open failed"
		end
	end
	return body, nil
end

local function autosaveStep(nowClock: number)
	local nextWakeIn = 1
	local sawWork = false

	for _, store in STORES do
		trimIssues(store)
		local list = store._autosave
		local length = #list
		if length == 0 then
			continue
		end

		sawWork = true
		local spacing = math.max(0.05, store.Options.autosave / length)
		while nowClock - store._lastAutoSave >= spacing do
			store._lastAutoSave += spacing
			local wake = list[store._autoIndex]
			store._autoIndex += 1
			if store._autoIndex > length then
				store._autoIndex = 1
			end
			if wake ~= nil and wake:isActive() and wake._dirty == true and wake._saving == false then
				task.spawn(function()
					wake:save()
				end)
			end
		end

		local dueIn = spacing - (nowClock - store._lastAutoSave)
		if dueIn < nextWakeIn then
			nextWakeIn = dueIn
		end
	end

	return if sawWork then math.max(0.05, math.min(nextWakeIn, 1)) else 1
end

local function ensureAutosaveLoop()
	if AUTOSAVE_LOOP_RUNNING then
		return
	end
	AUTOSAVE_LOOP_RUNNING = true
	task.spawn(function()
		while true do
			task.wait(autosaveStep(os.clock()))
		end
	end)
end

local function ensureMailbox()
	if MAILBOX_CONNECTED then
		return
	end
	MAILBOX_CONNECTED = true

	local function onMessage(message: any)
		local payload = message.Data
		if type(payload) ~= "table" then
			return
		end

		local kind = payload[1]
		local storeName = payload[2]
		local key = payload[3]
		if type(storeName) ~= "string" or type(key) ~= "string" then
			return
		end

		if kind == 1 then
			local requesterJobId = payload[4]
			local nonce = payload[5]
			local wake = ACTIVE_WAKES[token(storeName, key)]
			if wake ~= nil and wake:isActive() then
				task.spawn(function()
					wake:release("External")
					if type(requesterJobId) == "string" and requesterJobId ~= "" and type(nonce) == "string" then
						pcall(MessagingService.PublishAsync, MessagingService, topicForJob(requesterJobId), {2, storeName, key, nonce})
					end
				end)
			end
		elseif kind == 2 then
			local nonce = payload[4]
			if type(nonce) == "string" then
				MAILBOX_ACKS[ackKey(storeName, key, nonce)] = os.clock()
			end
		elseif kind == 3 then
			local wake = ACTIVE_WAKES[token(storeName, key)]
			if wake ~= nil and wake:isActive() then
				task.spawn(function()
					wake:save()
				end)
			end
		end
	end

	pcall(function()
		MessagingService:SubscribeAsync(topicForJob(JobId), onMessage)
	end)

	game:BindToClose(function()
		IS_CLOSING = true
		local jobs = 0
		for _, wake in ACTIVE_WAKES do
			if wake:isActive() then
				jobs += 1
				task.spawn(function()
					wake:release("Shutdown")
					jobs -= 1
				end)
			end
		end
		while jobs > 0 or ACTIVE_LOAD_JOBS > 0 or ACTIVE_SAVE_JOBS > 0 do
			task.wait()
		end
	end)
end

local function buildFreshBody(self: any, now: number): buffer
	local fresh = Wake.newBuffer(self.Schema)
	Wake.applyDefaults(self.Schema, fresh)
	Wake.seal(fresh, self.Schema, {
		active = true,
		sealed = self._vaultKey ~= nil,
		sealVersion = if self._vaultKey ~= nil then 2 else 0,
		revision = 0,
		commit = 0,
		lockEpoch = 1,
		openUnix = now,
		lastSaveUnix = now,
		ownerPlaceId = PlaceId,
		ownerJobId = JobId,
		mirrorRevision = 0,
	})
	return fresh
end

function Store.new(name: string, schema: any, options: {[string]: any}?)
	assert(type(name) == "string" and name ~= "", "[Merveille/Store] store name must be a non-empty string")
	assert(type(schema) == "table" and schema.Hash ~= nil, "[Merveille/Store] store schema must be a compiled Merveille profile")

	ensureMailbox()
	ensureAutosaveLoop()

	local self = setmetatable({}, Store)
	self.Name = name
	self.Schema = schema
	self.Options = {
		autosave = if options and options.autosave ~= nil then options.autosave else 180,
		assumeDead = if options and options.assumeDead ~= nil then options.assumeDead else 630,
		sessionSteal = if options and options.sessionSteal ~= nil then options.sessionSteal else 35,
		openTimeout = if options and options.openTimeout ~= nil then options.openTimeout else 120,
		firstRetry = if options and options.firstRetry ~= nil then options.firstRetry else 1.5,
		followRetry = if options and options.followRetry ~= nil then options.followRetry else 4,
		mock = if options and options.mock == true then true else false,
		vault = if options and options.vaultKey ~= nil then true else false,
		profile = if options and options.profile == true then true else false,
		criticalThreshold = if options and options.criticalThreshold ~= nil then options.criticalThreshold else 5,
		criticalExpire = if options and options.criticalExpire ~= nil then options.criticalExpire else 120,
	}
	self.State = "Access"
	self.IsClosing = false
	self.IsCritical = false
	self.OnError = Signal.new()
	self.OnCritical = Signal.new()
	self._issues = {}
	self._active = {}
	self._autosave = {}
	self._autoIndex = 1
	self._lastAutoSave = os.clock()
	self._mockData = {}
	self._vaultKey = if options and options.vaultKey ~= nil then Vault.key(options.vaultKey) else nil
	self._vaultArena = if self._vaultKey ~= nil then Arena.new(schema.PageBytes, if options and options.vaultSlots ~= nil then options.vaultSlots else 2) else nil
	self._dataStore = if self.Options.mock then nil else DataStoreService:GetDataStore(name)
	self._perf = {
		enabled = self.Options.profile,
		store = name,
		schema = schema.Id,
		peakActive = 0,
		encodedBytes = 0,
		decodedBytes = 0,
		opens = newPerfCounter(),
		saves = newPerfCounter(),
		mirrors = newPerfCounter(),
		whispers = newPerfCounter(),
		updateAsync = newPerfCounter(),
		getAsync = newPerfCounter(),
		removeAsync = newPerfCounter(),
	}

	STORES[name] = self
	return self
end

function Store:_updateAsync(key: string, transform: (any) -> any)
	local releaseQueue = waitInQueue(token(self.Name, key))
	local started = if self._perf.enabled then os.clock() else 0
	local success, result = pcall(function()
		if self.Options.mock then
			self._mockData[key] = transform(self._mockData[key])
			return self._mockData[key]
		else
			return self._dataStore:UpdateAsync(key, function(current: any)
				return transform(current)
			end)
		end
	end)
	releaseQueue()
	if self._perf.enabled then
		recordPerf(self._perf.updateAsync, os.clock() - started, success)
	end
	if not success then
		registerError(self, key, tostring(result))
		return false, nil
	end
	return true, result
end

function Store:_getAsync(key: string)
	local started = if self._perf.enabled then os.clock() else 0
	local success, result = pcall(function()
		if self.Options.mock then
			return self._mockData[key]
		else
			return self._dataStore:GetAsync(key)
		end
	end)
	if self._perf.enabled then
		recordPerf(self._perf.getAsync, os.clock() - started, success)
	end
	if not success then
		registerError(self, key, tostring(result))
		return nil
	end
	return result
end

function Store:_removeAsync(key: string): boolean
	local releaseQueue = waitInQueue(token(self.Name, key))
	local started = if self._perf.enabled then os.clock() else 0
	local success, result = pcall(function()
		if self.Options.mock then
			self._mockData[key] = nil
			return true
		else
			self._dataStore:RemoveAsync(key)
			return true
		end
	end)
	releaseQueue()
	if self._perf.enabled then
		recordPerf(self._perf.removeAsync, os.clock() - started, success)
	end
	if not success then
		registerError(self, key, tostring(result))
		return false
	end
	return result
end

function Store:_registerWake(wake: any)
	local id = token(self.Name, wake:key())
	ACTIVE_WAKES[id] = wake
	self._active[id] = wake
	self._autosave[#self._autosave + 1] = wake
	if #self._autosave == 1 then
		self._lastAutoSave = os.clock()
		self._autoIndex = 1
	end
end

function Store:_deregisterWake(wake: any)
	local id = token(self.Name, wake:key())
	ACTIVE_WAKES[id] = nil
	self._active[id] = nil
	local index = table.find(self._autosave, wake)
	if index ~= nil then
		table.remove(self._autosave, index)
		if index < self._autoIndex then
			self._autoIndex -= 1
		end
		if self._autoIndex < 1 then
			self._autoIndex = 1
		end
		if self._autoIndex > #self._autosave then
			self._autoIndex = 1
		end
	end
end

function Store:_publish(kind: number, key: string, foreignJobId: string, nonce: string?)
	if self.Options.mock then
		return
	end
	local payload = if kind == 1 then {1, self.Name, key, foreignJobId, nonce}
		elseif kind == 2 then {2, self.Name, key, nonce}
		else {3, self.Name, key}
	pcall(MessagingService.PublishAsync, MessagingService, topicForJob(foreignJobId), payload)
end

function Store:open(playerOrKey: any, _options: {[string]: any}?)
	local key, player = resolveKey(playerOrKey)
	assert(ACTIVE_WAKES[token(self.Name, key)] == nil, `[Merveille/Store] '{self.Name}/{key}' is already active on this server`)
	if IS_CLOSING or self.IsClosing then
		return nil
	end

	ACTIVE_LOAD_JOBS += 1
	local started = os.clock()
	local function finishOpen(ok: boolean)
		if self._perf.enabled then
			recordPerf(self._perf.opens, os.clock() - started, ok)
		end
	end
	local foreignJobId: string? = nil
	local allowSteal = false
	local firstRetry = true

	while not IS_CLOSING and not self.IsClosing do
		local now = os.time()
		foreignJobId = nil
		local claimedBody: buffer? = nil
		local integrityIssue: string? = nil

		local success = self:_updateAsync(key, function(current: any)
			if current == nil or (type(current) == "string" and current == "") then
				local fresh = buildFreshBody(self, now)
				claimedBody = fresh
				return encodeRecord(self, fresh)
			end

			local body, decodeIssue = decodeRecord(self, current)
			if body == nil then
				integrityIssue = decodeIssue or "decode failure"
				return current
			end

			local ok, reason = Wake.verifyIntegrity(body, self.Schema)
			if not ok then
				integrityIssue = reason or "integrity failure"
				return current
			end

			local header = Wake.readHeader(body)
			if header.active == false or header.ownerJobId == JobId or allowSteal or (header.lastSaveUnix > 0 and (now - header.lastSaveUnix) >= self.Options.assumeDead) then
				Wake.seal(body, self.Schema, {
					active = true,
					sealed = self._vaultKey ~= nil,
					sealVersion = if self._vaultKey ~= nil then 2 else 0,
					revision = header.revision,
					commit = header.commit,
					lockEpoch = header.lockEpoch + if header.ownerJobId == JobId then 0 else 1,
					openUnix = if header.openUnix > 0 then header.openUnix else now,
					lastSaveUnix = header.lastSaveUnix,
					ownerPlaceId = PlaceId,
					ownerJobId = JobId,
					mirrorRevision = header.mirrorRevision,
				})
				claimedBody = body
				return encodeRecord(self, body)
			end

			foreignJobId = header.ownerJobId
			return current
		end)

		if success and claimedBody ~= nil then
			local wake = Wake.fromBuffer(self, key, player, claimedBody, true, false)
			self:_registerWake(wake)
			ACTIVE_LOAD_JOBS -= 1
			return wake
		end

		if integrityIssue ~= nil then
			registerError(self, key, `open rejected existing payload: {integrityIssue}`)
			ACTIVE_LOAD_JOBS -= 1
			return nil
		end

		if os.clock() - started >= self.Options.openTimeout then
			ACTIVE_LOAD_JOBS -= 1
			return nil
		end

		if foreignJobId ~= nil and foreignJobId ~= "" and foreignJobId ~= JobId then
			local nonce = HttpService:GenerateGUID(false)
			MAILBOX_ACKS[ackKey(self.Name, key, nonce)] = nil
			self:_publish(1, key, foreignJobId, nonce)
			local waited = 0
			local maxWait = if firstRetry then self.Options.firstRetry else self.Options.followRetry
			while waited < maxWait and not IS_CLOSING and not self.IsClosing do
				if MAILBOX_ACKS[ackKey(self.Name, key, nonce)] ~= nil then
					MAILBOX_ACKS[ackKey(self.Name, key, nonce)] = nil
					break
				end
				task.wait(0.1)
				waited += 0.1
			end
		else
			task.wait(if firstRetry then self.Options.firstRetry else self.Options.followRetry)
		end

		firstRetr		end

		firstRetry = false
		if os.clock() - started >= self.Options.sessionSteal then
			allowSteal = true
		end
	end

	ACTIVE_LOAD_JOBS -= 1
	finishOpen(false)
	return nil
end

function Store:_saveWake(wake: any, releasing: boolean, _reason: string?): boolean
	if wake._view == true then
		error("[Merveille/Store] view wakes cannot be saved; use a live wake")
	end
	if wake._active ~= true then
		return false
	end
	while wake._saving do
		task.wait()
	end

	wake._saving = true
	wake._releasing = releasing
	ACTIVE_SAVE_JOBS += 1
	local started = os.clock()
	local function finishSave(ok: boolean)
		if self._perf.enabled then
			recordPerf(self._perf.saves, os.clock() - started, ok, self.Schema.PageBytes)
		end
		if wake._perf ~= nil then
			recordPerf(wake._perf.saves, os.clock() - started, ok, self.Schema.PageBytes)
		end
	end

	local snapshotRevision = wake._revision
	local nextCommit = wake._commit + 1
	local now = os.time()
	local saveScratch = wake._saveScratch :: buffer
	copyBuffer(saveScratch, wake._buffer, self.Schema.PageBytes)
	Wake.seal(saveScratch, self.Schema, {
		active = not releasing,
		sealed = self._vaultKey ~= nil,
		sealVersion = if self._vaultKey ~= nil then 2 else 0,
		revision = snapshotRevision,
		commit = nextCommit,
		lockEpoch = wake._lockEpoch,
		openUnix = wake._openUnix,
		lastSaveUnix = now,
		ownerPlaceId = if releasing then 0 else PlaceId,
		ownerJobId = if releasing then "" else JobId,
		mirrorRevision = snapshotRevision,
	})
	local encodedSnapshot = encodeRecord(self, saveScratch)

	local lostOwnership = false
	local success = self:_updateAsync(wake:key(), function(current: any)
		if current == nil or (type(current) == "string" and current == "") then
			lostOwnership = true
			return current
		end
		local body, decodeIssue = decodeRecord(self, current)
		if body == nil then
			registerError(self, wake:key(), `save rejected current payload: {decodeIssue or "decode failure"}`)
			lostOwnership = true
			return current
		end
		local ok, integrityIssue = Wake.verifyIntegrity(body, self.Schema)
		if ok == false then
			registerError(self, wake:key(), `save rejected current payload: {integrityIssue or "integrity failure"}`)
			lostOwnership = true
			return current
		end
		local header = Wake.readHeader(body)
		if header.ownerJobId ~= JobId or header.lockEpoch ~= wake._lockEpoch or header.active == false then
			lostOwnership = true
			return current
		end
		return encodedSnapshot
	end)

	ACTIVE_SAVE_JOBS -= 1
	wake._saving = false

	if not success then
		return false
	end
	if lostOwnership then
		wake:_deactivate()
		self:_deregisterWake(wake)
		finishSave(false)
		return false
	end

	wake._commit = nextCommit
	wake._lastSaveUnix = now
	if releasing then
		wake:_deactivate()
		self:_deregisterWake(wake)
	elseif wake._revision == snapshotRevision then
		wake:_clearDirty()
	end

	return true
end

function Store:mirror(playerOrKey: any)
	local started = os.clock()
	local function finishMirror(ok: boolean)
		if self._perf.enabled then
			recordPerf(self._perf.mirrors, os.clock() - started, ok, self.Schema.MirrorSize)
		end
	end
	local key = resolveKey(playerOrKey)
	local encoded = self:_getAsync(key)
	if encoded == nil or (type(encoded) == "string" and encoded == "") then
		finishMirror(false)
		return nil
	end
	local body, decodeIssue = decodeRecord(self, encoded)
	if body == nil then
		registerError(self, key, `view decode failed: {decodeIssue or "unknown"}`)
		finishMirror(false)
		return nil
	end
	local ok, reason = Wake.verifyIntegrity(body, self.Schema)
	if not ok then
		registerError(self, key, `integrity check failed during view load: {reason or "unknown"}`)
		finishMirror(false)
		return nil
	end
	local wake = Wake.fromBuffer(self, key, nil, body, false, true)
	finishMirror(true)
	return wake
end

function Store:sever(playerOrKey: any, force: boolean?)
	local key = resolveKey(playerOrKey)
	if not force and ACTIVE_WAKES[token(self.Name, key)] ~= nil then
		return false
	end
	return self:_removeAsync(key)
end

function Store:whisper(playerOrKey: any, _payload: any): boolean
	local started = os.clock()
	local function finishWhisper(ok: boolean)
		if self._perf.enabled then
			recordPerf(self._perf.whispers, os.clock() - started, ok)
		end
	end
	local key = resolveKey(playerOrKey)
	local wake = ACTIVE_WAKES[token(self.Name, key)]
	if wake ~= nil and wake:isActive() then
		local ok = wake:save()
		finishWhisper(ok)
		return ok
	end

	local encoded = self:_getAsync(key)
	if encoded == nil or (type(encoded) == "string" and encoded == "") then
		finishWhisper(false)
		return false
	end
	local body, decodeIssue = decodeRecord(self, encoded)
	if body == nil then
		registerError(self, key, `whisper decode failed: {decodeIssue or "unknown"}`)
		finishWhisper(false)
		return false
	end
	local header = Wake.readHeader(body)
	if header.ownerJobId ~= "" and header.ownerJobId ~= JobId then
		self:_publish(3, key, header.ownerJobId, nil)
		finishWhisper(true)
		return true
	end
	finishWhisper(false)
	return false
end

function Store:tryVeille(playerOrKey: any, options: {[string]: any}?)
	local ok, wake = pcall(self.veille, self, playerOrKey, options)
	if not ok then
		return Result.err(wake)
	end
	return if wake ~= nil then Result.ok(wake) else Result.err("OpenFailed")
end

function Store:matchVeille(playerOrKey: any, onOk: (any) -> any, onErr: (any) -> any, options: {[string]: any}?)
	return self:tryVeille(playerOrKey, options):match(onOk, onErr)
end

function Store:tryMirror(playerOrKey: any)
	local ok, wake = pcall(self.mirror, self, playerOrKey)
	if not ok then
		return Result.err(wake)
	end
	return if wake ~= nil then Result.ok(wake) else Result.err("MirrorFailed")
end

function Store:matchMirror(playerOrKey: any, onOk: (any) -> any, onErr: (any) -> any)
	return self:tryMirror(playerOrKey):match(onOk, onErr)
end

function Store:trySever(playerOrKey: any, force: boolean?)
	local ok, removed = pcall(self.sever, self, playerOrKey, force)
	if not ok then
		return Result.err(removed)
	end
	return if removed then Result.ok(true) else Result.err("SeverFailed")
end

function Store:matchSever(playerOrKey: any, onOk: (any) -> any, onErr: (any) -> any, force: boolean?)
	return self:trySever(playerOrKey, force):match(onOk, onErr)
end

function Store:veille(playerOrKey: any, options: {[string]: any}?)
	return self:open(playerOrKey, options)
end

function Store:wake(playerOrKey: any, options: {[string]: any}?)
	return self:veille(playerOrKey, options)
end

function Store:erase(playerOrKey: any, force: boolean?)
	return self:sever(playerOrKey, force)
end

function Store:remove(playerOrKey: any, force: boolean?)
	return self:sever(playerOrKey, force)
end

function Store:view(playerOrKey: any)
	return self:mirror(playerOrKey)
end

function Store:miroir(playerOrKey: any)
	return self:mirror(playerOrKey)
end

function Store:message(playerOrKey: any, payload: any): boolean
	return self:whisper(playerOrKey, payload)
end

return Store
e
