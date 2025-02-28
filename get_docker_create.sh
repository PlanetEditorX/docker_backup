#!/bin/bash

# 清空运行文件
> docker_create.txt

# 获取所有运行中的容器名称，并存储到变量中
running_containers=$(docker ps --format "{{.Names}}")

# 打印变量内容
echo "Running containers:"
echo "$running_containers"

# 检查目标参数是否不在数组中
check_not_in_array() {
    # array=("/" "/var/run/docker.sock" "/etc/localtime" "/run/dbus")
    array=("/")
    # 使用 printf 和 grep 检查
    if printf "%s\n" "${array[@]}" | grep -q "^$1$"; then
        return 1
    else
        return 0
    fi
}

# 添加cmd
# $1：关键字如-p
# $2：参数
set_cmd() {
    if [ "$2" != "null" ] && [ "$2" != "{}" ]; then
        if [ "$1" != "null" ] && [ "$1" != "{}" ]; then
            create_cmd+=("$1")
        fi
        create_cmd+=("$2")
    fi
}

# 定义一个函数来处理字符串添加引号
add_quotes_if_space() {
    local input="$1"
    if [[ "$input" =~ [[:space:]] ]]; then  # 检查是否包含空格
        local key="${input%%=*}"  # 提取等号前的内容
        local value="${input#*=}"  # 提取等号后的内容
        echo "${key}=\"${value}\""  # 重新组合并为等号后的内容添加双引号
    else
        echo "$input"  # 如果没有空格，保持原样
    fi
}

for container in $running_containers; do
    echo "Processing container: $container"
    # 在这里对每个容器执行操作
    # 使用 docker inspect 获取容器信息，并通过 jq 解析为 JSON 对象
    inspect_output=$(docker inspect "$container" --format '{{json .}}')
    create_cmd=("docker run -d")
    # 将 JSON 数据解析为 Bash 关联数组
    declare -A container_info
    while IFS="=" read -r key value; do
        container_info["$key"]="$value"
    done < <(echo "$inspect_output" | jq -r "to_entries|map(\"\(.key)=\(.value|tostring)\")|.[]")
    # 获取名称
    name=${container_info["Name"]}
    set_cmd "--name" ${name#/}

    # 获取挂载
    mounts_json_data=${container_info["Mounts"]}
    if [ -n "$mounts_json_data" ]; then
        # 使用 jq 解析 JSON 数据
        length=$(jq length <<< "$mounts_json_data")

        # 循环输出每个参数
        for ((i = 0; i < length; i++)); do
                source=$(jq -r ".[$i].Source" <<< "$mounts_json_data")
                destination=$(jq -r ".[$i].Destination" <<< "$mounts_json_data")
                # 检查并添加卷挂载参数
                if check_not_in_array "$source"; then
                    create_cmd+=("-v")
                    create_cmd+=("$source:$destination")
                fi
        done
    fi

    HostConfig_json_data=${container_info["HostConfig"]}
    if [ -n "$HostConfig_json_data" ]; then
        # 使用 jq 提取 重启策略
        restart_policy_name=$(echo "$HostConfig_json_data" | jq -r '.RestartPolicy.Name')
        set_cmd "--restart" $restart_policy_name

        # 使用 jq 提取 网络
        network_mode=$(echo "$HostConfig_json_data" | jq -r '.NetworkMode')
        set_cmd "--network" $network_mode

        # 使用 jq 提取 端口映射
        bindings_list_json=$(echo "$HostConfig_json_data" | jq -r '.PortBindings')
        if [ "$bindings_list_json" != "null" ] && [ "$bindings_list_json" != "{}" ]; then
            # 提取容器端口和宿主机端口
            readarray -t port_mappings < <(echo "$bindings_list_json" | jq -r 'to_entries | .[] | "\(.key | split("/")[0]):\(.value[0].HostPort)"')
            # 循环处理每个 HostPort
            for port in "${port_mappings[@]}"; do
                set_cmd "-p" $port
            done
        fi

    fi

    Config_json_data=${container_info["Config"]}
    # 使用 jq 提取 Env 数组，并将其转换为 Bash 数组
    Env=$(echo "$Config_json_data" | jq -r '.Env[]')
    readarray -t Env_array <<< "$Env"
    if [ "$Env_array" != "null" ] && [ "$Env_array" != "{}" ]; then
        for item in "${Env_array[@]}"; do
            # set_cmd "-e" "$item"
            new_item=$(add_quotes_if_space "$item")
            echo $new_item
            set_cmd "-e" "$new_item"
        done
    fi

    # 使用 jq 提取 Image 字段的值
    image=$(echo "$Config_json_data" | jq -r '.Image')
    set_cmd "null" $image

    echo "get create docker command:${create_cmd[@]}"
    echo "${create_cmd[@]}" >> docker_create.txt

done
