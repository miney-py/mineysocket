-- configuration
local host_ip = "127.0.0.1"  -- the ip of the interface, "*" starts on all available IPs/Interfaces
local host_port = 29999
_debug = false  -- show detailed all actions
--

modname = minetest.get_current_modname()

-- Load external depencies 
local ie
if minetest.request_insecure_environment then
  ie = minetest.request_insecure_environment()
end
if not ie then
  error(modname .. " has to be added to the secure.trusted_mods in minetest.conf")
end
local luasocket = ie.require("socket.core")
if not luasocket then
  error("luasocket is not installed or was not found...")
end
local json = ie.require("cjson")
if not json then
  error("lua-cjson is not installed or was not found...")
end

-- setup network server port
local server, err = luasocket.udp()
if not server then 
  error(modname .. ": Socket error: " .. err) 
else
  minetest.log("action", modname .. ": " .. "listening on " .. host_ip .. ":" .. host_port)
end
server:setsockname(host_ip, host_port)
server:settimeout(0)
host_ip, host_port = server:getsockname()
if not host_ip or not host_port then error(modname .. ": Couldn't open server port!") end
local socket_clients = {}  -- a table with all connected clients with there options


-- receive network data and process them
minetest.register_globalstep(function(dtime)
  local data, ip, port, clientid
  data, ip, port = server:receivefrom()
  if data and string.find(data, "\n") then
    clientid = ip .. ":" .. port
    
    -- is it a known client, or do we need authentication?
    if socket_clients[clientid] and socket_clients[clientid].auth == true then  -- known client

      -- parse data as json
      local status, input = pcall(json.decode, data)
      
      if not status then
        minetest.log("error", modname .. ": " .. json.encode({error = input}))
        log("error", "JSON-Error: " .. input, ip, port)
        send(clientid, json.encode({error = input}))
        return
      end
      
      -- commands:
      -- we run lua code
      if input["lua"] then
        run_lua(input, clientid, ip, port)
        return
      end
      
      -- client requested something unimplemented
      send(clientid, json.encode({error = "Unknown command"}))
      
    else -- we need authentication
      authenticate(data, clientid, ip, port)
    end
  end
end)


minetest.register_on_shutdown(function()
  minetest.log("action", modname .. ": " .. "Closing port...")
  server:close()
end)


-- run lua code send by the client
function run_lua(input, clientid, ip, port)
  -- log the (shortend) code
  if string.len(input["lua"]) > 120 then
    log("action", "execute: " .. string.sub(input["lua"], 0, 120) .. " ...", ip, port)
  else
    log("action", "execute: " .. input["lua"], ip, port)
  end
  
  -- run
  local f = loadstring(input["lua"])
  local status, result1, result2, result3, result4 = pcall(f)  -- is there a more elegant way for unlimited results?
  
  -- Send return values
  local output = {}
  if status then
    output = json.encode({result = {result1, result2, result3, result4}})
    if output then
      if string.len(tostring(output)) > 120 then
        log("action", string.sub(tostring(output),0, 120) .. " ...", ip, port)
      else
        log("action", tostring(output), ip, port)
      end
      send(clientid, output)
   else
      log("action", "{\"result\": {}}")
      send(clientid, "{\"result\": {}}")
   end
  else  -- send lua errors
    local err = result1
    if type(err) == "table" then
      if err.code then
        log("error", json.encode({error = err}), ip, port)
        send(clientid, json.encode({error = err}))
      else
        log("error", "err.code is nil", ip, port)
        send(clientid, json.encode({error = "err.code is nil"}))
      end
    else
      log("error", json.encode({error = err}), ip, port)
      send(clientid, json.encode({error = err}))
    end
  end
  if err then
    log("error", "Error "..err.." in command", ip, port)
  end
end


-- authenticate clients
function authenticate(data, clientid, ip, port)
  local input, err = json.decode(data)
  
  if err then log("error", "json.decode error: " .. err, ip, port) end
  
  if not err and input["playername"] and input["password"] then
    local player = minetest.get_auth_handler().get_auth(input["playername"])
    
    if player and minetest.check_password_entry(input["playername"], player['password'], input["password"]) and minetest.check_player_privs(input["playername"], { server=true }) then
      log("action", "Player '" .. input["playername"] .. "' authentication successful", ip, port)
      socket_clients[clientid] = {["auth"] = true, playername=input["playername"], ip = ip, port = port}
      send(clientid, "{\"result\": \"auth_ok\"}")
    else
      log("error", "Wrong playername ('".. input["playername"] .."') or password", ip, port)
      server:sendto(json.encode({error = "authentication error"}) .. "\n", ip, port)
    end
    
  end
  
end


-- send data to the client
function send(clientid, data)
  data = data .. "\n"  -- \n is the terminator
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

-- just a logging function
function log(level, text, ip, port)
  if _debug or level ~= "action" then
    if ip and port then
      minetest.log(level, modname .. ": " .. text .. " from " .. ip .. ":" .. port)
    else
      minetest.log(level, modname .. ": " .. text)
    end
  end
end