deploy_mini
======

用于远程部署,使用管理员权限运行指定脚本

【使用说明】

./deploy.pl usage:

-i   [指定配置文件, 必选]


-h   [帮助]




【配置文件】

使用了ini的标准配置方式
[to_xx]      
xx用于配置文件中唯一标识每台主机，此配置项用于远程/本地 部署和发布的信息。

ip=                   ip地址 

usr=                  部署工程的用户名

pass=                 用户的密码

root_pass=            root 密码

local_shell=           本地用于发布工程的shell的路径

