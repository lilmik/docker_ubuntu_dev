# docker_ubuntu_dev
一个适用于linux开发的docker容器,基于ubuntu22.04创建.

开发的时候需要用到ubuntu镜像,默认提供的ubuntu镜像为了保持轻量化,里面缺少了很多库和组件,用起来哪哪都不顺:

> - 原始ubuntu镜像未开启ssh,docker中linux开启ssh自启动也和物理机/虚拟机方式有些差异
> - 原始ubuntu镜像只有`root`用户,没有设定密码
> - 原始ubuntu镜像不含`bash-completion`包,缺少`Tab`补全功能用起来很麻烦
> - 原始ubuntu镜像时区和时间信息不对,有时候依赖时间需要排查一些内容的时候,用起来麻烦
> - 原始ubuntu镜像页缺少`vi | vim | nano`这些终端文本编辑工具
> - ......

那就干脆直接通过脚本一次性把这些问题都解决掉算了.

------

## 镜像使用说明

> - 暴露了容器`22`端口,可以在创建容器的时候自行增加宿主机的端口映射.开启了`ssh`服务并自动启动.`dev`或者`root`用户都可以通过`ssh`工具进行登录.
> - 镜像中创建了一个名为`dev`的管理员用户,`root`用户和`dev`用户的密码都是`dev`.
> - 加入了bash-completion修正,并且注释了/etc/apt/apt.conf.d/docker-clean中部分影响apt install <tab> <tab>补全功能的内容,会让镜像容量变得稍大,但是后续需要补充安装包的时候更方便
> - 加入了时区设置到Asia/Shanghai,并且加入了每小时自动同步一次时间的功能
> - 补充了部分常用工具,如`vi | vim | nano | btop | neofetch`等
> - 加入了一个ssh登陆后打印`系统信息 | IP地址 | 当前时间 | 当前时区`的功能

我目前这版镜像上传到了docker hub,提前构建了amd64和arm64镜像,可以直接使用.链接地址是:

https://hub.docker.com/r/ignislee/ubuntu2204_dev/tags

一键启用命令参考:

```bash
sudo docker run -d \
--name ubuntu_2204 \
--hostname ubuntu_2204 \
--privileged \
--restart=always \
-p 5522:22 \
-v ./app:/app \
ignislee/ubuntu2204_dev:1.0
```

使用WSL测试使用效果如下图:

![image-20251007102232750](./README.assets/image-20251007102232750.png)

------

## 手动创建常用命令

```bash
# macvlan方式
sudo docker run -d \
  --name ubuntu_2204 \
  --hostname ubuntu_2204 \
  --network 1panel_macvlan \
  --ip=192.168.1.233 \
  --privileged \
  --restart=always \
  ubuntu_dev:22.04


# 桥接，并映射端口到宿主机
sudo docker run -d \
  --name ubuntu_2204 \
  --hostname ubuntu_2204 \
  --network bridge \
  --privileged \
  --restart=always \
  -p 5522:22 \
  ubuntu_dev:22.04


# 桥接，并映射端口到宿主机，并挂载外部文件夹
sudo docker run -d \
--name ubuntu_2204 \
--hostname ubuntu_2204 \
--network bridge \
--privileged \
--restart=always \
-p 5522:22 \
-v ./app:/app \
ubuntu_dev:22.04
```



------

## 基本构建命令，-t指定镜像名称和标签
```bash
docker build -t ubuntu_dev:22.04 .
```



## 构建成功后查看镜像
```bash
docker images | grep ubuntu_dev:22.04
```



## 运行构建好的镜像验证

```bash
docker run ubuntu_dev:22.04
```



## 将镜像保存为tar文件

```bash
docker save -o [保存的文件名.tar] [镜像名称:标签]
```



## 保存镜像到当前目录

```bash
docker save -o ubuntu_dev-22.04.tar ubuntu_dev:22.04
```



## 加载保存的镜像

```bash
docker load -i ubuntu_dev-22.04.tar
```



------

## docker compose启动命令

```bash
sudo docker compose down && sudo docker compose up -d
```

