--[[
Mineysocket
Copyright (C) 2019 Robert Lieback <robertlieback@zetabyte.de>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
--]]

mineysocket = {}  -- global namespace

-- configuration
mineysocket.host_ip = minetest.settings:get("mineysocket.host_ip")
mineysocket.host_port = minetest.settings:get("mineysocket.host_port")

-- Workaround for bug, where default values return only nil
if not mineysocket.host_ip then
  mineysocket.host_ip = "127.0.0.1"
end
if not mineysocket.host_port then
  mineysocket.host_port = 29999
end

mineysocket.debug = false  -- set to true to show all log levels
mineysocket.max_clients = 10
local eom = "\r\n"  -- End of message marker

-- Load external libs
local ie
if minetest.request_insecure_environment then
  ie = minetest.request_insecure_environment()
end
if not ie then
  error("mineysocket has to be added to the secure.trusted_mods in minetest.conf")
end

local luasocket = ie.require("socket.core")
if not luasocket then
  error("luasocket is not installed or was not found...")
end
mineysocket.json = ie.require("cjson")
if not mineysocket.json then
  error("lua-cjson is not installed or was not found...")
end

-- setup network server
local server, err = luasocket.tcp()
if not server then
  minetest.log("action", err)
  error("exit")
end

local bind, err = server:bind(mineysocket.host_ip, mineysocket.host_port)
if not bind then
  error("mineysocket: " .. err)
end
local listen, err = server:listen(mineysocket.max_clients)
if not listen then
  error("mineysocket: Socket listen error: " .. err)
end
minetest.log("action", "mineysocket: " .. "listening on " .. mineysocket.host_ip .. ":" .. tostring(mineysocket.host_port))

server:settimeout(0)
mineysocket.host_ip, mineysocket.host_port = server:getsockname()
if not mineysocket.host_ip or not mineysocket.host_port then
  error("mineysocket: Couldn't open server port!")
end

local socket_clients = {}  -- a table with all connected clients with there options

-- receive network data and process them
minetest.register_globalstep(function(dtime)
  mineysocket.receive()
end)


-- Clean shutdown
minetest.register_on_shutdown(function()
  minetest.log("action", "mineysocket: Closing port...")
  for clientid, client in pairs(socket_clients) do
    socket_clients[clientid].socket:close()
  end
  server:close()
end)


-- receive data from clients
mineysocket.receive = function()
  local data, ip, port, clientid, client, err

  -- look for new client connections
  client, err = server:accept()
  if client then
    ip, port = client:getpeername()
    clientid = ip .. ":" .. port
    mineysocket.log("action", "New connection from " .. ip .. " " .. port)

    client:settimeout(0)
    -- register the new client
    if not socket_clients[clientid] then
      socket_clients[clientid] = {}
      socket_clients[clientid].socket = client
      socket_clients[clientid].last_message = minetest.get_server_uptime()
	  socket_clients[clientid].buffer = ""
	  
	  if ip == "127.0.0.1" then  -- skip authentication for 127.0.0.1
		socket_clients[clientid].auth = true
		socket_clients[clientid].playername = "localhost"
		socket_clients[clientid].ip = ip
		socket_clients[clientid].port = port
		socket_clients[clientid].callbacks = {}
	  end
    end
  else
    if err ~= "timeout" then
      mineysocket.log("error", "Connection error \"" .. err .. "\"")
	  client:close()
    end
  end

  -- receive data
  for clientid, client in pairs(socket_clients) do
    local complete_data, err, data = socket_clients[clientid].socket:receive("*a")
    -- there are never complete_data, cause we don't receive lines
	-- Note: err is "timeout" every time when there are no client data, cause we set timeout to 0 and
	-- we don't want to wait and block lua/minetest for clients to send data
    if err ~= "timeout" then
	  socket_clients[clientid].socket:close()
      -- cleanup
      if err == "closed" then
        socket_clients[clientid] = nil
        mineysocket.log("action", "Connection to ".. clientid .." was closed")
        return
      else
        mineysocket.log("action", err)
      end
    end
    if data and data ~= "" then
      if not string.find(data, eom) then
        -- fill a buffer and wait for the linebreak
		if socket_clients[clientid].auth == true then  -- prevent dos attack 
			if not socket_clients[clientid].buffer then
			  socket_clients[clientid].buffer = data
			else
			  socket_clients[clientid].buffer = socket_clients[clientid].buffer .. data
			end
			mineysocket.receive()
			return
		end
      else
        -- get data from buffer and reset em
        if socket_clients[clientid]["buffer"] then
          data = socket_clients[clientid].buffer .. data
          socket_clients[clientid].buffer = nil
        end
		
		-- simple alive check
        if data == "ping" .. eom then
          socket_clients[clientid].socket:send("pong" .. eom)
          return
        end

        -- is it a known client, or do we need authentication?
        if socket_clients[clientid] and socket_clients[clientid].auth == true then
          -- known client

          -- store time of the last message for cleanup of old connection
          socket_clients[clientid].last_message = minetest.get_server_uptime()

          -- parse data as json
          local status, input = pcall(mineysocket.json.decode, data)

          if not status then
            minetest.log("error", "mineysocket: " .. mineysocket.json.encode({ error = input }))
            mineysocket.log("error", "JSON-Error: " .. input, ip, port)
            mineysocket.send(clientid, mineysocket.json.encode({ error = "JSON decode error - " .. input }))
            return
          end

          -- commands:
          -- we run lua code
          if input["lua"] then
            run_lua(input, clientid, ip, port)
            return
          end
		  
		  if input[""] then
		    
			return
		  end
		  
		  -- handle reauthentication
		  if input["playername"] and input["password"] then
			mineysocket.authenticate(data, clientid, ip, port, socket_clients[clientid].socket)
			return
		  end

          -- client requested something unimplemented
          mineysocket.send(clientid, mineysocket.json.encode({ error = "Unknown command" }))

        else
          -- we need authentication
          mineysocket.authenticate(data, clientid, ip, port, socket_clients[clientid].socket)
        end
      end
    end
  end
end


-- run lua code send by the client
function run_lua(input, clientid, ip, port)
  local start_time, err
  local output = {}

  start_time = minetest.get_server_uptime()

  if input["id"] then
    output["id"] = input["id"]
  end

  -- log the (shortend) code
  if string.len(input["lua"]) > 120 then
    mineysocket.log("action", "execute: " .. string.sub(input["lua"], 0, 120) .. " ...", ip, port)
  else
    mineysocket.log("action", "execute: " .. input["lua"], ip, port)
  end

  -- run
  local f, syntaxError = loadstring(input["lua"])
  -- todo: is there a way to get also warning like "Undeclared global variable ... accessed at ..."?

  if f then
    local status, result1, result2, result3, result4 = pcall(f, clientid)  -- Get the clientid with "...". Example: "mineysocket.send(..., output)"
    -- is there a more elegant way for unlimited results?

    if status then
      output["result"] = { result1, result2, result3, result4 }

      output = mineysocket.json.encode(output)
      if string.len(output) > 120 then
        mineysocket.log("action", string.sub(output, 0, 120) .. " ..." .. " in " .. (minetest.get_server_uptime() - start_time) .. " seconds", ip, port)
      else
        mineysocket.log("action", output .. " in " .. (minetest.get_server_uptime() - start_time) .. " seconds", ip, port)
      end
      mineysocket.send(clientid, output)
    else
      err = result1
    end
  else
    err = syntaxError
  end

  -- send lua errors
  if err then
    output["error"] = err
    mineysocket.log("error", "Error " .. err .. " in command", ip, port)
    mineysocket.send(clientid, mineysocket.json.encode(output))
  end
end


-- authenticate clients
mineysocket.authenticate = function(data, clientid, ip, port, socket)
  local status, input = pcall(mineysocket.json.decode, data)
  if not status then
    minetest.log("error", "mineysocket: " .. mineysocket.json.encode({ error = input }))
    mineysocket.log("error", "JSON-Error: " .. input, ip, port)
    mineysocket.send(clientid, mineysocket.json.encode({ error = input }))
    return
  end

  if input["playername"] and input["password"] then
    local player = minetest.get_auth_handler().get_auth(input["playername"])

    local player_table = {
      auth = true,
      playername = input["playername"],
      ip = ip, port = port,
      last_message = minetest.get_server_uptime(),
      callbacks = {},
      buffer = "",
      socket = socket
    }

    -- we skip authentication for 127.0.0.1 and just accept everything
    if ip == "127.0.0.1" then
      mineysocket.log("action", "Player '" .. input["playername"] .. "' connected successful", ip, port)
      socket_clients[clientid] = player_table
      mineysocket.send(clientid, mineysocket.json.encode({ result = { "auth_ok", clientid }, id = "auth" }))
    else
      -- others need a valid playername and password
      if player and minetest.check_password_entry(input["playername"], player['password'], input["password"]) and minetest.check_player_privs(input["playername"], { server = true }) then
        mineysocket.log("action", "Player '" .. input["playername"] .. "' authentication successful", ip, port)
        socket_clients[clientid] = player_table
        mineysocket.send(clientid, mineysocket.json.encode({ result = { "auth_ok", clientid }, id = "auth" }))
      else
        mineysocket.log("error", "Wrong playername ('" .. input["playername"] .. "') or password", ip, port)
        socket:send(mineysocket.json.encode({ error = "authentication error" }) .. eom)
      end
    end
  else
    -- that wasn't a auth message
    socket:send(mineysocket.json.encode({ error = "authentication error - malformed message" }) .. eom)
  end
end


-- send data to the client
mineysocket.send = function(clientid, data)
  local data = data .. eom  -- eom is the terminator
  local size = string.len(data)

  local chunk_size = 4096

  if size < chunk_size then
    -- we send in one package
    socket_clients[clientid].socket:send(data)

  else
    -- we split into multiple packages
    for i = 0, math.floor(size / chunk_size) do
      socket_clients[clientid].socket:send(
        string.sub(data, i * chunk_size, chunk_size + (i * chunk_size) - 1)
      )
      luasocket.sleep(0.001)  -- Or buffer fills to fast
      -- todo: Protocol change, that every chunked message needs a response before sending the next
    end
  end
end

-- send data to all connected clients
mineysocket.send_event = function(data)
  for clientid, values in pairs(socket_clients) do
	if socket_clients[clientid].callbacks[data["event"][0]] then
		mineysocket.send(clientid, mineysocket.json.encode(data))
	end
  end
end


-- BEGIN global event registration
minetest.register_on_shutdown(function()
  mineysocket.send_event({ event = { "shutdown" } })
end)
minetest.register_on_player_hpchange(function(player, hp_change, reason)
  mineysocket.send_event({ event = { "player_hpchanged", player:get_player_name(), hp_change, reason } })
end, false)
minetest.register_on_dieplayer(function(player, reason)
  mineysocket.send_event({ event = { "player_died", player:get_player_name(), reason } })
end)
minetest.register_on_respawnplayer(function(player)
  mineysocket.send_event({ event = { "player_respawned", player:get_player_name() } })
end)
minetest.register_on_joinplayer(function(player)
  mineysocket.send_event({ event = { "player_joined", player:get_player_name() } })
end)
minetest.register_on_leaveplayer(function(player, timed_out)
  mineysocket.send_event({ event = { "player_left", player:get_player_name(), timed_out } })
end)
minetest.register_on_auth_fail(function(name, ip)
  mineysocket.send_event({ event = { "auth_failed", name, ip } })
end)
minetest.register_on_cheat(function(player, cheat)
  mineysocket.send_event({ event = { "player_cheated", player:get_player_name(), cheat } })
end)
minetest.register_on_chat_message(function(name, message)
  mineysocket.send_event({ event = { "chat_message", name, message } })
end)
-- END global event registration


-- just a logging function
mineysocket.log = function(level, text, ip, port)
  if mineysocket.debug or level ~= "action" then
    if text then
      if ip and port then
        minetest.log(level, "mineysocket: " .. text .. " from " .. ip .. ":" .. port)
      else
        minetest.log(level, "mineysocket: " .. ": " .. text)
      end
    end
  end
end
