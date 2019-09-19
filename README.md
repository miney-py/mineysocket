# mineysocket - A network api mod for minetest

The goal of this mod is to open minetest for other scripting languages.

For that this mod opens a udp network port where it receives lua snippets to execute these inside the minetest api environment.
That allows you to write a socket client in your favorite language to wrap api functions over network/internet.

The reference implementation is miney (not released yet).

## Requirements

* luasockets
* lua-cjson

~~Mineysocket is currently only developed and tested under linux. But a minetest-server should run very well in the Windows Subsystem for Linux with a Debian Buster.~~

**Update 2019/09: A windows minetest distribution bundled with luasocket and lua-cjson is nearly ready and will be published in the miney repo.**

## Notes

Clients can only run code after authentication and if the user has "server" privilege (or if connected from 127.0.0.1).

This may change, but currently authenticated users can do anything in the minetest api, also change there own and other users privileges!

**You use this at your own risk!**

## Todo

- [ ] Authentication without sending cleartext password
- [ ] Implement limited user rights with a fixed set of available commands
- [x] ~~Disable authentication for 127.0.0.1 clients~~
- [ ] Catch json encode errors
- [ ] Receive packages with multiple chunks
- [x] ~~Callback functions~~
- [x] ~~clientlist cleanup (delete unavailable/disconnected clients)~~
- [ ] Send basic events like player_joined or chatmessage

## Installation with Debian Buster

The latest minetest version is in the backports repository for buster, so it's very easy to install: https://wiki.minetest.net/Setting_up_a_server/Debian
```
apt install lua-socket lua-cjson
cd /var/games/minetest-server/.minetest/mods
git clone <clone url of this repo>
```
* Edit /var/games/minetest-server/.minetest/worlds/\<your_world\>/world.mt and add:
```
load_mod_mineysocket = true
```
* Connect at least once with minetest to your server and login with a username + password, to get you registered
* Edit /etc/minetest/minetest.conf
  * name = \<your_playername\>  # This gives you all privileges on your server
  * secure.trusted_mods = mineysocket  # This is needed for luasocket and lua-cjson
  * Optional but recommended:
    * enable_rollback_recording = true  # This allows you to cleanup your world

## Protocol description

mineysocket is a simple JSON-based UDP-Protocol. Send a valid JSON-String with a tailing linebreak (`\n`) to the port 
and mineysocket responds a JSON string with a tailing linebreak.

### Authentication

```
>>> {"playername": "player", "password": "my_password"}\n
<<< {result = ["auth_ok", "127.0.0.1:31928"]}\n
``` 
Send playername and password and you get auth_ok with your clientid (store this for later).

On error you get a error object:
```
{error = "authentication error"}\n
```
Btw: All errors look like this, with different error descriptions.

### Run lua code

After authentication you are ready to send a command. An JSON object key is a command, in this example 
"lua" to run lua code.
```
>>> {"lua": "return 12 + 2, \"something\""}\n
<<< {"result": [14, "something"]}\n
```
Lua code runs inside a function definition, so you need to return value to get a result send back to you. 
As you see, you can return multiple values.

More commands will be added later.