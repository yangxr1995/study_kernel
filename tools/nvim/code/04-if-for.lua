#!/usr/bin/lua

local num = 10
if num > 5 then
    print("Number is greater than 5")
elseif num <= 5 then
    print("Number is less than or equal to 5")
end

local grade = 85
if grade >= 90 then
    print("A")
elseif grade >= 80 then
    print("B")
elseif grade >= 70 then
    print("C")
elseif grade >= 60 then
    print("D")
else
    print("F")
end

local i = 1
while i <= 5 do
    print(i)
    i = i + 1
end

-- do while
local i = 1
repeat
    print(i)
    i = i + 1
until i > 5


-- for 1 到 5
for i = 1, 5 do
    print(i)
end

-- 自定义步长
-- for 1 到 10 ,每次加2
for i = 1, 10, 2 do
    print(i)
end

local fruits = {"apple", "banana", "cherry"}
for index, value in ipairs(fruits) do
    print(index, value)
end

-- 迭代字典风格的表
for key, value in pairs(fruits) do
    print(key, value)
end

local isRaining = false
local haveUmbrella = true

if haveUmbrella and not isRaining then
    print("Don't need an umbrella today.")
elseif haveUmbrella or isRaining then
    print("Bring an umbrella just in case.")
end

for i = 1, 10 do
    if i == 5 then
        break -- 退出循环
    end
    print(i)
end

function findFirstEven(list)
    for _, value in ipairs(list) do
        if value % 2 == 0 then
            return value -- 找到第一个偶数并返回
        end
    end
end

local list = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
local firstEven = findFirstEven(list)
if firstEven then
	print("The first even number is:", firstEven)
else
	print("No even number found.")
end
