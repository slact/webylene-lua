#!/bin/bash
export LUA_CPATH="./?.so;/home/leop/local/lib/lua/5.1/?.so;/home/leop/local/lib/lua/5.1/loadall.so"
export LUA_PATH="./?.lua;/home/leop/local/share/lua/5.1/?.lua;/home/leop/local/share/lua/5.1/?/init.lua;/home/leop/local/lib/lua/5.1/?.lua;/home/leop/local/lib/lua/5.1/?/init.lua"
export LD_LIBRARY_PATH="/lib:/usr/lib:/home/leop/local/lib"
exec /home/leop/local/bin/lua ../../bootstrap.lua --path ../.. --protocol cgi