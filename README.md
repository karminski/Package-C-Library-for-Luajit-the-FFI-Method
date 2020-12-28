Package-C-Library-for-Luajit-the-FFI-Method (利用 FFI 在 Luajit 里面轻松使用 C 语言库的简单教程)
-------------------------------------------

- @version:    20201228:1
- @author:     karminski <code.karminski@outlook.com>


看到有同学说 Lua 库少, 需要自己造轮子. 其实不是这样的, 今天给大家看一个魔法, 这个魔法可以让你非常方便的在 luajit 里面使用高性能的 C/CPP 库, 从而避免自己造轮子的痛苦.  

这个魔法是 FFI ([Foreign function interface](https://en.wikipedia.org/wiki/Foreign_function_interface)), 我并不打算仔细讲 FFI 原理, 所以简单来说, FFI 实现了跨语言的二进制接口. 它的优点是高效方便. 直接调用 ABI, 缺点也很明显, 出了问题直接会挂掉, 因此数据跨临界区前仔细检查就可以了.  

我们今天直接找个 C 语言库, 然后利用 FFI 在 luajit 里面调用这个函数库作为个大家的演示.  

# 什么? 这里竟然躺着一个高性能 base64 库?

我们以这个 repo 为例: [https://github.com/aklomp/base64](https://github.com/aklomp/base64). 这是一个 C 编写的 Base64 编码/解码库, 而且支持SIMD. 

可以简单运行下这个库的 benchmark:

```
karminski@router02:/data/works/base64$ make clean && SSSE3_CFLAGS=-mssse3 AVX2_CFLAGS=-mavx2 make && make -C test
...
Testing with buffer size 100 KB, fastest of 10 * 100
AVX2	encode	12718.47 MB/sec
AVX2	decode	14542.81 MB/sec
plain	encode	3657.40 MB/sec
plain	decode	3433.23 MB/sec
SSSE3	encode	7269.55 MB/sec
SSSE3	decode	8173.10 MB/sec
...
```

我的 CPU 是 Intel(R) Xeon(R) CPU E3-1246 v3 @ 3.50GHz, 可以看到CPU如果支持 AVX2 的话, 可以达到 12GB/s 以上, 这个性能非常强悍, 甚至连普通的SSD都跟不上了.

我们需要的第一步是把这个 repo 编译为动态库. 但是这个 repo 并没有提供动态库的编译选项, 所以我们魔改下这个项目的 Makefile. 

```Makefile
CFLAGS += -std=c99 -O3 -Wall -Wextra -pedantic

# Set OBJCOPY if not defined by environment:
OBJCOPY ?= objcopy

OBJS = \
  lib/arch/avx2/codec.o \
  lib/arch/generic/codec.o \
  lib/arch/neon32/codec.o \
  lib/arch/neon64/codec.o \
  lib/arch/ssse3/codec.o \
  lib/arch/sse41/codec.o \
  lib/arch/sse42/codec.o \
  lib/arch/avx/codec.o \
  lib/lib.o \
  lib/codec_choose.o \
  lib/tables/tables.o

SOOBJS = \
  lib/arch/avx2/codec.so \
  lib/arch/generic/codec.so \
  lib/arch/neon32/codec.so \
  lib/arch/neon64/codec.so \
  lib/arch/ssse3/codec.so \
  lib/arch/sse41/codec.so \
  lib/arch/sse42/codec.so \
  lib/arch/avx/codec.so \
  lib/lib.so \
  lib/codec_choose.so \
  lib/tables/tables.so

HAVE_AVX2   = 0
HAVE_NEON32 = 0
HAVE_NEON64 = 0
HAVE_SSSE3  = 0
HAVE_SSE41  = 0
HAVE_SSE42  = 0
HAVE_AVX    = 0

# The user should supply compiler flags for the codecs they want to build.
# Check which codecs we're going to include:
ifdef AVX2_CFLAGS
  HAVE_AVX2 = 1
endif
ifdef NEON32_CFLAGS
  HAVE_NEON32 = 1
endif
ifdef NEON64_CFLAGS
  HAVE_NEON64 = 1
endif
ifdef SSSE3_CFLAGS
  HAVE_SSSE3 = 1
endif
ifdef SSE41_CFLAGS
  HAVE_SSE41 = 1
endif
ifdef SSE42_CFLAGS
  HAVE_SSE42 = 1
endif
ifdef AVX_CFLAGS
  HAVE_AVX = 1
endif
ifdef OPENMP
  CFLAGS += -fopenmp
endif


.PHONY: all analyze clean

all: bin/base64 lib/libbase64.o lib/libbase64.so

bin/base64: bin/base64.o lib/libbase64.o lib/libbase64.so
	$(CC) $(CFLAGS) -o $@ $^

lib/libbase64.o: $(OBJS)
	$(LD) -r -o $@ $^
	$(OBJCOPY) --keep-global-symbols=lib/exports.txt $@

lib/libbase64.so: $(SOOBJS)
	$(LD) -shared -fPIC -o $@ $^
	$(OBJCOPY) --keep-global-symbols=lib/exports.txt $@

lib/config.h:
	@echo "#define HAVE_AVX2   $(HAVE_AVX2)"    > $@
	@echo "#define HAVE_NEON32 $(HAVE_NEON32)" >> $@
	@echo "#define HAVE_NEON64 $(HAVE_NEON64)" >> $@
	@echo "#define HAVE_SSSE3  $(HAVE_SSSE3)"  >> $@
	@echo "#define HAVE_SSE41  $(HAVE_SSE41)"  >> $@
	@echo "#define HAVE_SSE42  $(HAVE_SSE42)"  >> $@
	@echo "#define HAVE_AVX    $(HAVE_AVX)"    >> $@

$(OBJS): lib/config.h

$(SOOBJS): lib/config.h

# o
lib/arch/avx2/codec.o:   CFLAGS += $(AVX2_CFLAGS)
lib/arch/neon32/codec.o: CFLAGS += $(NEON32_CFLAGS)
lib/arch/neon64/codec.o: CFLAGS += $(NEON64_CFLAGS)
lib/arch/ssse3/codec.o:  CFLAGS += $(SSSE3_CFLAGS)
lib/arch/sse41/codec.o:  CFLAGS += $(SSE41_CFLAGS)
lib/arch/sse42/codec.o:  CFLAGS += $(SSE42_CFLAGS)
lib/arch/avx/codec.o:    CFLAGS += $(AVX_CFLAGS)
# so
lib/arch/avx2/codec.so:   CFLAGS += $(AVX2_CFLAGS)
lib/arch/neon32/codec.so: CFLAGS += $(NEON32_CFLAGS)
lib/arch/neon64/codec.so: CFLAGS += $(NEON64_CFLAGS)
lib/arch/ssse3/codec.so:  CFLAGS += $(SSSE3_CFLAGS)
lib/arch/sse41/codec.so:  CFLAGS += $(SSE41_CFLAGS)
lib/arch/sse42/codec.so:  CFLAGS += $(SSE42_CFLAGS)
lib/arch/avx/codec.so:    CFLAGS += $(AVX_CFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) -o $@ -c $<

%.so: %.c
	$(CC) $(CFLAGS) -shared -fPIC -o $@ -c $<

analyze: clean
	scan-build --use-analyzer=`which clang` --status-bugs make

clean:
	rm -f bin/base64 bin/base64.o lib/libbase64.o lib/libbase64.so lib/config.h $(OBJS)
```

看不懂没关系, Makefile 是如此的复杂, 我也看不懂, 仅仅是凭着感觉修改的, 然后他就恰好能运行了...  注意 Makefile 的缩进一定要用 "\t", 否则不符合语法会报错.  

然后我们进行编译:

```
AVX2_CFLAGS=-mavx2 SSSE3_CFLAGS=-mssse3 SSE41_CFLAGS=-msse4.1 SSE42_CFLAGS=-msse4.2 AVX_CFLAGS=-mavx make lib/libbase64.so 
```

这样我们就得到了 libbase64.so 动态库 (在 lib 里面). 这里还顺便开启了各种 SIMD 选项. 如果不需要的话可以关闭.   



# 魔改开始

当然这只是魔法, 不是炼金术, 所以是需要付出努力的, 我们要手动实现动态库的桥接, 首先我们需要查看我们要调用的函数需要什么参数. 这两个定义很简单, 我们需要传入:  

- 我们要编码或解码的字符串 ```const char *src```
- 该字符串的长度 ```size_t srclen```
- 指向返回结果的指针 ```char *out```
- 返回结果的长度的指针 ```size_t *outlen ```
- 还有 flag ```int flags```

```c
void base64_encode(const char *src, size_t srclen, char *out, size_t *outlen, int flags);
int  base64_decode(const char *src, size_t srclen, char *out, size_t *outlen, int flags);
```

然后我们就可以开始编写 ffi 桥接程序了. 首先把需要的库全都包含进来, 注意, 多用 local 没坏处, 使用 local 可以有效从局部查询, 避免低效的全局查询. 甚至其他包中的函数都可以 local 一下来提升性能.     

动态库的话用专用的 ```ffi.load``` 来引用.  

然后定义一个 _M 用来包裹我们的库. 这里跟 JavaScript 很像, JavaScript 在浏览器里有 window, Lua 有 _G. 我们要尽可能避免封装好的库直接扔给全局, 因此封装起来是个好办法.  

```lua
-- init
local ffi        = require "ffi"
local floor      = math.floor
local ffi_new    = ffi.new
local ffi_str    = ffi.string
local ffi_typeof = ffi.typeof
local C          = ffi.C
local libbase64  = ffi.load("./libbase64.so") -- change this path when needed.

local _M = { _VERSION = '0.0.1' }
```

然后是用 ffi.cdef 声明 ABI 接口, 这里更简单, 直接把源代码的头文件中的函数声明拷过来就完事了:  

```lua
-- cdef
ffi.cdef[[
void base64_encode(const uint8_t *src, size_t srclen, uint8_t *out, size_t *outlen, size_t flags);
int  base64_decode(const uint8_t *src, size_t srclen, uint8_t *out, size_t *outlen, size_t flags);
]]
```

接下来是最重要的类型转换:

```lua
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
```

我们用 ffi_typeof 来定义需要映射的数据类型, 然后用 ffi_new 来将其实例化, 分配内存空间. 具体来讲:  
  
我们定义了2种数据类型, 其中, ```local uint8t = ffi_typeof("uint8_t[?]")``` 类型用来传输字符串, 后面的问号是给 ```local out = ffi_new(uint8t, dlen)``` 中的 ```ffi_new``` 函数准备的, 它的第二个参数可以指定实例化该数据类型时的长度. 这样我们就得到了一个空的字符串数组, 用来装 C 函数返回的结果. 这里的 dlen 计算出了源字符串 base64 encode 之后的长度, 分配该长度即可.  
  
同样, ```local psizet = ffi_typeof("size_t[1]")``` 指定了一个 ```size_t *``` 类型. C 语言里面数组就是指针, 即 ``` size_t[0]``` 与 ```site_t*``` 是等价的. 因此我们分只有一个元素的 ```size_t``` 数组就得到了指向 ```size_t``` 类型的指针. 然后在 ```local outlen = ffi_new(psizet, 1) ``` 的时候后面的参数写的也是1, 不过这里写什么已经无所谓了, 它只是不支持传进去空, 所以我们相当于传了个 placeholder.  

在使用这个值的时候, 我们也是按照数组的模式去使用的: ```return ffi_str(out, outlen[0])```.  
  
需要注意的是, 一定要将 ```require "ffi"``` 以及 ```ffi.load``` 放在代码最底层, 否则会出现 ```table overflow``` 的情况.  


  
最后, 这个文件是这样子的:  

```lua
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
```



好了, 大功告成, 我们写个 demo 调用一下试试:

```lua
-- main.lua
local ffi_base64 = require "ffi-base64" 

local target = "https://example.com"

local r = ffi_base64.base64_encode(target, 0)
print("base64 encode result: \n"..r)

local r = ffi_base64.base64_decode(r, 0)
print("base64 decode result: \n"..r)

```

```
root@router02:/data/works/libbase64-ffi# luajit -v
LuaJIT 2.1.0-beta3 -- Copyright (C) 2005-2020 Mike Pall. https://luajit.org/
root@router02:/data/works/libbase64-ffi# luajit ./main.lua 
base64 encode result: 
aHR0cHM6Ly9leGFtcGxlLmNvbQ==
base64 decode result: 
https://example.com

```

搞定! 是不是很简单? 类似的 FFI 库还有很多, 各个语言也有不同程度的支持. 大家都可以尝试一下.  
最后, 当你遇到类似的问题的时候, 就可以回忆起来, 还有 FFI 这样一件趁手的兵(魔)器(法)在你的武器库里面.  
以上.  


