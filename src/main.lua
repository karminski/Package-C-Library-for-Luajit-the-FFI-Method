-- main.lua
local ffi_base64 = require "ffi-base64" 

local target = "https://example.com"

local r = ffi_base64.base64_encode(target, 0)
print("base64 encode result: \n"..r)

local r = ffi_base64.base64_decode(r, 0)
print("base64 decode result: \n"..r)