-- Get from: https://github.com/SinisterRectus/Discordia/blob/master/libs/utils/Emitter.lua

local timer = require('timer')

local wrap, yield = coroutine.wrap, coroutine.yield
local resume, running = coroutine.resume, coroutine.running
local insert, remove = table.insert, table.remove
local setTimeout, clearTimeout = timer.setTimeout, timer.clearTimeout

---Implements an asynchronous event emitter where callbacks can be subscribed to
---specific named events. When events are emitted, the callbacks are called in the
---order that they were originally registered.
---@class Emitter
---<!tag:interface>

local Emitter = require('class')('Emitter')

---Initial function for cache
function Emitter:__init()
	self._listeners = {}
end

local function new(self, name, listener)
	local listeners = self._listeners[name]
	if not listeners then
		listeners = {}
		self._listeners[name] = listeners
	end
	insert(listeners, listener)
	return listener.fn
end

---Subscribes a callback to be called every time the named event is emitted.
---Callbacks registered with this method will automatically be wrapped as a new
---coroutine when they are called. Returns the original callback for convenience.
---@param name string
---@param fn function
---@return function
function Emitter:on(name, fn)
	return new(self, name, {fn = fn})
end

---Subscribes a callback to be called only the first time this event is emitted.
---Callbacks registered with this method will automatically be wrapped as a new
---coroutine when they are called. Returns the original callback for convenience.
---@param name string
---@param fn function
---@return function
function Emitter:once(name, fn)
	return new(self, name, {fn = fn, once = true})
end

---Subscribes a callback to be called every time the named event is emitted.
---Callbacks registered with this method are not automatically wrapped as a
---coroutine. Returns the original callback for convenience.
---@param name string
---@param fn function
---@return function
function Emitter:onSync(name, fn)
	return new(self, name, {fn = fn, sync = true})
end

---Subscribes a callback to be called only the first time this event is emitted.
---Callbacks registered with this method are not automatically wrapped as a coroutine.
---Returns the original callback for convenience.
---@param name string
---@param fn function
---@return function
function Emitter:onceSync(name, fn)
	return new(self, name, {fn = fn, once = true, sync = true})
end

---Emits the named event and a variable number of arguments to pass to the event callbacks.
---@param name string
---@param ... unknown
---@return nil
function Emitter:emit(name, ...)
	local listeners = self._listeners[name]
	if not listeners then return end
	for i = 1, #listeners do
		local listener = listeners[i]
		if listener then
			local fn = listener.fn
			if listener.once then
				listeners[i] = false
			end
			if listener.sync then
				fn(...)
			else
				wrap(fn)(...)
			end
		end
	end
	if listeners._removed then
		for i = #listeners, 1, -1 do
			if not listeners[i] then
				remove(listeners, i)
			end
		end
		if #listeners == 0 then
			self._listeners[name] = nil
		end
		listeners._removed = nil
	end
end

---Returns an iterator for all callbacks registered to the named event.
---@param name string
---@return function
function Emitter:getListeners(name)
	local listeners = self._listeners[name]
	if not listeners then return function() end end
	local i = 0
	return function()
		while i < #listeners do
			i = i + 1
			if listeners[i] then
				return listeners[i].fn
			end
		end
	end
end

---Returns the number of callbacks registered to the named event.
---@param name string
---@return number
function Emitter:getListenerCount(name)
	local listeners = self._listeners[name]
	if not listeners then return 0 end
	local n = 0
	for _, listener in ipairs(listeners) do
		if listener then
			n = n + 1
		end
	end
	return n
end

---Unregisters all instances of the callback from the named event.
---@param name string
---@param fn function
---@return nil
function Emitter:removeListener(name, fn)
	local listeners = self._listeners[name]
	if not listeners then return end
	for i, listener in ipairs(listeners) do
		if listener and listener.fn == fn then
			listeners[i] = false
		end
	end
	listeners._removed = true
end

---Unregisters all callbacks for the emitter. If a name is passed, then only
---callbacks for that specific event are unregistered.
---@param name string
---@return nil
function Emitter:removeAllListeners(name)
	if name then
		self._listeners[name] = nil
	else
		for k in pairs(self._listeners) do
			self._listeners[k] = nil
		end
	end
end

---When called inside of a coroutine, this will yield the coroutine until the
---named event is emitted. If a timeout (in milliseconds) is provided, the function
---will return after the time expires, regardless of whether the event is emitted,
---and `false` will be returned; otherwise, `true` is returned. If a predicate is
---provided, events that do not pass the predicate will be ignored.
---@param name string
---@param timeout number
---@param predicate function
---@return boolean, unknown
function Emitter:waitFor(name, timeout, predicate)
	local thread = running()
	local fn
	fn = self:onSync(name, function(...)
		if predicate and not predicate(...) then return end
		if timeout then
			clearTimeout(timeout)
		end
		self:removeListener(name, fn)
		return assert(resume(thread, true, ...))
	end)
	timeout = timeout and setTimeout(timeout, function()
		self:removeListener(name, fn)
		return assert(resume(thread, false))
	end)
	return yield()
end

return Emitter