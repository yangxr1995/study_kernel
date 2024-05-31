#!/usr/bin/lua

--  Nil: 表示空值。
--  Boolean: 逻辑值，true 或 false。
--  Number: 数值，Lua 5.3 以后区分整数和浮点数。
--  String: 字符串。
--  Table: 表，Lua 中的主要数据结构，用于数组、字典等。
--  Function: 函数。
--  Thread: 线程。
--  UserData: 用户数据，用于封装C语言的数据结构。
--  LightUserData: 轻量级用户数据，用于C语言的指针。

-- nil
local nilValue = nil
print(nilValue)  -- 输出: nil

-- bool
local isTrue = true
local isFalse = false

print(isTrue)  -- 输出: true
print(isFalse) -- 输出: false

-- num
local intValue = 10
local floatValue = 3.14

print(intValue)     -- 输出: 10
print(floatValue)  -- 输出: 3.14

-- string
local greeting = "Hello, World!"
local name = 'John Doe'

print(greeting) -- 输出: Hello, World!
print("Hello, " .. name) -- 输出: Hello, John Doe

-- table
local fruits = {"apple", "banana", "cherry"}
local person = {name = "Alice", age = 30}

-- unpack 将table对象拆分为多个对象
print(unpack(fruits))  -- 输出: apple   banana   cherry
-- table类似于key value
print(person.name)     -- 输出: Alice

-- function
local function greet(name)
    print("Hello, " .. name)
end

greet("Lua") -- 输出: Hello, Lua


-- thread
local function threadFunction()
    print("Running in a thread")
end

local co = coroutine.create(threadFunction)
coroutine.resume(co) -- 输出: Running in a thread

-- UserData通常与C语言交互时使用，这里仅提供一个简单示例
-- local myObject = userdata.create(someCData)
-- print(myObject) -- 输出: userdata: 0xXXXXXX

-- LightUserData通常用于C语言指针，这里提供一个简单示例
-- local myLightObject = lightuserdata.new(someCPointer)
-- print(myLightObject) -- 输出: lightuserdata: 0xXXXXXX
