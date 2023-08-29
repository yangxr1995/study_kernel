# gdb
## gdbserver 和 gdb
将没有debug信息的文件上传到开发板，使用gdbserver开启调试
```shell
gdbserver <hostip:port> <bin>
gdbserver <hostip:port> --attach <pid>
```
在宿主机使用gdb
此处bin带debug info
```shell
gdb <bin>
# 如果目标符号在so中，需要设置 solib-search-path
# 首先不使用目标机上的 so文件
# 将 sysroot设置为 . , sysroot指目标机，gdbserver首先从sysroot/lib 中找so 文件
# 将其设置为 . ，则会加载失败
set sysroot .
# 当目标机加载so文件失败，则会从宿主机加载so文件，
# 因为宿主机的so文件才有debug info，所以使用宿主机的so文件
# 设置 solib-search-path 为so文件所在绝对路径
set solib-search-path <path>

target remote <hostip:port>

# 连接后会加载so
# 查看被加载的so的debug info 是否存在
info share
```


