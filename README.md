deploy
======

用于tomcat的java工程包远程发布、部署工具

【使用说明】

./deploy.pl usage:

-i   [指定配置文件, 必选]

-n   [指定要更新的svn工程代码,并进行ant编译打包]

-q   [只更新sql]

-w   [只更新war包]

-t   [只同步系统时间, 需配置root_pass选项]

-s   [停掉远程tomcat工程]

-r   [重启远程tomcat工程]

-h   [帮助]


更新发布qkmusic工程步骤：
     更新及编译qkmusic

deploy.pl -i test.ini -n qkmusic

     发布工程

deploy.pl -i test.ini –w




【配置文件】

发布到测试机使用test.ini ，生产机 使用 cfg.ini

使用了ini的标准配置方式
[database]  数据库相关配置

[sql]       sql脚本更新的配置
dir=        sql的所在目录（相对路径）
backup_dir= 存储过程的备份目录（相对路径）

[svn]       工程代码svn的配置，用于取代码及编译
#ant执行文件的路径
antpath=/opt/data/apache-ant-1.9.4/bin
#svn代码下载的根目录
svnpath=/home/qkmusic/pl/ant/svnsrc
#编译环境，生成临时目录的根目录
basepath=/home/qkmusic/pl/ant
#tomcat的home目录
tomcat_home=/opt/data/apache-tomcat-7.0.55
#war文件输出目录
war=/home/qkmusic/pl/deploy/war

[to_xx]      
xx用于配置文件中唯一标识每台主机，此配置项用于远程/本地 部署和发布的信息。

ip=                   ip地址 

usr=                  部署工程的用户名

pass=                 用户的密码

war_dir               本地war包所在路径（相对路径）

war_file              本地war包名称（如果缺失，会发布war_dir目录中所有war包）

tomcat                远程tomcat路径（绝对路径）


service_path          远程war包存放路径（绝对路径）

backup_dir            远程工程目录备份路径（绝对路径）

backup_flag           是否进行备份 1.是 其他：否

remote_shell          远程用于发布工程的shell的路径（绝对路径）

local_shell           本地用于发布工程的shell的路径（绝对路径）

local_extent_shell    如果war包解压后需要运行某个shell做处理，此处指定此shell的本地路径（绝对路径）

