#!/bin/bash

# 设置备份目录
BACKUP_DIR="/vol2/1000/Storage/Backup/docker"

# 检查备份目录是否存在
if [ ! -d "$BACKUP_DIR" ]; then
    echo "备份目录 $BACKUP_DIR 不存在，请检查路径是否正确。"
    exit 1
fi

# 恢复 Docker 镜像
echo "开始恢复 Docker 镜像..."
for file in $BACKUP_DIR/*.tar; do
    if [ -f "$file" ]; then
        echo "正在恢复镜像：$file"
        docker load < "$file"
        echo "镜像 $file 恢复完成。"
    else
        echo "未找到镜像文件：$file"
    fi
done
echo "所有 Docker 镜像恢复完成。"

# 修改镜像标签
echo "开始恢复 Docker 镜像标签..."
docker_images=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep ":latest.bak$")
# 循环处理每个镜像
while IFS= read -r image; do
    # 提取仓库名和原始标签
    repository=$(echo "$image" | cut -d: -f1)
    original_tag=$(echo "$image" | cut -d: -f2)

    # 新标签为 :latest
    new_tag="latest"

    # 重新标记镜像
    echo "正在将 $image 重新标记为 $repository:$new_tag"
    docker tag "$image" "$repository:$new_tag"

    # 删除旧的镜像标签（可选）
    echo "删除旧的镜像标签 $image"
    docker rmi "$image"
done <<< "$docker_images"

echo "所有镜像的标签已更新完成。"

# 恢复数据卷
echo "开始恢复数据卷..."
for file in $BACKUP_DIR/backup_*.tar; do
    if [ -f "$file" ]; then
        volume=$(basename "$file" .tar | cut -d '_' -f 2-)
        echo "正在恢复数据卷：$volume"
        docker volume create "$volume"
        docker run --rm -v "$volume":/data -v "$file":/backup.tar busybox sh -c "tar xvf /backup.tar -C /data"
        echo "数据卷 $volume 恢复完成。"
    else
        echo "未找到数据卷备份文件：$file"
    fi
done
echo "所有数据卷恢复完成。"

# 创建容器

# 定义文件路径
file_path="docker_create.txt"

# 检查文件是否存在
if [ ! -f "$file_path" ]; then
    echo "文件 $file_path 不存在，请检查路径是否正确。"
    exit 1
fi

# 逐行读取文件内容并执行
echo "开始执行 Docker 命令..."
while IFS= read -r line; do
    # 跳过空行
    if [ -z "$line" ]; then
        continue
    fi

    # 执行 Docker 命令
    echo "执行命令: $line"
    eval "$line"

    # 检查命令是否成功执行
    if [ $? -eq 0 ]; then
        echo "命令执行成功: $line"
    else
        echo "命令执行失败: $line"
    fi
done < "$file_path"

echo "所有 Docker 命令执行完成。"

echo "所有操作完成！"
