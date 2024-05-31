#!/usr/bin/lua

-- string 在Lua中是不可变的，这意味着一旦创建了一个字符串，你就不能改变它的内容。所有的字符串操作都会返回一个新的字符串。

-- 定义字符串
local greeting = "Hello, World!"
local message = 'Lua is great!'

-- 字符串链接
local hello = "Hello, "
local world = "World!"
local sentence = hello .. world -- "Hello, World!"

-- 字符串长度
local length = string.len(greeting) -- 13

-- 查找和替换
local found = string.find(greeting, "World") -- 8
local newMessage = string.gsub(greeting, "World", "Lua") -- "Hello, Lua!"

-- 子字符串
local sub = string.sub(greeting, 1, 5) -- "Hello"

-- 模式匹配
-- 可用于搜索、替换和捕获字符串中的模式。
local pattern = "%w+"
-- 第一个下划线 _ 忽略了第一个返回值（模式匹配的起始位置）。
-- 第二个下划线 _ 忽略了第二个返回值（模式匹配的结束位置）。
-- word 变量接收第三个返回值，即第一个捕获组的内容。
local _, _, word = string.find(greeting, pattern) -- "Hello"

-- 遍历字符串
-- 虽然字符串是不可变的，但你可以使用 string.gmatch 来遍历字符串中的模式匹配结果。
-- foreach begin
-- Hello
-- World
-- foreach end
print("foreach begin")
for word in string.gmatch(greeting, "%w+") do
    print(word)
end
print("foreach end")

-- 格式化字符串
-- Lua没有专门的格式化字符串的函数，但你可以使用 string.format 来格式化数字和字符串。
person = { name = "Alice", age = 30}
local formatted = string.format("Name: %s, Age: %d", person.name, person.age) -- "Name: Alice, Age: 30"
