# docker_ubuntu_dev
一个适用于linux开发的docker容器

开发的时候需要用到ubuntu镜像,每次从头搭建一个ubuntu镜像非常麻烦,安装了一些开发常用的基本库.



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

