#!/usr/bin/lua

print("arg num : "..#arg)

-- 打印所有传递给脚本的参数
print("all arg:")
for i, arg in ipairs(arg) do
    print(i, arg)
end

-- 打印脚本名称（第一个参数）
print("Script name: " .. arg[0])

-- 打印所有剩余的参数（不包括脚本名称）
print("Remaining arguments:")
for i = 2, #arg do
    print(arg[i])
end


print("-----------------")

print("arg num : "..#arg)

local opt = {name = "", file = ""}
local except_opt_name = "-n"
local except_opt_file = "-f"

for i, a in ipairs(arg) do
  if a == except_opt_name then
    if arg[i + 1] then
      opt.name = arg[i + 1]
    else
      print("Option '" .. except_opt_name .. "' requires an argument")
    end
  elseif a == except_opt_file then
    if arg[i + 1] then
      opt.file = arg[i + 1]
    else
      print("Option '" .. except_opt_file .. "' requires an argument")
    end
  end
end
if opt.name ~= "" and opt.name ~= nil then
  print("name : " .. opt.name)
end

if opt.file ~= "" and opt.file ~= nil then
  print("file : " .. opt.file)
end

print("-------------- 使用argparse库 --------------")

-- script.lua
local argparse = require "argparse"

local parser = argparse("script", "An example.")
parser:argument("input", "Input file.")
parser:option("-o --output", "Output file.", "a.out")
parser:option("-I --include", "Include locations."):count("*")

local args = parser:parse()
