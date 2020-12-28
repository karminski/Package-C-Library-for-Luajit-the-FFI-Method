--[[
 
    ffi-base64.lua
    
    @version    20201228:1
    @author     karminski <code.karminski@outlook.com>

]]--

-- init
local ffi        = require "ffi"
local floor      = math.floor
local ffi_new    = ffi.new
local ffi_str    = ffi.string
local ffi_typeof = ffi.typeof
local C          = ffi.C
local libbase64  = ffi.load("./libbase64.so") -- change this path when needed.

local _M = { _VERSION = '0.0.1' }


-- cdef
ffi.cdef[[
void base64_encode(const uint8_t *src, size_t srclen, uint8_t *out, size_t *outlen, size_t flags);
int  base64_decode(const uint8_t *src, size_t srclen, uint8_t *out, size_t *outlen, size_t flags);
]]

-- define types
local uint8t    = ffi_typeof("uint8_t[?]") -- uint8_t *
local psizet    = ffi_typeof("size_t[1]")  -- size_t *

-- package function
function _M.base64_encode(src, flags)
    local dlen   = floor((#src * 8 + 4) / 6)
	local out    = ffi_new(uint8t, dlen)
	local outlen = ffi_new(psizet, 1)
	libbase64.base64_encode(src, #src, out, outlen, flags)
	return ffi_str(out, outlen[0])

end 

function _M.base64_decode(src, flags)
    local dlen   = floor((#src + 1) * 6 / 8)
    local out    = ffi_new(uint8t, dlen)
	local outlen = ffi_new(psizet, 1)
    libbase64.base64_decode(src, #src, out, outlen, flags)
    return ffi_str(out, outlen[0])
end 

return _M