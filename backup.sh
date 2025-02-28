#!/bin/bash

# 设置备份目录
BACKUP_DIR="/vol2/1000/Storage/Backup/docker"
mkdir -p $BACKUP_DIR

echo "获取并保存创建命令..."
bash get_docker_create.sh


# 删除旧的备份文件
echo "清理所有容器的备份..."
old_backup_files=$(ls $BACKUP_DIR/*.tar 2> /dev/null)
if [ -n "$old_backup_files" ]; then
    for old_file in $old_backup_files; do
        echo "删除旧的备份文件：$old_file"
        rm -f "$old_file"
    done
fi

# 备份所有容器的镜像
echo "备份所有容器的镜像..."
for container in $(docker ps -aq); do
    container_name=$(docker inspect --format '{{.Name}}' $container | sed 's/\///g')
    echo "正在处理容器：$container_name ($container)"
    # 创建新的备份
    # 获取镜像名字
    container_image=$(docker inspect --format '{{.Config.Image}}' "$container")
    # 定义容器名字
    image_name="$container_image.bak"
    echo "正在提交容器到镜像：$image_name"
    docker commit $container $image_name

    backup_file="$BACKUP_DIR/backup_$container_name.tar"
    echo "正在保存镜像到文件：$backup_file"
    docker save $image_name > $backup_file
    echo "容器 $container_name 的镜像备份完成。"

    # 删除临时镜像
    echo "删除临时镜像：$image_name"
    docker rmi $image_name
done

echo "备份完成！"
