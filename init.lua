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

mineysocket = {}  -- namespace

-- configuration
mineysocket.host_ip = minetest.settings:get("miney_ip")
mineysocket.host_port = minetest.settings:get("miney_port")
-- Workaround for bug, where default values return only nil
if not mineysocket.host_ip then mineysocket.host_ip = "127.0.0.1" end
if not mineysocket.host_port then mineysocket.host_port = 29999 end

mineysocket.debug = false  -- set to true to show all log levels

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
local server, err = luasocket.udp()
if not server then 
  error("mineysocket: Socket error: " .. err)
else
  minetest.log("action", "mineysocket: " .. "listening on " .. mineysocket.host_ip .. ":" .. tostring(mineysocket.host_port))
end
server:setsockname(mineysocket.host_ip, mineysocket.host_port)
server:settimeout(0)
mineysocket.host_ip, mineysocket.host_port = server:getsockname()
if not mineysocket.host_ip or not mineysocket.host_port then error("mineysocket: Couldn't open server port!") end

local socket_clients = {}  -- a table with all connected clients with there options


-- receive network data and process them
minetest.register_globalstep(function(dtime)
  local data, ip, port, clientid
  data, ip, port = server:receivefrom()
  if data and string.find(data, "\n") then
    clientid = ip .. ":" .. port

    -- is it a known client, or do we need authentication?
    if socket_clients[clientid] and socket_clients[clientid].auth == true then  -- known client
      -- store time of the last message for cleanup of old connection
      socket_clients[clientid].last_message = minetest.get_server_uptime()

      -- parse data as json
      local status, input = pcall(mineysocket.json.decode, data)

      if not status then
        minetest.log("error", "mineysocket: " .. mineysocket.json.encode({error = input}))
        mineysocket.log("error", "JSON-Error: " .. input, ip, port)
        mineysocket.send(clientid, mineysocket.json.encode({error = input}))
        return
      end
      
      -- commands:
      -- we run lua code
      if input["lua"] then
        run_lua(input, clientid, ip, port)
        return
      end
      
      -- client requested something unimplemented
      mineysocket.send(clientid, mineysocket.json.encode({error = "Unknown command"}))
      
    else -- we need authentication
      mineysocket.authenticate(data, clientid, ip, port)
    end
  end

  -- cleanup old inactive connections after 10 minutes
  for clientid, values in pairs(socket_clients) do
    if minetest.get_server_uptime() - socket_clients[clientid].last_message > 600 then
      mineysocket.log("action","Removed old connection", socket_clients[clientid].ip, socket_clients[clientid].port)
      socket_clients[clientid] = nil
    end
  end
end)


-- Clean shutdown
minetest.register_on_shutdown(function()
  minetest.log("action", "mineysocket: " .. "Closing port...")
  server:close()
end)


-- run lua code send by the client
function run_lua(input, clientid, ip, port)
  local err
  local output = {}
  
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
  -- is there a way to get also warning like "Undeclared global variable ... accessed at ..."?
  
  if f then
    local status, result1, result2, result3, result4 = pcall(f, clientid)  -- Get the clientid with "...". Example: "mineysocket.send(..., output)"
    -- is there a more elegant way for unlimited results?

    if status then
      output["result"] = {result1, result2, result3, result4}
      
      output = mineysocket.json.encode(output)
      if string.len(output) > 120 then
        mineysocket.log("action", string.sub(output,0, 120) .. " ...", ip, port)
      else
        mineysocket.log("action", output, ip, port)
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
    mineysocket.log("error", "Error "..err.." in command", ip, port)
    mineysocket.send(clientid, mineysocket.json.encode(output))
  end
end


-- authenticate clients
mineysocket.authenticate = function (data, clientid, ip, port)
  local input, err = mineysocket.json.decode(data)
  if err then mineysocket.log("error", "mineysocket.json.decode error: " .. err, ip, port) end

  if not err and input["playername"] and input["password"] then
    local player = minetest.get_auth_handler().get_auth(input["playername"])
    -- we skip authentication for 127.0.0.1 and just accept everything
    if ip == "127.0.0.1" then
      mineysocket.log("action", "Player '" .. input["playername"] .. "' connected successful", ip, port)
      socket_clients[clientid] = {["auth"] = true, playername=input["playername"], ip = ip, port = port, last_message = minetest.get_server_uptime(), callbacks={}}
      mineysocket.send(clientid, mineysocket.json.encode({result = {"auth_ok", clientid}, id = "auth"}))
    else
      -- others need a valid playername and password
      if player and minetest.check_password_entry(input["playername"], player['password'], input["password"]) and minetest.check_player_privs(input["playername"], { server=true }) then
        mineysocket.log("action", "Player '" .. input["playername"] .. "' authentication successful", ip, port)
        socket_clients[clientid] = {["auth"] = true, playername=input["playername"], ip = ip, port = port, last_message = minetest.get_server_uptime(), callbacks={}}
        mineysocket.send(clientid, mineysocket.json.encode({result = {"auth_ok", clientid}, id = "auth"}))
      else
        mineysocket.log("error", "Wrong playername ('".. input["playername"] .."') or password", ip, port)
        server:sendto(mineysocket.json.encode({error = "authentication error"}) .. "\n", ip, port)
      end
    end
  else
    -- that wasn't a auth message
    server:sendto(mineysocket.json.encode({error = "authentication error"}) .. "\n", ip, port)
  end
end


-- send data to the client
mineysocket.send = function (clientid, data)
  local data = data .. "\n"  -- \n is the terminator
  local size = string.len(data)
  
  local chunksize = 4096
  
  if size < chunksize then  -- we send in one package
    server:sendto(data, socket_clients[clientid].ip, socket_clients[clientid].port)
    
  else  -- we split into multiple packages
    for i = 0, math.floor(size / chunksize) do
      server:sendto(
        string.sub(data, i * chunksize, chunksize + (i * chunksize) - 1), 
        socket_clients[clientid].ip, 
        socket_clients[clientid].port
      )
    end
  end
end

-- send data to all connected clients
mineysocket.send_to_all = function(data)
  for clientid, values in pairs(socket_clients) do
    mineysocket.send(clientid, mineysocket.json.encode(data))
  end
end

-- just a logging function
mineysocket.log = function (level, text, ip, port)
  if mineysocket.debug or level ~= "action" then
    if ip and port then
      minetest.log(level, "mineysocket: " .. text .. " from " .. ip .. ":" .. port)
    else
      minetest.log(level, "mineysocket: " .. ": " .. text)
    end
  end
end


-- store the callback functions in the socket_clients table, to keep them nil-able
mineysocket.register_callback = function(clientid, cb_id, description, func)
  socket_clients[clientid]["callbacks"]["cb_id"] = {func = func, description = description}
  return func
end


-- BEGIN global event registration
minetest.register_on_shutdown(function() mineysocket.send_to_all({event = {"shutdown"}}) end)
minetest.register_on_player_hpchange(function(player, hp_change, reason) mineysocket.send_to_all({event = {"player_hpchanged", player:get_player_name(), hp_change, reason}}) end, false)
minetest.register_on_dieplayer(function(player, reason) mineysocket.send_to_all({event = {"player_died", player:get_player_name(), reason}}) end)
minetest.register_on_respawnplayer(function(player) mineysocket.send_to_all({event = {"player_respawned", player:get_player_name()}}) end)
minetest.register_on_joinplayer(function(player) mineysocket.send_to_all({event = {"player_joined", player:get_player_name()}}) end)
minetest.register_on_leaveplayer(function(player, timed_out) mineysocket.send_to_all({event = {"player_left", player:get_player_name(), timed_out}}) end)
minetest.register_on_auth_fail(function(name, ip) mineysocket.send_to_all({event = {"auth_failed", name, ip}}) end)
minetest.register_on_cheat(function(player, cheat) mineysocket.send_to_all({event = {"player_cheated", player:get_player_name(), cheat}}) end)
minetest.register_on_chat_message(function(name, message) mineysocket.send_to_all({event = {"chat_message", name, message}}) end)
-- END global event registration