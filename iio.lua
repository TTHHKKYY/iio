local function setposition(file, position)
	file.i = math.min(math.max(position, 0), #file.s) -- clamp the file position from 0 to #content
	
	return file.i
end

local function empty(s)
	return #s > 0 and s or nil
end

----

local file = {}

file.__index = file
file.__name = "FILE*"

local function isfile(object, critical, name)
	local meta = getmetatable(object)
	
	if meta and meta.__index == file then
		return true
	end
	
	if critical then
		error(string.format("bad argument #1 to '%s' (%s expected, got %s)", name, file.__name, type((object))))
	end
	
	return false
end

function file.__close(file)
	file:close()
end

function file.__gc(file)
	file:close()
end

function file.__tostring(file)
	return "file"
end

function file.__newindex(file,key)
	error(string.format("attempt to index a %s value (%s)", file.__name, key))
end

function file:read(...)
	isfile(self, true, "read")
	
	local args = {...}
	
	local formatted = {}
	
	local content do
		if self.readcallback then
			content = tostring((table.remove(args, 1))) or self.s -- use the first argument as an input to the custom read function, or the file's content
			self.i = 0
		else
			content = self.s
		end
	end
	
	if #args == 0 then -- set the first argument to the default (l) if there are no arguments
		args[1] = "l"
	end
	
	for i,arg in pairs(args) do
		local sub = ""
		local length
		
		local all = string.sub(content, self.i + 1, #content)
		
		if type(arg) == "number" then -- bytes
			if arg < 0 then
				print("not enough memory")
				return -- return void 
			end
			
			sub = string.sub(all, 1, arg)
			
			formatted[i] = empty(sub)
		elseif string.find(arg, "^n") or string.find(arg, "^%*n") then -- number
			local number do
				sub = string.match(all, "^[%d%.]+[Ee]*[%+%-]*[%d%.]+") -- numbers (0.0e±1.0)
				number = tonumber(sub)
				
				if not number then
					sub = string.match(all, "^0[Xx][%x%.]+[Ee]*[Pp]?[%+%-]*[%d%.]*") -- hex numbers (0x0.0ep±1.0)
					number = tonumber(sub)
					
					if not number then
						break -- break if there is no number
					end
				end
			end
			
			formatted[i] = number
		elseif string.find(arg, "^a") or string.find(arg, "^%*a") then -- all
			sub = all
			
			formatted[i] = all
		elseif string.find(arg,"^l") or string.find(arg,"^%*l") then -- line without \n
			local newline = string.find(all, "\n") or #all + 1
			
			sub = string.sub(all, 1, newline - 1)
			
			length = newline -- seek past the entire line, or it breaks
			
			formatted[i] = empty(sub)
		elseif string.find(arg, "^L") or string.find(arg, "^%*L") then -- line with \n
			local newline = string.find(all, "\n") or #all
			
			sub = string.sub(all, 1, newline)
			
			formatted[i] = empty(sub)
		else -- invalid option
			error(string.format("bad argument #%i to 'read' (invalid format)", i))
		end
		
		length = length and length or (sub and #sub or 0) -- length value, substring length, or 0 length
		
		setposition(self, self.i + length)
	end
	
	if #formatted > 0 then
		if self.readcallback then
			return self.readcallback(table.unpack(formatted))
		else
			return table.unpack(formatted)
		end
	else
		return nil -- table.unpack() does not return nil for an empty table
	end
end

function file:lines(...)
	isfile(self, true, "lines")
	
	local args = {...}
	
	return function()
		return self:read(table.unpack(args))
	end
end

function file:seek(whence,offset)
	isfile(self, true, "seek")
	
	whence = whence or "cur"
	offset = offset or 0
	
	if type(offset) ~= "number" then
		error(string.format("bad argument #2 to 'seek' (number expected, got %s)", type(offset)))
	end
	
	if whence == "set" then
		setposition(self, 0 + offset)
	elseif whence == "cur" then
		setposition(self, self.i + offset)
	elseif whence == "end" then
		setposition(self, #self.s + offset)
	else
		error(string.format("bad argument #1 to 'seek' (invalid option '%s')", tostring(whence)))
	end
	
	return self.i
end

function file:write(...)
	isfile(self, true, "write")
	
	local args = {...}
	
	for i,arg in pairs(args) do
		if type(arg) ~= "string" and type(arg) ~= "number" then
			error(string.format("bad argument #%i to 'write' (string expected, got %s)", i, type(arg)))
		end
	end
	
	if self.writecallback then
		self.writecallback(...)
		
		return self
	end
	
	local firsthalf = string.sub(self.s, 1, self.i)
	local secondhalf = string.sub(self.s, self.i + 1, #self.s)
	
	local segment = table.concat(args)
	
	self.s = firsthalf .. segment .. secondhalf
	self.i = setposition(self, self.i + #segment)
	
	return self
end

function file:setvbuf(mode,size)
	isfile(self, true, "setvbuf")
	
	return true
end

function file:flush()
	isfile(self, true, "flush")
	
	return true
end

function file:close()
	isfile(self, true, "close")
	
	return true
end

----

local io = {}

local stdout,stdin,stderr -- used here but cannot be defined yet

function io.open(data, readcallback, writecallback)
	return setmetatable(
		{
			s = tostring((data)), -- wrapped in parentheses to convert void to nil
			i = 0,
			readcallback = readcallback,
			writecallback = writecallback
		}, file)
end

function io.tmpfile()
	return io.open("")
end

function io.type(obj)
	return isfile(obj) and "file" or nil
end

function io.lines(data, ...)
	if data then
		return io.open(data):lines(...)
	else
		return input:lines(...)
	end
end

function io.popen()
	error("popen cannot be used with iio")
end

function io.read(...)
	return stdin:read(...)
end

function io.write(...)
	return stdout:write(...)
end

function io.input(data)
	stdin = io.open(data)
end

function io.output(data)
	stdout = io.open(data)
end

function io.flush()
	stdout:flush()
end

function io.close(file)
	if file then
		file:close()
	else
		output:close()
	end
end

----

stdout = io.open("", nil, function(...)
	print(table.concat({...})) -- can't do anything about newlines
end)

stdin = io.open("", function(...)
	return ...
end)

stderr = io.open("", nil, function(...)
	print(table.concat({...}))
end)

io.stdout = stdout
io.stdin = stdin
io.stderr = stderr

return io
