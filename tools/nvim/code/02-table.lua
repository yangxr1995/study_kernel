#!/usr/bin/lua

-- table 是Lua中的主要数据结构，它是一个灵活的、可以动态调整大小的数组。
-- table 可以被用作数组、字典（键值对集合）或多维数组。

-- 创建一个空table
-- 创建一个table, 并将他的引用存储到 myTable
local myTable = {}

-- 创建一个带有初始值的table
-- key = 1, value = apple
-- key = 2, value = banana
-- key = 3, value = cherry
local fruits = {"apple", "banana", "cherry"}

-- 创建一个字典风格的table
-- key = name, value = Alice
-- key = age, value = 30
local person = {name = "Alice", age = 30}

-- 访问数组风格的table
local firstFruit = fruits[1] -- "apple"

-- 访问字典风格的table
local name = person.name -- "Alice"

-- 修改数组元素
-- 修改条目 key=2 value = blueberry
fruits[2] = "blueberry" -- 更改第二个元素

-- 修改字典元素
person.age = 25 -- 更新年龄

-- 遍历数组风格的table
-- 1       apple
-- 2       blueberry
-- 3       cherry
for index, value in ipairs(fruits) do
    print(index, value)
end

-- 遍历字典风格的table
-- name    Alice
-- age     25
for key, value in pairs(person) do
    print(key, value)
end


-- 数组风格是假象，本质上都是字典风格
-- 即数组风格是以 1, 2 ,3 做key
-- 字典风格是以 string 为 key
-- 1       apple
-- 2       blueberry
-- 3       cherry
for key, value in pairs(fruits) do
    print(key, value)
end

fruits["1"] = "111"

-- fruits[1] : apple
-- fruits["1"] : 111
print("fruits[1] : " .. fruits[1])
print("fruits[\"1\"] : " .. fruits["1"])


