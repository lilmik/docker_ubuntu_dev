# docker_ubuntu_dev
一个适用于linux开发的docker容器

开发的时候需要用到ubuntu镜像,默认提供的ubuntu镜像为了保持轻量化,里面缺少了很多库和组件,用起来哪哪都不顺:

> - 原始ubuntu镜像未开启ssh,docker中linux开启ssh自启动也和物理机/虚拟机方式有些差异
> - 原始ubuntu镜像只有root用户,没有设定密码
> - 原始ubuntu镜像不含bash-completion包,缺少Tab补全功能用起来很麻烦
> - 原始ubuntu镜像时区和时间信息不对,有时候依赖时间需要排查一些内容的时候,用起来麻烦
> - 原始ubuntu镜像页缺少vi | vim | nano这些终端文本编辑工具
> - ......

那就干脆直接通过脚本一次性把这些问题都解决掉算了.

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
-v /home/test:/home/test \
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

