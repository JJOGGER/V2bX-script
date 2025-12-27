#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

# 检查系统是否有 IPv6 地址
check_ipv6_support() {
    if ip -6 addr | grep -q "inet6"; then
        echo "1"  # 支持 IPv6
    else
        echo "0"  # 不支持 IPv6
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启V2bX" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/JJOGGER/V2bX-script/master/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/JJOGGER/V2bX-script/master/install.sh) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}更新完成，已自动重启 V2bX，请使用 V2bX log 查看运行日志${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "V2bX在修改配置后会自动尝试重启"
    vi /etc/V2bX/config.json
    sleep 2
    restart
    check_status
    case $? in
        0)
            echo -e "V2bX状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "检测到您未启动V2bX或V2bX自动重启失败，是否查看日志？[Y/n]" && echo
            read -e -rp "(默认: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "V2bX状态: ${red}未安装${plain}"
    esac
}

list_nodes() {
    if [ ! -f "/etc/V2bX/config.json" ]; then
        echo -e "${red}未找到 /etc/V2bX/config.json 配置文件，请先生成或配置节点${plain}"
        return 1
    fi

    if command -v python3 &> /dev/null; then
        python3 << 'PYTHON_LIST_NODES'
import json
import sys

path = "/etc/V2bX/config.json"
try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前配置中未找到任何节点。")
        sys.exit(0)
    print("当前已配置的节点列表：")
    for idx, node in enumerate(nodes):
        core = node.get("Core", "")
        node_type = node.get("NodeType", "")
        node_id = node.get("NodeID", "")
        api_host = node.get("ApiHost", "")
        print(f"[索引 {idx}] Core={core}, NodeType={node_type}, NodeID={node_id}, ApiHost={api_host}")
except Exception as e:
    print(f"读取节点列表失败: {e}")
PYTHON_LIST_NODES
    elif command -v python &> /dev/null; then
        python << 'PYTHON_LIST_NODES'
import json
import sys

path = "/etc/V2bX/config.json"
try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前配置中未找到任何节点。")
        sys.exit(0)
    print("当前已配置的节点列表：")
    for idx, node in enumerate(nodes):
        core = node.get("Core", "")
        node_type = node.get("NodeType", "")
        node_id = node.get("NodeID", "")
        api_host = node.get("ApiHost", "")
        print(f"[索引 {idx}] Core={core}, NodeType={node_type}, NodeID={node_id}, ApiHost={api_host}")
except Exception as e:
    print(f"读取节点列表失败: {e}")
PYTHON_LIST_NODES
    else
        echo -e "${red}未找到 Python，无法列出节点信息，请手动编辑 /etc/V2bX/config.json${plain}"
        return 1
    fi
}

edit_node_id() {
    echo "此功能用于修改已存在节点的 NodeID（面板中的节点编号），不会修改其他配置字段。"
    if [ ! -f "/etc/V2bX/config.json" ]; then
        echo -e "${red}未找到 /etc/V2bX/config.json 配置文件，请先生成或配置节点${plain}"
        return 1
    fi

    list_nodes
    echo ""
    read -rp "请输入要修改的节点索引（上方列表中的索引数字）: " node_index
    if ! [[ "$node_index" =~ ^[0-9]+$ ]]; then
        echo -e "${red}索引必须为非负整数${plain}"
        return 1
    fi

    read -rp "请输入新的 NodeID（面板中的节点ID，必须为正整数）: " new_node_id
    if ! [[ "$new_node_id" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${red}NodeID 必须为正整数${plain}"
        return 1
    fi

    if command -v python3 &> /dev/null; then
        python3 << PYTHON_EDIT_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")
new_id = int("$new_node_id")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    old_id = nodes[idx].get("NodeID")
    nodes[idx]["NodeID"] = new_id
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    print(f"已将索引 {idx} 节点的 NodeID 从 {old_id} 修改为 {new_id}")
except Exception as e:
    print(f"修改节点失败: {e}")
    sys.exit(1)
PYTHON_EDIT_NODE
        result=$?
    elif command -v python &> /dev/null; then
        python << PYTHON_EDIT_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")
new_id = int("$new_node_id")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    old_id = nodes[idx].get("NodeID")
    nodes[idx]["NodeID"] = new_id
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    print(f"已将索引 {idx} 节点的 NodeID 从 {old_id} 修改为 {new_id}")
except Exception as e:
    print(f"修改节点失败: {e}")
    sys.exit(1)
PYTHON_EDIT_NODE
        result=$?
    else
        echo -e "${red}未找到 Python，无法修改节点配置，请手动编辑 /etc/V2bX/config.json${plain}"
        return 1
    fi

    if [ "$result" -eq 0 ]; then
        echo -e "${green}节点 NodeID 修改完成，正在重启 V2bX 使配置生效${plain}"
        restart
    else
        echo -e "${red}节点 NodeID 修改失败，请检查上方错误信息${plain}"
    fi
}

edit_node_full() {
    echo "此功能用于修改单个节点的完整配置（整段 JSON），适合高级用户精细调整。"
    if [ ! -f "/etc/V2bX/config.json" ]; then
        echo -e "${red}未找到 /etc/V2bX/config.json 配置文件，请先生成或配置节点${plain}"
        return 1
    fi

    list_nodes
    echo ""
    read -rp "请输入要修改的节点索引（上方列表中的索引数字）: " node_index
    if ! [[ "$node_index" =~ ^[0-9]+$ ]]; then
        echo -e "${red}索引必须为非负整数${plain}"
        return 1
    fi

    tmp_file="/tmp/V2bX_node_${node_index}.json"

    # 导出当前节点配置到临时文件
    if command -v python3 &> /dev/null; then
        python3 << PYTHON_DUMP_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    node = nodes[idx]
    with open("$tmp_file", "w", encoding="utf-8") as f:
        json.dump(node, f, indent=4, ensure_ascii=False)
    print(f"已将索引 {idx} 节点配置导出到 $tmp_file")
except Exception as e:
    print(f"导出节点失败: {e}")
    sys.exit(1)
PYTHON_DUMP_NODE
        dump_result=$?
    elif command -v python &> /dev/null; then
        python << PYTHON_DUMP_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    node = nodes[idx]
    with open("$tmp_file", "w", encoding="utf-8") as f:
        json.dump(node, f, indent=4, ensure_ascii=False)
    print(f"已将索引 {idx} 节点配置导出到 $tmp_file")
except Exception as e:
    print(f"导出节点失败: {e}")
    sys.exit(1)
PYTHON_DUMP_NODE
        dump_result=$?
    else
        echo -e "${red}未找到 Python，无法导出节点配置，请手动编辑 /etc/V2bX/config.json${plain}"
        return 1
    fi

    if [ "$dump_result" -ne 0 ]; then
        echo -e "${red}导出节点配置失败，请检查上方错误信息${plain}"
        return 1
    fi

    echo -e "${yellow}即将使用 vi 打开节点配置文件，请根据需要修改 JSON 内容，保存退出即可生效。${plain}"
    echo -e "${yellow}文件路径: $tmp_file${plain}"
    read -rp "按回车继续编辑..." _
    vi "$tmp_file"

    # 将修改后的节点写回配置文件
    if command -v python3 &> /dev/null; then
        python3 << PYTHON_APPLY_NODE
import json
import sys
import os

cfg_path = "/etc/V2bX/config.json"
idx = int("$node_index")
tmp_path = "$tmp_file"

try:
    if not os.path.exists(tmp_path):
        print("临时节点文件不存在，已取消修改。")
        sys.exit(1)

    with open(tmp_path, "r", encoding="utf-8") as f:
        new_node = json.load(f)

    with open(cfg_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)

    nodes[idx] = new_node

    with open(cfg_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)

    print(f"已将修改后的节点配置写回索引 {idx}")
except Exception as e:
    print(f"应用节点修改失败: {e}")
    sys.exit(1)
PYTHON_APPLY_NODE
        apply_result=$?
    elif command -v python &> /dev/null; then
        python << PYTHON_APPLY_NODE
import json
import sys
import os

cfg_path = "/etc/V2bX/config.json"
idx = int("$node_index")
tmp_path = "$tmp_file"

try:
    if not os.path.exists(tmp_path):
        print("临时节点文件不存在，已取消修改。")
        sys.exit(1)

    with open(tmp_path, "r", encoding="utf-8") as f:
        new_node = json.load(f)

    with open(cfg_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)

    nodes[idx] = new_node

    with open(cfg_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)

    print(f"已将修改后的节点配置写回索引 {idx}")
except Exception as e:
    print(f"应用节点修改失败: {e}")
    sys.exit(1)
PYTHON_APPLY_NODE
        apply_result=$?
    else
        echo -e "${red}未找到 Python，无法应用节点修改，请手动编辑 /etc/V2bX/config.json${plain}"
        return 1
    fi

    if [ "$apply_result" -eq 0 ]; then
        echo -e "${green}节点完整配置修改完成，正在重启 V2bX 使配置生效${plain}"
        restart
    else
        echo -e "${red}节点完整配置修改失败，请检查上方错误信息${plain}"
    fi
}

delete_node() {
    echo "此功能用于删除单个节点配置（从 Nodes 数组中移除）。"
    if [ ! -f "/etc/V2bX/config.json" ]; then
        echo -e "${red}未找到 /etc/V2bX/config.json 配置文件，请先生成或配置节点${plain}"
        return 1
    fi

    list_nodes
    echo ""
    read -rp "请输入要删除的节点索引（上方列表中的索引数字）: " node_index
    if ! [[ "$node_index" =~ ^[0-9]+$ ]]; then
        echo -e "${red}索引必须为非负整数${plain}"
        return 1
    fi

    read -rp "确定要删除该节点配置吗？(y/n): " confirm_del
    if [[ "$confirm_del" != "y" && "$confirm_del" != "Y" ]]; then
        echo "已取消删除操作。"
        return 0
    fi

    if command -v python3 &> /dev/null; then
        python3 << PYTHON_DELETE_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前没有可删除的节点。")
        sys.exit(1)
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    removed = nodes.pop(idx)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    print(f"已删除索引 {idx} 的节点（NodeID={removed.get('NodeID')}, Core={removed.get('Core')}, NodeType={removed.get('NodeType')})")
except Exception as e:
    print(f"删除节点失败: {e}")
    sys.exit(1)
PYTHON_DELETE_NODE
        del_result=$?
    elif command -v python &> /dev/null; then
        python << PYTHON_DELETE_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前没有可删除的节点。")
        sys.exit(1)
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    removed = nodes.pop(idx)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    print(f"已删除索引 {idx} 的节点（NodeID={removed.get('NodeID')}, Core={removed.get('Core')}, NodeType={removed.get('NodeType')})")
except Exception as e:
    print(f"删除节点失败: {e}")
    sys.exit(1)
PYTHON_DELETE_NODE
        del_result=$?
    else
        echo -e "${red}未找到 Python，无法删除节点配置，请手动编辑 /etc/V2bX/config.json${plain}"
        return 1
    fi

    if [ "$del_result" -eq 0 ]; then
        echo -e "${green}节点已删除，正在重启 V2bX 使配置生效${plain}"
        restart
    else
        echo -e "${red}节点删除失败，请检查上方错误信息${plain}"
    fi
}

batch_update_api_host() {
    echo "此功能用于批量修改所有节点的机场地址（ApiHost），适用于机场域名被墙的情况。"
    echo -e "${yellow}注意：此操作会修改所有节点的 ApiHost，但不会修改其他配置（如 NodeID、协议类型等）${plain}"
    if [ ! -f "/etc/V2bX/config.json" ]; then
        echo -e "${red}未找到 /etc/V2bX/config.json 配置文件，请先生成或配置节点${plain}"
        return 1
    fi

    list_nodes
    echo ""
    read -rp "请输入新的机场地址（ApiHost，例如：https://new-domain.com）: " new_api_host
    if [ -z "$new_api_host" ]; then
        echo -e "${red}机场地址不能为空${plain}"
        return 1
    fi

    read -rp "确定要将所有节点的 ApiHost 修改为 '$new_api_host' 吗？(y/n): " confirm_update
    if [[ "$confirm_update" != "y" && "$confirm_update" != "Y" ]]; then
        echo "已取消修改操作。"
        return 0
    fi

    if command -v python3 &> /dev/null; then
        python3 << PYTHON_BATCH_UPDATE
import json
import sys

path = "/etc/V2bX/config.json"
new_host = "$new_api_host"

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前配置中未找到任何节点。")
        sys.exit(1)
    
    updated_count = 0
    for idx, node in enumerate(nodes):
        old_host = node.get("ApiHost", "")
        if old_host != new_host:
            node["ApiHost"] = new_host
            updated_count += 1
            print(f"节点 [索引 {idx}] (NodeID={node.get('NodeID')}): {old_host} -> {new_host}")
    
    if updated_count == 0:
        print("所有节点的 ApiHost 已经是 '$new_host'，无需修改。")
    else:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=4, ensure_ascii=False)
        print(f"\n已成功更新 {updated_count} 个节点的 ApiHost")
except Exception as e:
    print(f"批量更新失败: {e}")
    sys.exit(1)
PYTHON_BATCH_UPDATE
        update_result=$?
    elif command -v python &> /dev/null; then
        python << PYTHON_BATCH_UPDATE
import json
import sys

path = "/etc/V2bX/config.json"
new_host = "$new_api_host"

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前配置中未找到任何节点。")
        sys.exit(1)
    
    updated_count = 0
    for idx, node in enumerate(nodes):
        old_host = node.get("ApiHost", "")
        if old_host != new_host:
            node["ApiHost"] = new_host
            updated_count += 1
            print(f"节点 [索引 {idx}] (NodeID={node.get('NodeID')}): {old_host} -> {new_host}")
    
    if updated_count == 0:
        print("所有节点的 ApiHost 已经是 '$new_host'，无需修改。")
    else:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=4, ensure_ascii=False)
        print(f"\n已成功更新 {updated_count} 个节点的 ApiHost")
except Exception as e:
    print(f"批量更新失败: {e}")
    sys.exit(1)
PYTHON_BATCH_UPDATE
        update_result=$?
    else
        echo -e "${red}未找到 Python，无法批量更新节点配置，请手动编辑 /etc/V2bX/config.json${plain}"
        return 1
    fi

    if [ "$update_result" -eq 0 ]; then
        echo -e "${green}批量更新完成，正在重启 V2bX 使配置生效${plain}"
        restart
    else
        echo -e "${red}批量更新失败，请检查上方错误信息${plain}"
    fi
}

uninstall() {
    confirm "确定要卸载 V2bX 吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        service V2bX stop
        rc-update del V2bX
        rm /etc/init.d/V2bX -f
    else
        systemctl stop V2bX
        systemctl disable V2bX
        rm /etc/systemd/system/V2bX.service -f
        systemctl daemon-reload
        systemctl reset-failed
    fi
    rm /etc/V2bX/ -rf
    rm /usr/local/V2bX/ -rf

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/V2bX -f${plain} 进行删除"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}V2bX已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service V2bX start
        else
            systemctl start V2bX
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}V2bX 启动成功，请使用 V2bX log 查看运行日志${plain}"
        else
            echo -e "${red}V2bX可能启动失败，请稍后使用 V2bX log 查看日志信息${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    if [[ x"${release}" == x"alpine" ]]; then
        service V2bX stop
    else
        systemctl stop V2bX
    fi
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}V2bX 停止成功${plain}"
    else
        echo -e "${red}V2bX停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    if [[ x"${release}" == x"alpine" ]]; then
        service V2bX restart
    else
        systemctl restart V2bX
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 重启成功，请使用 V2bX log 查看运行日志${plain}"
    else
        echo -e "${red}V2bX可能启动失败，请稍后使用 V2bX log 查看日志信息${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    if [[ x"${release}" == x"alpine" ]]; then
        service V2bX status
    else
        systemctl status V2bX --no-pager -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add V2bX
    else
        systemctl enable V2bX
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 设置开机自启成功${plain}"
    else
        echo -e "${red}V2bX 设置开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del V2bX
    else
        systemctl disable V2bX
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 取消开机自启成功${plain}"
    else
        echo -e "${red}V2bX 取消开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}alpine系统暂不支持日志查看${plain}\n" && exit 1
    else
        journalctl -u V2bX.service -e --no-pager -f
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    bash <(curl -L -s https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh)
}

update_shell() {
    wget -O /usr/bin/V2bX -N --no-check-certificate https://raw.githubusercontent.com/JJOGGER/V2bX-script/master/V2bX.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/V2bX
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/V2bX/V2bX ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service V2bX status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status V2bX | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_enabled() {
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(rc-update show | grep V2bX)
        if [[ x"${temp}" == x"" ]]; then
            return 1
        else
            return 0
        fi
    else
        temp=$(systemctl is-enabled V2bX)
        if [[ x"${temp}" == x"enabled" ]]; then
            return 0
        else
            return 1;
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}V2bX已安装，请不要重复安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装V2bX${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "V2bX状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "V2bX状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "V2bX状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

generate_x25519_key() {
    echo -n "正在生成 x25519 密钥："
    /usr/local/V2bX/V2bX x25519
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_V2bX_version() {
    echo -n "V2bX 版本："
    /usr/local/V2bX/V2bX version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

add_node_config() {
    echo -e "${green}请选择节点核心类型：${plain}"
    echo -e "${green}1. xray${plain}"
    echo -e "${green}2. singbox${plain}"
    echo -e "${green}3. hysteria2${plain}"
    read -rp "请输入：" core_type
    if [ "$core_type" == "1" ]; then
        core="xray"
        core_xray=true
    elif [ "$core_type" == "2" ]; then
        core="sing"
        core_sing=true
    elif [ "$core_type" == "3" ]; then
        core="hysteria2"
        core_hysteria2=true
    else
        echo "无效的选择。请选择 1 2 3。"
        continue
    fi
    while true; do
        read -rp "请输入节点Node ID：" NodeID
        # 判断NodeID是否为正整数
        if [[ "$NodeID" =~ ^[0-9]+$ ]]; then
            break  # 输入正确，退出循环
        else
            echo "错误：请输入正确的数字作为Node ID。"
        fi
    done

    if [ "$core_hysteria2" = true ] && [ "$core_xray" = false ] && [ "$core_sing" = false ]; then
        NodeType="hysteria2"
    else
        echo -e "${yellow}请选择节点传输协议：${plain}"
        echo -e "${green}1. Shadowsocks${plain}"
        echo -e "${green}2. Vless${plain}"
        echo -e "${green}3. Vmess${plain}"
        if [ "$core_sing" == true ]; then
            echo -e "${green}4. Hysteria${plain}"
            echo -e "${green}5. Hysteria2${plain}"
        fi
        if [ "$core_hysteria2" == true ] && [ "$core_sing" = false ]; then
            echo -e "${green}5. Hysteria2${plain}"
        fi
        echo -e "${green}6. Trojan${plain}"  
        if [ "$core_sing" == true ]; then
            echo -e "${green}7. Tuic${plain}"
            echo -e "${green}8. AnyTLS${plain}"
        fi
        read -rp "请输入：" NodeType
        case "$NodeType" in
            1 ) NodeType="shadowsocks" ;;
            2 ) NodeType="vless" ;;
            3 ) NodeType="vmess" ;;
            4 ) NodeType="hysteria" ;;
            5 ) NodeType="hysteria2" ;;
            6 ) NodeType="trojan" ;;
            7 ) NodeType="tuic" ;;
            8 ) NodeType="anytls" ;;
            * ) NodeType="shadowsocks" ;;
        esac
    fi
    fastopen=true
    isreality=""
    istls=""
    if [ "$NodeType" == "vless" ]; then
        read -rp "请选择是否为reality节点？(y/n)" isreality
    elif [ "$NodeType" == "hysteria" ] || [ "$NodeType" == "hysteria2" ] || [ "$NodeType" == "tuic" ] || [ "$NodeType" == "anytls" ]; then
        fastopen=false
        istls="y"
    fi

    if [[ "$isreality" != "y" && "$isreality" != "Y" &&  "$istls" != "y" ]]; then
        read -rp "请选择是否进行TLS配置？(y/n)" istls
    fi

    certmode="none"
    certdomain="example.com"
    if [[ "$isreality" != "y" && "$isreality" != "Y" && ( "$istls" == "y" || "$istls" == "Y" ) ]]; then
        echo -e "${yellow}请选择证书申请模式：${plain}"
        echo -e "${green}1. http模式自动申请，节点域名已正确解析${plain}"
        echo -e "${green}2. dns模式自动申请，需填入正确域名服务商API参数${plain}"
        echo -e "${green}3. self模式，自签证书或提供已有证书文件${plain}"
        read -rp "请输入：" certmode
        case "$certmode" in
            1 ) certmode="http" ;;
            2 ) certmode="dns" ;;
            3 ) certmode="self" ;;
        esac
        read -rp "请输入节点证书域名(example.com)：" certdomain
        if [ "$certmode" != "http" ]; then
            echo -e "${red}请手动修改配置文件后重启V2bX！${plain}"
        fi
    fi
    ipv6_support=$(check_ipv6_support)
    listen_ip="0.0.0.0"
    if [ "$ipv6_support" -eq 1 ]; then
        listen_ip="::"
    fi
    node_config=""
    if [ "$core_type" == "1" ]; then 
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "EnableProxyProtocol": false,
            "EnableUot": true,
            "EnableTFO": true,
            "DNSType": "UseIPv4",
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    elif [ "$core_type" == "2" ]; then
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "$listen_ip",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "TCPFastOpen": $fastopen,
            "SniffEnabled": true,
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    elif [ "$core_type" == "3" ]; then
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Hysteria2ConfigPath": "/etc/V2bX/hy2config.yaml",
            "Timeout": 30,
            "ListenIP": "",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    fi
    nodes_config+=("$node_config")
}

generate_config_file() {
    echo -e "${yellow}V2bX 配置文件生成向导${plain}"
    echo -e "${red}请阅读以下注意事项：${plain}"
    echo -e "${red}1. 目前该功能正处测试阶段${plain}"
    echo -e "${red}2. 生成的配置文件会保存到 /etc/V2bX/config.json${plain}"
    echo -e "${red}3. 原来的配置文件会保存到 /etc/V2bX/config.json.bak${plain}"
    echo -e "${red}4. 目前仅部分支持TLS${plain}"
    echo -e "${red}5. 使用此功能生成的配置文件会自带审计，确定继续？(y/n)${plain}"
    read -rp "请输入：" continue_prompt
    if [[ "$continue_prompt" =~ ^[Nn][Oo]? ]]; then
        exit 0
    fi
    
    # 读取现有配置文件中的节点（如果存在）
    existing_nodes=""
    if [ -f "/etc/V2bX/config.json" ]; then
        echo -e "${green}检测到现有配置文件${plain}"
        read -rp "是否保留已有节点配置并追加新节点？(y/n，默认y): " keep_existing
        if [[ "$keep_existing" =~ ^[Nn][Oo]? ]]; then
            echo -e "${yellow}将创建全新配置，不保留已有节点${plain}"
        else
            echo -e "${green}将保留已有节点并追加新节点${plain}"
            # 使用 Python 提取现有节点（Python 通常已安装）
            if command -v python3 &> /dev/null; then
                result=$(python3 << 'PYTHON_SCRIPT'
import json
import sys
try:
    with open('/etc/V2bX/config.json', 'r', encoding='utf-8') as f:
        config = json.load(f)
    nodes = config.get('Nodes', [])
    if not nodes:
        sys.exit(1)
    # 输出节点数量
    print(f"NODE_COUNT:{len(nodes)}")
    # 输出格式化的节点，自动添加逗号（除了最后一个）
    for i, node in enumerate(nodes):
        node_json = json.dumps(node, indent=8, ensure_ascii=False)
        # 给每行添加8空格缩进（因为在Nodes数组内）
        lines = node_json.split('\n')
        indented_lines = ['        ' + line for line in lines]
        output = '\n'.join(indented_lines)
        print(output, end='')
        # 除了最后一个节点，其他都加逗号
        if i < len(nodes) - 1:
            print(',')
        else:
            print()
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)
                exit_code=$?
                if [ $exit_code -eq 0 ] && [ -n "$result" ]; then
                    node_count=$(echo "$result" | head -n 1 | grep "NODE_COUNT:" | cut -d: -f2)
                    existing_nodes=$(echo "$result" | tail -n +2)
                    if [ -n "$existing_nodes" ] && [ -n "$node_count" ]; then
                        echo -e "${green}已读取 $node_count 个现有节点${plain}"
                    else
                        echo -e "${yellow}未找到现有节点，将创建新配置${plain}"
                        existing_nodes=""
                    fi
                else
                    echo -e "${yellow}读取现有节点失败，将创建新配置${plain}"
                    existing_nodes=""
                fi
            elif command -v python &> /dev/null; then
                result=$(python << 'PYTHON_SCRIPT'
import json
import sys
try:
    with open('/etc/V2bX/config.json', 'r', encoding='utf-8') as f:
        config = json.load(f)
    nodes = config.get('Nodes', [])
    if not nodes:
        sys.exit(1)
    print(f"NODE_COUNT:{len(nodes)}")
    for i, node in enumerate(nodes):
        node_json = json.dumps(node, indent=8, ensure_ascii=False)
        lines = node_json.split('\n')
        indented_lines = ['        ' + line for line in lines]
        output = '\n'.join(indented_lines)
        print(output, end='')
        if i < len(nodes) - 1:
            print(',')
        else:
            print()
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)
                exit_code=$?
                if [ $exit_code -eq 0 ] && [ -n "$result" ]; then
                    node_count=$(echo "$result" | head -n 1 | grep "NODE_COUNT:" | cut -d: -f2)
                    existing_nodes=$(echo "$result" | tail -n +2)
                    if [ -n "$existing_nodes" ] && [ -n "$node_count" ]; then
                        echo -e "${green}已读取 $node_count 个现有节点${plain}"
                    else
                        existing_nodes=""
                    fi
                else
                    existing_nodes=""
                fi
            else
                echo -e "${yellow}未找到 Python，无法读取现有节点，将创建新配置${plain}"
                echo -e "${yellow}建议安装 Python 或手动编辑配置文件添加节点${plain}"
            fi
        fi
    fi
    
    nodes_config=()
    first_node=true
    core_xray=false
    core_sing=false
    core_hysteria2=false
    # 如果保留了已有节点，根据已存在节点的 Core 类型预置核心标记，避免覆盖原有 Cores
    if [ -n "$existing_nodes" ]; then
        if grep -q '"Core": "xray"' /etc/V2bX/config.json 2>/dev/null; then
            core_xray=true
        fi
        if grep -q '"Core": "sing"' /etc/V2bX/config.json 2>/dev/null; then
            core_sing=true
        fi
        if grep -q '"Core": "hysteria2"' /etc/V2bX/config.json 2>/dev/null; then
            core_hysteria2=true
        fi
    fi
    fixed_api_info=false
    check_api=false
    
    while true; do
        if [ "$first_node" = true ]; then
            read -rp "请输入机场网址(https://example.com)：" ApiHost
            read -rp "请输入面板对接API Key：" ApiKey
            read -rp "是否设置固定的机场网址和API Key？(y/n)" fixed_api
            if [ "$fixed_api" = "y" ] || [ "$fixed_api" = "Y" ]; then
                fixed_api_info=true
                echo -e "${red}成功固定地址${plain}"
            fi
            first_node=false
            add_node_config
        else
            read -rp "是否继续添加节点配置？(配置了证书的话先等待1-2分钟再继续。回车继续，输入n或no退出)" continue_adding_node
            if [[ "$continue_adding_node" =~ ^[Nn][Oo]? ]]; then
                break
            elif [ "$fixed_api_info" = false ]; then
                read -rp "请输入机场网址：" ApiHost
                read -rp "请输入面板对接API Key：" ApiKey
            fi
            add_node_config
        fi
    done

    # 初始化核心配置数组
    cores_config="["

    # 检查并添加xray核心配置
    if [ "$core_xray" = true ]; then
        cores_config+="
    {
        \"Type\": \"xray\",
        \"Log\": {
            \"Level\": \"error\",
            \"ErrorPath\": \"/etc/V2bX/error.log\"
        },
        \"OutboundConfigPath\": \"/etc/V2bX/custom_outbound.json\",
        \"RouteConfigPath\": \"/etc/V2bX/route.json\"
    },"
    fi

    # 检查并添加sing核心配置
    if [ "$core_sing" = true ]; then
        cores_config+="
    {
        \"Type\": \"sing\",
        \"Log\": {
            \"Level\": \"error\",
            \"Timestamp\": true
        },
        \"NTP\": {
            \"Enable\": false,
            \"Server\": \"time.apple.com\",
            \"ServerPort\": 0
        },
        \"OriginalPath\": \"/etc/V2bX/sing_origin.json\"
    },"
    fi

    # 检查并添加hysteria2核心配置
    if [ "$core_hysteria2" = true ]; then
        cores_config+="
    {
        \"Type\": \"hysteria2\",
        \"Log\": {
            \"Level\": \"error\"
        }
    },"
    fi

    # 移除最后一个逗号并关闭数组
    cores_config+="]"
    # 更精确地移除最后一个核心配置的逗号
    cores_config=$(echo "$cores_config" | sed -E 's/},[[:space:]]*\]$/}]/')

    # 切换到配置文件目录
    cd /etc/V2bX
    
    # 备份旧的配置文件
    if [ -f "config.json" ]; then
        cp config.json config.json.bak.$(date +%Y%m%d_%H%M%S)
    fi
    
    # 拼接新节点配置（每个节点间用逗号+换行分隔）
    formatted_nodes_config=""
    node_count=${#nodes_config[@]}
    for i in "${!nodes_config[@]}"; do
        formatted_nodes_config+="${nodes_config[$i]}"
        # 除了最后一个节点，其他都加逗号
        if [ $i -lt $((node_count - 1)) ]; then
            formatted_nodes_config+=","
        fi
        formatted_nodes_config+=$'\n'
    done
    
    # 合并现有节点和新节点
    all_nodes_config=""
    if [ -n "$existing_nodes" ] && [ -n "$formatted_nodes_config" ]; then
        # 有现有节点 + 有新节点 = 合并（existing_nodes已有逗号）
        all_nodes_config="${existing_nodes},"$'\n'"${formatted_nodes_config}"
    elif [ -n "$existing_nodes" ]; then
        # 只有现有节点（existing_nodes的最后一个节点已经没有逗号）
        all_nodes_config="$existing_nodes"
    elif [ -n "$formatted_nodes_config" ]; then
        # 只有新节点
        all_nodes_config="$formatted_nodes_config"
    fi

    # 创建 config.json 文件
    cat <<EOF > /etc/V2bX/config.json
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": $cores_config,
    "Nodes": [
$all_nodes_config
    ]
}
EOF

    # 验证生成的JSON格式是否正确
    if command -v python3 &> /dev/null; then
        if python3 -m json.tool /etc/V2bX/config.json > /dev/null 2>&1; then
            echo -e "${green}JSON格式验证通过${plain}"
        else
            echo -e "${red}警告：生成的JSON格式可能有问题，请检查配置文件${plain}"
            echo -e "${yellow}正在尝试修复JSON格式...${plain}"
            # 尝试修复常见的JSON格式问题
            python3 << 'PYTHON_FIX'
import json
import re
import sys

try:
    with open('/etc/V2bX/config.json', 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 修复常见的JSON格式问题：移除对象末尾的逗号
    # 匹配 }, 或 } 后面跟逗号的情况（在数组或对象末尾）
    content = re.sub(r'(\})\s*,(\s*[}\]])', r'\1\2', content)
    
    # 尝试解析JSON
    config = json.loads(content)
    
    # 重新格式化并保存
    with open('/etc/V2bX/config.json', 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    
    print("JSON格式已修复")
    sys.exit(0)
except Exception as e:
    print(f"修复失败: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_FIX
            if [ $? -eq 0 ]; then
                echo -e "${green}JSON格式已修复${plain}"
            else
                echo -e "${red}JSON格式修复失败，请手动检查配置文件${plain}"
            fi
        fi
    elif command -v python &> /dev/null; then
        if python -m json.tool /etc/V2bX/config.json > /dev/null 2>&1; then
            echo -e "${green}JSON格式验证通过${plain}"
        else
            echo -e "${red}警告：生成的JSON格式可能有问题，请检查配置文件${plain}"
        fi
    else
        echo -e "${yellow}未找到Python，跳过JSON格式验证${plain}"
    fi
    
    # 创建 custom_outbound.json 文件
    cat <<EOF > /etc/V2bX/custom_outbound.json
    [
        {
            "tag": "IPv4_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4v6"
            }
        },
        {
            "tag": "IPv6_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv6"
            }
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
EOF
    
    # 创建 route.json 文件
    cat <<EOF > /etc/V2bX/route.json
    {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "geoip:private"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "domain": [
                    "regexp:(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
                    "regexp:(.+.|^)(360|so).(cn|com)",
                    "regexp:(Subject|HELO|SMTP)",
                    "regexp:(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
                    "regexp:(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
                    "regexp:(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
                    "regexp:(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
                    "regexp:(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
                    "regexp:(.+.|^)(360).(cn|com|net)",
                    "regexp:(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
                    "regexp:(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
                    "regexp:(.*.||)(netvigator|torproject).(com|cn|net|org)",
                    "regexp:(..||)(visa|mycard|gash|beanfun|bank).",
                    "regexp:(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
                    "regexp:(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
                    "regexp:(.*.||)(mycard).(com|tw)",
                    "regexp:(.*.||)(gash).(com|tw)",
                    "regexp:(.bank.)",
                    "regexp:(.*.||)(pincong).(rocks)",
                    "regexp:(.*.||)(taobao).(com)",
                    "regexp:(.*.||)(laomoe|jiyou|ssss|lolicp|vv1234|0z|4321q|868123|ksweb|mm126).(com|cloud|fun|cn|gs|xyz|cc)",
                    "regexp:(flows|miaoko).(pages).(dev)"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "127.0.0.1/32",
                    "10.0.0.0/8",
                    "fc00::/7",
                    "fe80::/10",
                    "172.16.0.0/12"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "protocol": [
                    "bittorrent"
                ]
            }
        ]
    }
EOF

    ipv6_support=$(check_ipv6_support)
    dnsstrategy="ipv4_only"
    if [ "$ipv6_support" -eq 1 ]; then
        dnsstrategy="prefer_ipv4"
    fi
    # 创建 sing_origin.json 文件
    cat <<EOF > /etc/V2bX/sing_origin.json
{
  "dns": {
    "servers": [
      {
        "tag": "cf",
        "address": "1.1.1.1"
      }
    ],
    "strategy": "$dnsstrategy"
  },
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct",
      "domain_resolver": {
        "server": "cf",
        "strategy": "$dnsstrategy"
      }
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "ip_is_private": true,
        "outbound": "block"
      },
      {
        "domain_regex": [
            "(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
            "(.+.|^)(360|so).(cn|com)",
            "(Subject|HELO|SMTP)",
            "(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
            "(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
            "(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
            "(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
            "(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
            "(.+.|^)(360).(cn|com|net)",
            "(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
            "(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
            "(.*.||)(netvigator|torproject).(com|cn|net|org)",
            "(..||)(visa|mycard|gash|beanfun|bank).",
            "(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
            "(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
            "(.*.||)(mycard).(com|tw)",
            "(.*.||)(gash).(com|tw)",
            "(.bank.)",
            "(.*.||)(pincong).(rocks)",
            "(.*.||)(taobao).(com)",
            "(.*.||)(laomoe|jiyou|ssss|lolicp|vv1234|0z|4321q|868123|ksweb|mm126).(com|cloud|fun|cn|gs|xyz|cc)",
            "(flows|miaoko).(pages).(dev)"
        ],
        "outbound": "block"
      },
      {
        "outbound": "direct",
        "network": [
          "udp","tcp"
        ]
      }
    ]
  },
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
}
EOF

    # 创建 hy2config.yaml 文件           
    cat <<EOF > /etc/V2bX/hy2config.yaml
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false
ignoreClientBandwidth: false
disableUDP: false
udpIdleTimeout: 60s
resolver:
  type: system
acl:
  inline:
    - direct(geosite:google)
    - reject(geosite:cn)
    - reject(geoip:cn)
masquerade:
  type: 404
EOF
    echo -e "${green}V2bX 配置文件生成完成，正在重新启动 V2bX 服务${plain}"
    restart 0
    before_show_menu
}

# 放开防火墙端口
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}放开防火墙端口成功！${plain}"
}

show_usage() {
    echo "V2bX 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "V2bX              - 显示管理菜单 (功能更多)"
    echo "V2bX start        - 启动 V2bX"
    echo "V2bX stop         - 停止 V2bX"
    echo "V2bX restart      - 重启 V2bX"
    echo "V2bX status       - 查看 V2bX 状态"
    echo "V2bX enable       - 设置 V2bX 开机自启"
    echo "V2bX disable      - 取消 V2bX 开机自启"
    echo "V2bX log          - 查看 V2bX 日志"
    echo "V2bX x25519       - 生成 x25519 密钥"
    echo "V2bX generate     - 生成 V2bX 配置文件"
    echo "V2bX editnode     - 修改已存在节点的 NodeID"
    echo "V2bX editnodefull - 修改单个节点的完整配置（整段 JSON）"
    echo "V2bX delnode      - 删除单个节点配置"
    echo "V2bX updateapihost - 批量修改所有节点的机场地址（ApiHost）"
    echo "V2bX update       - 更新 V2bX"
    echo "V2bX update x.x.x - 安装 V2bX 指定版本"
    echo "V2bX install      - 安装 V2bX"
    echo "V2bX uninstall    - 卸载 V2bX"
    echo "V2bX version      - 查看 V2bX 版本"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}V2bX 后端管理脚本，${plain}${red}不适用于docker${plain}
--- https://github.com/JJOGGER/V2bX ---
  ${green}0.${plain} 修改配置
————————————————
  ${green}1.${plain} 安装 V2bX
  ${green}2.${plain} 更新 V2bX
  ${green}3.${plain} 卸载 V2bX
————————————————
  ${green}4.${plain} 启动 V2bX
  ${green}5.${plain} 停止 V2bX
  ${green}6.${plain} 重启 V2bX
  ${green}7.${plain} 查看 V2bX 状态
  ${green}8.${plain} 查看 V2bX 日志
————————————————
  ${green}9.${plain} 设置 V2bX 开机自启
  ${green}10.${plain} 取消 V2bX 开机自启
————————————————
  ${green}11.${plain} 一键安装 bbr (最新内核)
  ${green}12.${plain} 查看 V2bX 版本
  ${green}13.${plain} 生成 X25519 密钥
  ${green}14.${plain} 升级 V2bX 维护脚本
  ${green}15.${plain} 生成 V2bX 配置文件
  ${green}16.${plain} 放行 VPS 的所有网络端口
  ${green}17.${plain} 修改已存在节点的 NodeID
  ${green}18.${plain} 修改单个节点的完整配置
  ${green}19.${plain} 删除单个节点配置
  ${green}20.${plain} 批量修改所有节点的机场地址（ApiHost）
  ${green}21.${plain} 退出脚本
 "
 #后续更新可加入上方字符串中
    show_status
    echo && read -rp "请输入选择 [0-21]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) install_bbr ;;
        12) check_install && show_V2bX_version ;;
        13) check_install && generate_x25519_key ;;
        14) update_shell ;;
        15) generate_config_file ;;
        16) open_ports ;;
        17) check_install && edit_node_id ;;
        18) check_install && edit_node_full ;;
        19) check_install && delete_node ;;
        20) check_install && batch_update_api_host ;;
        21) exit ;;
        *) echo -e "${red}请输入正确的数字 [0-21]${plain}" ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "config") config $* ;;
        "generate") generate_config_file ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "x25519") check_install 0 && generate_x25519_key 0 ;;
        "version") check_install 0 && show_V2bX_version 0 ;;
        "editnode") check_install 0 && edit_node_id ;;
        "editnodefull") check_install 0 && edit_node_full ;;
        "delnode") check_install 0 && delete_node ;;
        "updateapihost") check_install 0 && batch_update_api_host ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "alpine"; then
    release="alpine"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "arch"; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
    if [[ ${os_version} -eq 7 ]]; then
        echo -e "${red}注意： CentOS 7 无法使用hysteria1/2协议！${plain}\n"
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

# 检查系统是否有 IPv6 地址
check_ipv6_support() {
    if ip -6 addr | grep -q "inet6"; then
        echo "1"  # 支持 IPv6
    else
        echo "0"  # 不支持 IPv6
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启V2bX" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/JJOGGER/V2bX-script/master/install.sh)
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/JJOGGER/V2bX-script/master/install.sh) $version
    if [[ $? == 0 ]]; then
        echo -e "${green}更新完成，已自动重启 V2bX，请使用 V2bX log 查看运行日志${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "V2bX在修改配置后会自动尝试重启"
    vi /etc/V2bX/config.json
    sleep 2
    restart
    check_status
    case $? in
        0)
            echo -e "V2bX状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "检测到您未启动V2bX或V2bX自动重启失败，是否查看日志？[Y/n]" && echo
            read -e -rp "(默认: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "V2bX状态: ${red}未安装${plain}"
    esac
}

list_nodes() {
    if [ ! -f "/etc/V2bX/config.json" ]; then
        echo -e "${red}未找到 /etc/V2bX/config.json 配置文件，请先生成或配置节点${plain}"
        return 1
    fi

    if command -v python3 &> /dev/null; then
        python3 << 'PYTHON_LIST_NODES'
import json
import sys

path = "/etc/V2bX/config.json"
try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前配置中未找到任何节点。")
        sys.exit(0)
    print("当前已配置的节点列表：")
    for idx, node in enumerate(nodes):
        core = node.get("Core", "")
        node_type = node.get("NodeType", "")
        node_id = node.get("NodeID", "")
        api_host = node.get("ApiHost", "")
        print(f"[索引 {idx}] Core={core}, NodeType={node_type}, NodeID={node_id}, ApiHost={api_host}")
except Exception as e:
    print(f"读取节点列表失败: {e}")
PYTHON_LIST_NODES
    elif command -v python &> /dev/null; then
        python << 'PYTHON_LIST_NODES'
import json
import sys

path = "/etc/V2bX/config.json"
try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前配置中未找到任何节点。")
        sys.exit(0)
    print("当前已配置的节点列表：")
    for idx, node in enumerate(nodes):
        core = node.get("Core", "")
        node_type = node.get("NodeType", "")
        node_id = node.get("NodeID", "")
        api_host = node.get("ApiHost", "")
        print(f"[索引 {idx}] Core={core}, NodeType={node_type}, NodeID={node_id}, ApiHost={api_host}")
except Exception as e:
    print(f"读取节点列表失败: {e}")
PYTHON_LIST_NODES
    else
        echo -e "${red}未找到 Python，无法列出节点信息，请手动编辑 /etc/V2bX/config.json${plain}"
        return 1
    fi
}

edit_node_id() {
    echo "此功能用于修改已存在节点的 NodeID（面板中的节点编号），不会修改其他配置字段。"
    if [ ! -f "/etc/V2bX/config.json" ]; then
        echo -e "${red}未找到 /etc/V2bX/config.json 配置文件，请先生成或配置节点${plain}"
        return 1
    fi

    list_nodes
    echo ""
    read -rp "请输入要修改的节点索引（上方列表中的索引数字）: " node_index
    if ! [[ "$node_index" =~ ^[0-9]+$ ]]; then
        echo -e "${red}索引必须为非负整数${plain}"
        return 1
    fi

    read -rp "请输入新的 NodeID（面板中的节点ID，必须为正整数）: " new_node_id
    if ! [[ "$new_node_id" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${red}NodeID 必须为正整数${plain}"
        return 1
    fi

    if command -v python3 &> /dev/null; then
        python3 << PYTHON_EDIT_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")
new_id = int("$new_node_id")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    old_id = nodes[idx].get("NodeID")
    nodes[idx]["NodeID"] = new_id
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    print(f"已将索引 {idx} 节点的 NodeID 从 {old_id} 修改为 {new_id}")
except Exception as e:
    print(f"修改节点失败: {e}")
    sys.exit(1)
PYTHON_EDIT_NODE
        result=$?
    elif command -v python &> /dev/null; then
        python << PYTHON_EDIT_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")
new_id = int("$new_node_id")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    old_id = nodes[idx].get("NodeID")
    nodes[idx]["NodeID"] = new_id
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    print(f"已将索引 {idx} 节点的 NodeID 从 {old_id} 修改为 {new_id}")
except Exception as e:
    print(f"修改节点失败: {e}")
    sys.exit(1)
PYTHON_EDIT_NODE
        result=$?
    else
        echo -e "${red}未找到 Python，无法修改节点配置，请手动编辑 /etc/V2bX/config.json${plain}"
        return 1
    fi

    if [ "$result" -eq 0 ]; then
        echo -e "${green}节点 NodeID 修改完成，正在重启 V2bX 使配置生效${plain}"
        restart
    else
        echo -e "${red}节点 NodeID 修改失败，请检查上方错误信息${plain}"
    fi
}

edit_node_full() {
    echo "此功能用于修改单个节点的完整配置，采用交互式方式逐步配置。"
    if [ ! -f "/etc/V2bX/config.json" ]; then
        echo -e "${red}未找到 /etc/V2bX/config.json 配置文件，请先生成或配置节点${plain}"
        return 1
    fi

    list_nodes
    echo ""
    read -rp "请输入要修改的节点索引（上方列表中的索引数字）: " node_index
    if ! [[ "$node_index" =~ ^[0-9]+$ ]]; then
        echo -e "${red}索引必须为非负整数${plain}"
        return 1
    fi

    # 读取当前节点配置
    if command -v python3 &> /dev/null; then
        node_data=$(python3 << PYTHON_READ_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。", file=sys.stderr)
        sys.exit(1)
    node = nodes[idx]
    # 输出为JSON字符串
    print(json.dumps(node, ensure_ascii=False))
    sys.exit(0)
except Exception as e:
    print(f"读取节点失败: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_READ_NODE
)
        read_result=$?
    elif command -v python &> /dev/null; then
        node_data=$(python << PYTHON_READ_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。", file=sys.stderr)
        sys.exit(1)
    node = nodes[idx]
    print(json.dumps(node, ensure_ascii=False))
    sys.exit(0)
except Exception as e:
    print(f"读取节点失败: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_READ_NODE
)
        read_result=$?
    else
        echo -e "${red}未找到 Python，无法读取节点配置${plain}"
        return 1
    fi

    if [ "$read_result" -ne 0 ]; then
        echo -e "${red}读取节点配置失败，请检查上方错误信息${plain}"
        return 1
    fi

    # 解析当前节点配置
    current_core=$(echo "$node_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Core',''))" 2>/dev/null || echo "$node_data" | python -c "import json,sys; d=json.load(sys.stdin); print(d.get('Core',''))" 2>/dev/null)
    current_nodeid=$(echo "$node_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('NodeID',''))" 2>/dev/null || echo "$node_data" | python -c "import json,sys; d=json.load(sys.stdin); print(d.get('NodeID',''))" 2>/dev/null)
    current_apihost=$(echo "$node_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ApiHost',''))" 2>/dev/null || echo "$node_data" | python -c "import json,sys; d=json.load(sys.stdin); print(d.get('ApiHost',''))" 2>/dev/null)
    current_apikey=$(echo "$node_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ApiKey',''))" 2>/dev/null || echo "$node_data" | python -c "import json,sys; d=json.load(sys.stdin); print(d.get('ApiKey',''))" 2>/dev/null)
    current_nodetype=$(echo "$node_data" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('NodeType',''))" 2>/dev/null || echo "$node_data" | python -c "import json,sys; d=json.load(sys.stdin); print(d.get('NodeType',''))" 2>/dev/null)

    echo -e "${green}当前节点配置：${plain}"
    echo -e "  Core: $current_core"
    echo -e "  NodeID: $current_nodeid"
    echo -e "  ApiHost: $current_apihost"
    echo -e "  NodeType: $current_nodetype"
    echo ""

    # 开始交互式配置
    echo -e "${yellow}开始交互式配置节点（直接回车保持当前值）${plain}"
    
    # 选择核心类型
    echo -e "${green}请选择节点核心类型：${plain}"
    echo -e "${green}1. xray${plain}"
    echo -e "${green}2. singbox${plain}"
    echo -e "${green}3. hysteria2${plain}"
    read -rp "请输入 [当前: $current_core]: " core_type
    if [ -z "$core_type" ]; then
        core="$current_core"
    elif [ "$core_type" == "1" ]; then
        core="xray"
        core_xray=true
    elif [ "$core_type" == "2" ]; then
        core="sing"
        core_sing=true
    elif [ "$core_type" == "3" ]; then
        core="hysteria2"
        core_hysteria2=true
    else
        core="$current_core"
    fi

    # NodeID
    read -rp "请输入节点Node ID [当前: $current_nodeid]: " NodeID
    if [ -z "$NodeID" ]; then
        NodeID="$current_nodeid"
    fi
    if ! [[ "$NodeID" =~ ^[0-9]+$ ]]; then
        echo -e "${red}NodeID必须为正整数，使用当前值${plain}"
        NodeID="$current_nodeid"
    fi

    # ApiHost
    backup_domains=$(read_backup_domains 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$backup_domains" ]; then
        echo -e "${green}检测到备用域名列表，可以选择：${plain}"
        echo -e "${green}1. 从备用域名列表中选择${plain}"
        echo -e "${green}2. 手动输入机场网址${plain}"
        echo -e "${green}3. 保持当前值${plain}"
        read -rp "请选择 (1/2/3，默认3): " select_method
        if [ "$select_method" = "1" ]; then
            echo -e "${yellow}备用域名列表：${plain}"
            domain_index=1
            domain_array=()
            while IFS= read -r domain; do
                if [ -n "$domain" ]; then
                    echo -e "${green}  ${domain_index}. ${domain}${plain}"
                    domain_array+=("$domain")
                    ((domain_index++))
                fi
            done <<< "$backup_domains"
            read -rp "请选择备用域名编号: " selected_index
            if [[ "$selected_index" =~ ^[0-9]+$ ]] && [ "$selected_index" -ge 1 ] && [ "$selected_index" -le "${#domain_array[@]}" ]; then
                ApiHost="${domain_array[$((selected_index-1))]}"
            else
                ApiHost="$current_apihost"
            fi
        elif [ "$select_method" = "2" ]; then
            read -rp "请输入机场网址 [当前: $current_apihost]: " ApiHost
            if [ -z "$ApiHost" ]; then
                ApiHost="$current_apihost"
            fi
        else
            ApiHost="$current_apihost"
        fi
    else
        read -rp "请输入机场网址 [当前: $current_apihost]: " ApiHost
        if [ -z "$ApiHost" ]; then
            ApiHost="$current_apihost"
        fi
    fi

    # ApiKey
    read -rp "请输入面板对接API Key [当前: ${current_apikey:0:10}...]: " ApiKey
    if [ -z "$ApiKey" ]; then
        ApiKey="$current_apikey"
    fi

    # 测试API地址是否可用，如果不可用则尝试备用域名
    echo -e "${yellow}正在测试API地址可用性...${plain}"
    available_host=$(find_available_api_host "$ApiHost" "$ApiKey" "$NodeID" "$current_nodetype")
    test_result=$?
    if [ $test_result -eq 0 ] && [ -n "$available_host" ]; then
        if [ "$available_host" != "$ApiHost" ]; then
            echo -e "${yellow}原API地址不可用，已自动切换到: $available_host${plain}"
            ApiHost="$available_host"
        else
            echo -e "${green}API地址可用${plain}"
        fi
    else
        echo -e "${yellow}无法测试API地址，将使用输入的地址${plain}"
    fi

    # 初始化核心类型标记
    core_xray=false
    core_sing=false
    core_hysteria2=false
    if [ "$core" == "xray" ]; then
        core_xray=true
    elif [ "$core" == "sing" ]; then
        core_sing=true
    elif [ "$core" == "hysteria2" ]; then
        core_hysteria2=true
    fi

    # NodeType
    if [ "$core" == "hysteria2" ] && [ "$core_xray" != "true" ] && [ "$core_sing" != "true" ]; then
        NodeType="hysteria2"
    else
        echo -e "${yellow}请选择节点传输协议：${plain}"
        echo -e "${green}1. Shadowsocks${plain}"
        echo -e "${green}2. Vless${plain}"
        echo -e "${green}3. Vmess${plain}"
        if [ "$core_sing" == "true" ]; then
            echo -e "${green}4. Hysteria${plain}"
            echo -e "${green}5. Hysteria2${plain}"
        fi
        if [ "$core" == "hysteria2" ] && [ "$core_sing" != "true" ]; then
            echo -e "${green}5. Hysteria2${plain}"
        fi
        echo -e "${green}6. Trojan${plain}"
        if [ "$core_sing" == "true" ]; then
            echo -e "${green}7. Tuic${plain}"
            echo -e "${green}8. AnyTLS${plain}"
        fi
        read -rp "请输入 [当前: $current_nodetype]: " NodeType_input
        if [ -z "$NodeType_input" ]; then
            NodeType="$current_nodetype"
        else
            case "$NodeType_input" in
                1 ) NodeType="shadowsocks" ;;
                2 ) NodeType="vless" ;;
                3 ) NodeType="vmess" ;;
                4 ) NodeType="hysteria" ;;
                5 ) NodeType="hysteria2" ;;
                6 ) NodeType="trojan" ;;
                7 ) NodeType="tuic" ;;
                8 ) NodeType="anytls" ;;
                * ) NodeType="$current_nodetype" ;;
            esac
        fi
    fi

    # TLS配置（简化处理，保持原有逻辑）
    fastopen=true
    isreality=""
    istls=""
    if [ "$NodeType" == "vless" ]; then
        read -rp "请选择是否为reality节点？(y/n): " isreality
    elif [ "$NodeType" == "hysteria" ] || [ "$NodeType" == "hysteria2" ] || [ "$NodeType" == "tuic" ] || [ "$NodeType" == "anytls" ]; then
        fastopen=false
        istls="y"
    fi

    if [[ "$isreality" != "y" && "$isreality" != "Y" && "$istls" != "y" ]]; then
        read -rp "请选择是否进行TLS配置？(y/n): " istls
    fi

    certmode="none"
    certdomain="example.com"
    if [[ "$isreality" != "y" && "$isreality" != "Y" && ( "$istls" == "y" || "$istls" == "Y" ) ]]; then
        echo -e "${yellow}请选择证书申请模式：${plain}"
        echo -e "${green}1. http模式自动申请，节点域名已正确解析${plain}"
        echo -e "${green}2. dns模式自动申请，需填入正确域名服务商API参数${plain}"
        echo -e "${green}3. self模式，自签证书或提供已有证书文件${plain}"
        read -rp "请输入: " certmode_input
        case "$certmode_input" in
            1 ) certmode="http" ;;
            2 ) certmode="dns" ;;
            3 ) certmode="self" ;;
        esac
        read -rp "请输入节点证书域名(example.com): " certdomain
        if [ -z "$certdomain" ]; then
            certdomain="example.com"
        fi
    fi

    # 生成节点配置（复用add_node_config的逻辑）
    ipv6_support=$(check_ipv6_support)
    listen_ip="0.0.0.0"
    if [ "$ipv6_support" -eq 1 ]; then
        listen_ip="::"
    fi

    # 构建新的节点配置
    if [ "$core" == "xray" ]; then
        new_node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "EnableProxyProtocol": false,
            "EnableUot": true,
            "EnableTFO": true,
            "DNSType": "UseIPv4",
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    elif [ "$core" == "sing" ]; then
        new_node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "$listen_ip",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "TCPFastOpen": $fastopen,
            "SniffEnabled": true,
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    elif [ "$core" == "hysteria2" ]; then
        new_node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Hysteria2ConfigPath": "/etc/V2bX/hy2config.yaml",
            "Timeout": 30,
            "ListenIP": "",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    fi

    # 将新配置写回配置文件
    if command -v python3 &> /dev/null; then
        python3 << PYTHON_UPDATE_NODE
import json
import sys

cfg_path = "/etc/V2bX/config.json"
idx = int("$node_index")
new_node_json = """$new_node_config"""

try:
    new_node = json.loads(new_node_json)
    
    with open(cfg_path, "r", encoding="utf-8") as f:
        config = json.load(f)
    
    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    
    nodes[idx] = new_node
    
    with open(cfg_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    
    print(f"已成功更新索引 {idx} 的节点配置")
    sys.exit(0)
except Exception as e:
    print(f"更新节点配置失败: {e}")
    sys.exit(1)
PYTHON_UPDATE_NODE
        update_result=$?
    elif command -v python &> /dev/null; then
        python << PYTHON_UPDATE_NODE
import json
import sys

cfg_path = "/etc/V2bX/config.json"
idx = int("$node_index")
new_node_json = """$new_node_config"""

try:
    new_node = json.loads(new_node_json)
    
    with open(cfg_path, "r", encoding="utf-8") as f:
        config = json.load(f)
    
    nodes = config.get("Nodes", [])
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    
    nodes[idx] = new_node
    
    with open(cfg_path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    
    print(f"已成功更新索引 {idx} 的节点配置")
    sys.exit(0)
except Exception as e:
    print(f"更新节点配置失败: {e}")
    sys.exit(1)
PYTHON_UPDATE_NODE
        update_result=$?
    else
        echo -e "${red}未找到 Python，无法更新节点配置${plain}"
        return 1
    fi

    if [ "$update_result" -eq 0 ]; then
        echo -e "${green}节点配置修改完成，正在重启 V2bX 使配置生效${plain}"
        restart
    else
        echo -e "${red}节点配置修改失败，请检查上方错误信息${plain}"
    fi
}

delete_node() {
    echo "此功能用于删除单个节点配置（从 Nodes 数组中移除）。"
    if [ ! -f "/etc/V2bX/config.json" ]; then
        echo -e "${red}未找到 /etc/V2bX/config.json 配置文件，请先生成或配置节点${plain}"
        return 1
    fi

    list_nodes
    echo ""
    read -rp "请输入要删除的节点索引（上方列表中的索引数字）: " node_index
    if ! [[ "$node_index" =~ ^[0-9]+$ ]]; then
        echo -e "${red}索引必须为非负整数${plain}"
        return 1
    fi

    read -rp "确定要删除该节点配置吗？(y/n): " confirm_del
    if [[ "$confirm_del" != "y" && "$confirm_del" != "Y" ]]; then
        echo "已取消删除操作。"
        return 0
    fi

    if command -v python3 &> /dev/null; then
        python3 << PYTHON_DELETE_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前没有可删除的节点。")
        sys.exit(1)
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    removed = nodes.pop(idx)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    print(f"已删除索引 {idx} 的节点（NodeID={removed.get('NodeID')}, Core={removed.get('Core')}, NodeType={removed.get('NodeType')})")
except Exception as e:
    print(f"删除节点失败: {e}")
    sys.exit(1)
PYTHON_DELETE_NODE
        del_result=$?
    elif command -v python &> /dev/null; then
        python << PYTHON_DELETE_NODE
import json
import sys

path = "/etc/V2bX/config.json"
idx = int("$node_index")

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前没有可删除的节点。")
        sys.exit(1)
    if idx < 0 or idx >= len(nodes):
        print("节点索引超出范围，请检查后重试。")
        sys.exit(1)
    removed = nodes.pop(idx)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    print(f"已删除索引 {idx} 的节点（NodeID={removed.get('NodeID')}, Core={removed.get('Core')}, NodeType={removed.get('NodeType')})")
except Exception as e:
    print(f"删除节点失败: {e}")
    sys.exit(1)
PYTHON_DELETE_NODE
        del_result=$?
    else
        echo -e "${red}未找到 Python，无法删除节点配置，请手动编辑 /etc/V2bX/config.json${plain}"
        return 1
    fi

    if [ "$del_result" -eq 0 ]; then
        echo -e "${green}节点已删除，正在重启 V2bX 使配置生效${plain}"
        restart
    else
        echo -e "${red}节点删除失败，请检查上方错误信息${plain}"
    fi
}

# 备用域名列表文件路径
BACKUP_DOMAINS_FILE="/etc/V2bX/backup_domains.json"
FIXED_API_FILE="/etc/V2bX/fixed_api.json"

# 更新备用域名列表
update_backup_domains() {
    echo "此功能用于更新备用域名列表，当主域名不可用时可以自动切换到备用域名。"
    echo -e "${yellow}提示：请输入备用域名请求地址，格式：http(s)://example.com/api/api.json${plain}"
    read -rp "请输入备用域名请求地址: " backup_url
    
    if [ -z "$backup_url" ]; then
        echo -e "${red}备用域名请求地址不能为空${plain}"
        return 1
    fi
    
    # 验证URL格式
    if [[ ! "$backup_url" =~ ^https?:// ]]; then
        echo -e "${red}URL格式错误，必须以 http:// 或 https:// 开头${plain}"
        return 1
    fi
    
    echo -e "${yellow}正在请求备用域名列表...${plain}"
    
    # 使用curl或wget获取数据
    if command -v curl &> /dev/null; then
        response=$(curl -s -m 10 "$backup_url" 2>&1)
        curl_result=$?
    elif command -v wget &> /dev/null; then
        response=$(wget -qO- -T 10 "$backup_url" 2>&1)
        curl_result=$?
    else
        echo -e "${red}未找到 curl 或 wget，无法请求备用域名列表${plain}"
        return 1
    fi
    
    if [ $curl_result -ne 0 ] || [ -z "$response" ]; then
        echo -e "${red}请求备用域名列表失败，请检查URL是否正确或网络是否正常${plain}"
        return 1
    fi
    
    # 使用Python解析JSON
    if command -v python3 &> /dev/null; then
        result=$(python3 << PYTHON_PARSE_DOMAINS
import json
import sys

response = """$response"""

try:
    data = json.loads(response)
    domain_list = data.get("domain", [])
    if isinstance(domain_list, str):
        # 如果domain是字符串，按逗号分割
        domain_list = [d.strip() for d in domain_list.split(",") if d.strip()]
    elif not isinstance(domain_list, list):
        print("错误：domain字段格式不正确", file=sys.stderr)
        sys.exit(1)
    
    # 保存到文件
    output = {
        "update_url": "$backup_url",
        "domains": domain_list,
        "update_time": __import__("datetime").datetime.now().isoformat()
    }
    
    with open("$BACKUP_DOMAINS_FILE", "w", encoding="utf-8") as f:
        json.dump(output, f, indent=4, ensure_ascii=False)
    
    print(f"成功获取 {len(domain_list)} 个备用域名：")
    for i, domain in enumerate(domain_list, 1):
        print(f"  {i}. {domain}")
    sys.exit(0)
except json.JSONDecodeError as e:
    print(f"JSON解析失败: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"处理失败: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_PARSE_DOMAINS
)
        parse_result=$?
    elif command -v python &> /dev/null; then
        result=$(python << PYTHON_PARSE_DOMAINS
import json
import sys

response = """$response"""

try:
    data = json.loads(response)
    domain_list = data.get("domain", [])
    if isinstance(domain_list, str):
        domain_list = [d.strip() for d in domain_list.split(",") if d.strip()]
    elif not isinstance(domain_list, list):
        print("错误：domain字段格式不正确", file=sys.stderr)
        sys.exit(1)
    
    output = {
        "update_url": "$backup_url",
        "domains": domain_list,
        "update_time": __import__("datetime").datetime.now().isoformat()
    }
    
    with open("$BACKUP_DOMAINS_FILE", "w", encoding="utf-8") as f:
        json.dump(output, f, indent=4, ensure_ascii=False)
    
    print(f"成功获取 {len(domain_list)} 个备用域名：")
    for i, domain in enumerate(domain_list, 1):
        print(f"  {i}. {domain}")
    sys.exit(0)
except ValueError as e:
    print(f"JSON解析失败: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"处理失败: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_PARSE_DOMAINS
)
        parse_result=$?
    else
        echo -e "${red}未找到 Python，无法解析备用域名列表${plain}"
        return 1
    fi
    
    if [ $parse_result -eq 0 ]; then
        echo "$result"
        echo -e "${green}备用域名列表已保存到 $BACKUP_DOMAINS_FILE${plain}"
    else
        echo -e "${red}解析备用域名列表失败，请检查响应格式是否正确${plain}"
        return 1
    fi
    
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

# 读取备用域名列表
read_backup_domains() {
    if [ ! -f "$BACKUP_DOMAINS_FILE" ]; then
        return 1
    fi
    
    if command -v python3 &> /dev/null; then
        python3 << PYTHON_READ_DOMAINS
import json
import sys

try:
    with open("$BACKUP_DOMAINS_FILE", "r", encoding="utf-8") as f:
        data = json.load(f)
    domains = data.get("domains", [])
    
    # 如果domains是字符串，按逗号分割
    if isinstance(domains, str):
        domains = [d.strip() for d in domains.split(",") if d.strip()]
    # 如果domains是列表，确保每个元素都是字符串
    elif isinstance(domains, list):
        processed_domains = []
        for domain in domains:
            if isinstance(domain, str):
                # 如果域名中包含逗号，需要进一步分割
                if "," in domain:
                    processed_domains.extend([d.strip() for d in domain.split(",") if d.strip()])
                else:
                    processed_domains.append(domain.strip())
        domains = processed_domains
    else:
        sys.exit(1)
    
    # 过滤空字符串并去重
    domains = list(dict.fromkeys([d for d in domains if d]))
    
    # 每个域名单独一行输出
    for domain in domains:
        print(domain)
    sys.exit(0)
except Exception as e:
    sys.exit(1)
PYTHON_READ_DOMAINS
    elif command -v python &> /dev/null; then
        python << PYTHON_READ_DOMAINS
import json
import sys

try:
    with open("$BACKUP_DOMAINS_FILE", "r", encoding="utf-8") as f:
        data = json.load(f)
    domains = data.get("domains", [])
    
    # 如果domains是字符串，按逗号分割
    if isinstance(domains, str):
        domains = [d.strip() for d in domains.split(",") if d.strip()]
    # 如果domains是列表，确保每个元素都是字符串
    elif isinstance(domains, list):
        processed_domains = []
        for domain in domains:
            if isinstance(domain, str):
                # 如果域名中包含逗号，需要进一步分割
                if "," in domain:
                    processed_domains.extend([d.strip() for d in domain.split(",") if d.strip()])
                else:
                    processed_domains.append(domain.strip())
        domains = processed_domains
    else:
        sys.exit(1)
    
    # 过滤空字符串并去重
    domains = list(dict.fromkeys([d for d in domains if d]))
    
    # 每个域名单独一行输出
    for domain in domains:
        print(domain)
    sys.exit(0)
except Exception as e:
    sys.exit(1)
PYTHON_READ_DOMAINS
    else
        return 1
    fi
}

# 测试API地址是否可用
test_api_host() {
    local api_host=$1
    local api_key=$2
    local node_id=$3
    local node_type=$4
    
    if [ -z "$api_host" ] || [ -z "$api_key" ] || [ -z "$node_id" ] || [ -z "$node_type" ]; then
        return 1
    fi
    
    # 构建测试URL
    local test_url="${api_host}/api/v1/server/UniProxy/config?node_type=${node_type}&node_id=${node_id}&token=${api_key}"
    
    # 使用curl测试
    if command -v curl &> /dev/null; then
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 --connect-timeout 5 "$test_url" 2>/dev/null)
        if [ -n "$http_code" ] && ([ "$http_code" = "200" ] || [ "$http_code" = "304" ] || [ "$http_code" = "401" ] || [ "$http_code" = "403" ]); then
            # 200/304表示成功，401/403表示API地址可达但认证失败（也算地址可用）
            return 0
        fi
    elif command -v wget &> /dev/null; then
        http_code=$(wget --spider -S --timeout=10 "$test_url" 2>&1 | grep -E "HTTP/" | tail -1 | awk '{print $2}')
        if [ -n "$http_code" ] && ([ "$http_code" = "200" ] || [ "$http_code" = "304" ] || [ "$http_code" = "401" ] || [ "$http_code" = "403" ]); then
            return 0
        fi
    else
        # 如果没有curl或wget，无法测试，返回1
        return 1
    fi
    
    return 1
}

# 从备用域名列表中找到可用的API地址
find_available_api_host() {
    local current_api_host=$1
    local api_key=$2
    local node_id=$3
    local node_type=$4
    
    # 先测试当前地址
    if test_api_host "$current_api_host" "$api_key" "$node_id" "$node_type"; then
        echo "$current_api_host"
        return 0
    fi
    
    # 从备用域名列表中查找
    local backup_domains=$(read_backup_domains)
    if [ -z "$backup_domains" ]; then
        return 1
    fi
    
    echo -e "${yellow}当前API地址不可用，正在从备用域名列表中查找可用地址...${plain}" >&2
    
    while IFS= read -r domain; do
        if [ -n "$domain" ]; then
            echo -e "${yellow}正在测试: $domain${plain}" >&2
            if test_api_host "$domain" "$api_key" "$node_id" "$node_type"; then
                echo "$domain"
                return 0
            fi
        fi
    done <<< "$backup_domains"
    
    return 1
}

# 保存固定的API信息
save_fixed_api() {
    local api_host=$1
    local api_key=$2
    
    if command -v python3 &> /dev/null; then
        python3 << PYTHON_SAVE_FIXED_API
import json
import sys

api_host = "$api_host"
api_key = "$api_key"

try:
    data = {
        "ApiHost": api_host,
        "ApiKey": api_key,
        "saved_time": __import__("datetime").datetime.now().isoformat()
    }
    with open("$FIXED_API_FILE", "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)
    sys.exit(0)
except Exception as e:
    print(f"保存失败: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SAVE_FIXED_API
    elif command -v python &> /dev/null; then
        python << PYTHON_SAVE_FIXED_API
import json
import sys

api_host = "$api_host"
api_key = "$api_key"

try:
    data = {
        "ApiHost": api_host,
        "ApiKey": api_key,
        "saved_time": __import__("datetime").datetime.now().isoformat()
    }
    with open("$FIXED_API_FILE", "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4, ensure_ascii=False)
    sys.exit(0)
except Exception as e:
    print(f"保存失败: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SAVE_FIXED_API
    fi
}

# 读取固定的API信息
read_fixed_api() {
    if [ ! -f "$FIXED_API_FILE" ]; then
        return 1
    fi
    
    if command -v python3 &> /dev/null; then
        python3 << PYTHON_READ_FIXED_API
import json
import sys

try:
    with open("$FIXED_API_FILE", "r", encoding="utf-8") as f:
        data = json.load(f)
    print(data.get("ApiHost", ""))
    print(data.get("ApiKey", ""))
    sys.exit(0)
except Exception as e:
    sys.exit(1)
PYTHON_READ_FIXED_API
    elif command -v python &> /dev/null; then
        python << PYTHON_READ_FIXED_API
import json
import sys

try:
    with open("$FIXED_API_FILE", "r", encoding="utf-8") as f:
        data = json.load(f)
    print(data.get("ApiHost", ""))
    print(data.get("ApiKey", ""))
    sys.exit(0)
except Exception as e:
    sys.exit(1)
PYTHON_READ_FIXED_API
    else
        return 1
    fi
}

batch_update_api_host() {
    echo "此功能用于批量修改所有节点的机场地址（ApiHost），适用于机场域名被墙的情况。"
    echo -e "${yellow}注意：此操作会修改所有节点的 ApiHost，但不会修改其他配置（如 NodeID、协议类型等）${plain}"
    if [ ! -f "/etc/V2bX/config.json" ]; then
        echo -e "${red}未找到 /etc/V2bX/config.json 配置文件，请先生成或配置节点${plain}"
        return 1
    fi

    list_nodes
    echo ""
    
    # 检查是否有备用域名列表
    backup_domains=$(read_backup_domains 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$backup_domains" ]; then
        echo -e "${green}检测到备用域名列表，可以选择：${plain}"
        echo -e "${green}1. 从备用域名列表中选择${plain}"
        echo -e "${green}2. 手动输入机场网址${plain}"
        read -rp "请选择 (1/2，默认2): " select_method
        if [ "$select_method" = "1" ]; then
            echo -e "${yellow}备用域名列表：${plain}"
            domain_index=1
            domain_array=()
            while IFS= read -r domain; do
                if [ -n "$domain" ]; then
                    echo -e "${green}  ${domain_index}. ${domain}${plain}"
                    domain_array+=("$domain")
                    ((domain_index++))
                fi
            done <<< "$backup_domains"
            read -rp "请选择备用域名编号: " selected_index
            if [[ "$selected_index" =~ ^[0-9]+$ ]] && [ "$selected_index" -ge 1 ] && [ "$selected_index" -le "${#domain_array[@]}" ]; then
                new_api_host="${domain_array[$((selected_index-1))]}"
                echo -e "${green}已选择: $new_api_host${plain}"
            else
                echo -e "${red}无效的选择，将使用手动输入${plain}"
                read -rp "请输入新的机场地址（ApiHost，例如：https://new-domain.com）: " new_api_host
            fi
        else
            read -rp "请输入新的机场地址（ApiHost，例如：https://new-domain.com）: " new_api_host
        fi
    else
        read -rp "请输入新的机场地址（ApiHost，例如：https://new-domain.com）: " new_api_host
    fi
    
    if [ -z "$new_api_host" ]; then
        echo -e "${red}机场地址不能为空${plain}"
        return 1
    fi

    read -rp "确定要将所有节点的 ApiHost 修改为 '$new_api_host' 吗？(y/n): " confirm_update
    if [[ "$confirm_update" != "y" && "$confirm_update" != "Y" ]]; then
        echo "已取消修改操作。"
        return 0
    fi

    if command -v python3 &> /dev/null; then
        python3 << PYTHON_BATCH_UPDATE
import json
import sys

path = "/etc/V2bX/config.json"
new_host = "$new_api_host"

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前配置中未找到任何节点。")
        sys.exit(1)
    
    updated_count = 0
    for idx, node in enumerate(nodes):
        old_host = node.get("ApiHost", "")
        if old_host != new_host:
            node["ApiHost"] = new_host
            updated_count += 1
            print(f"节点 [索引 {idx}] (NodeID={node.get('NodeID')}): {old_host} -> {new_host}")
    
    if updated_count == 0:
        print("所有节点的 ApiHost 已经是 '$new_host'，无需修改。")
    else:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=4, ensure_ascii=False)
        print(f"\n已成功更新 {updated_count} 个节点的 ApiHost")
except Exception as e:
    print(f"批量更新失败: {e}")
    sys.exit(1)
PYTHON_BATCH_UPDATE
        update_result=$?
    elif command -v python &> /dev/null; then
        python << PYTHON_BATCH_UPDATE
import json
import sys

path = "/etc/V2bX/config.json"
new_host = "$new_api_host"

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前配置中未找到任何节点。")
        sys.exit(1)
    
    updated_count = 0
    for idx, node in enumerate(nodes):
        old_host = node.get("ApiHost", "")
        if old_host != new_host:
            node["ApiHost"] = new_host
            updated_count += 1
            print(f"节点 [索引 {idx}] (NodeID={node.get('NodeID')}): {old_host} -> {new_host}")
    
    if updated_count == 0:
        print("所有节点的 ApiHost 已经是 '$new_host'，无需修改。")
    else:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=4, ensure_ascii=False)
        print(f"\n已成功更新 {updated_count} 个节点的 ApiHost")
except Exception as e:
    print(f"批量更新失败: {e}")
    sys.exit(1)
PYTHON_BATCH_UPDATE
        update_result=$?
    else
        echo -e "${red}未找到 Python，无法批量更新节点配置，请手动编辑 /etc/V2bX/config.json${plain}"
        return 1
    fi

    if [ "$update_result" -eq 0 ]; then
        echo -e "${green}批量更新完成，正在重启 V2bX 使配置生效${plain}"
        restart
    else
        echo -e "${red}批量更新失败，请检查上方错误信息${plain}"
    fi
}

# 检查API请求频率和优化建议
check_api_frequency() {
    echo "此功能用于检查节点API请求频率，并提供优化建议。"
    if [ ! -f "/etc/V2bX/config.json" ]; then
        echo -e "${red}未找到 /etc/V2bX/config.json 配置文件，请先生成或配置节点${plain}"
        return 1
    fi

    list_nodes
    echo ""
    read -rp "请输入要检查的节点索引（上方列表中的索引数字，留空检查所有节点）: " node_index
    
    if command -v python3 &> /dev/null; then
        python3 << PYTHON_CHECK_API
import json
import sys
import subprocess
import re
from datetime import datetime, timedelta

path = "/etc/V2bX/config.json"

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前配置中未找到任何节点。")
        sys.exit(1)
    
    # 如果指定了节点索引，只检查该节点
    if "$node_index" and "$node_index".strip():
        idx = int("$node_index")
        if idx < 0 or idx >= len(nodes):
            print("节点索引超出范围，请检查后重试。")
            sys.exit(1)
        nodes = [nodes[idx]]
        print(f"检查节点 [索引 {idx}]:")
    else:
        print("检查所有节点:")
    
    print("=" * 80)
    
    # 检查V2bX日志中的API请求频率
    log_file = "/var/log/V2bX.log"
    if not __import__("os").path.exists(log_file):
        # 尝试从journalctl获取日志
        try:
            result = subprocess.run(
                ["journalctl", "-u", "V2bX.service", "--no-pager", "-n", "1000"],
                capture_output=True,
                text=True,
                timeout=5
            )
            log_content = result.stdout
        except:
            log_content = ""
    else:
        try:
            with open(log_file, "r", encoding="utf-8") as f:
                log_content = f.read()
        except:
            log_content = ""
    
    for idx, node in enumerate(nodes):
        node_id = node.get("NodeID", "")
        api_host = node.get("ApiHost", "")
        node_type = node.get("NodeType", "")
        
        print(f"\n节点 [索引 {idx if not '$node_index' or not '$node_index'.strip() else 0}] (NodeID={node_id}, NodeType={node_type}):")
        print(f"  API地址: {api_host}")
        
        # 统计日志中的请求次数（最近1小时）
        if log_content:
            # 查找包含该API地址的日志行
            api_pattern = re.escape(api_host)
            relevant_lines = [line for line in log_content.split("\n") if api_pattern in line]
            
            # 统计错误次数
            error_count = len([line for line in relevant_lines if "error" in line.lower() or "failed" in line.lower()])
            request_count = len([line for line in relevant_lines if "config" in line.lower() or "user" in line.lower()])
            
            if request_count > 0:
                print(f"  最近日志中的请求次数: {request_count}")
                if error_count > 0:
                    print(f"  ${chr(27)}[33m错误次数: {error_count}${chr(27)}[0m")
        
        # 检查配置中的超时设置
        timeout = node.get("Timeout", 30)
        print(f"  超时设置: {timeout}秒")
        
        # 提供优化建议
        suggestions = []
        
        # 检查是否有备用域名
        backup_file = "/etc/V2bX/backup_domains.json"
        try:
            with open(backup_file, "r", encoding="utf-8") as f:
                backup_data = json.load(f)
            backup_domains = backup_data.get("domains", [])
            if backup_domains:
                print(f"  ${chr(27)}[32m✓ 已配置备用域名列表 (共{len(backup_domains)}个)${chr(27)}[0m")
            else:
                suggestions.append("建议配置备用域名列表，以便在主域名不可用时自动切换")
        except:
            suggestions.append("建议配置备用域名列表，以便在主域名不可用时自动切换")
        
        # 超时设置建议
        if timeout < 10:
            suggestions.append("超时设置过短，可能导致请求频繁失败，建议设置为30秒以上")
        elif timeout > 60:
            suggestions.append("超时设置过长，可能导致响应缓慢，建议设置为30-60秒")
        
        # API地址可用性测试
        print(f"  正在测试API地址可用性...", end="", flush=True)
        import urllib.request
        import urllib.error
        test_url = f"{api_host}/api/v1/server/UniProxy/config?node_type={node_type}&node_id={node_id}&token=test"
        try:
            req = urllib.request.Request(test_url)
            req.add_header("User-Agent", "V2bX-Check")
            with urllib.request.urlopen(req, timeout=5) as response:
                status = response.getcode()
                if status == 200 or status == 304:
                    print(f" ${chr(27)}[32m✓ 可用${chr(27)}[0m")
                else:
                    print(f" ${chr(27)}[33m⚠ 状态码: {status}${chr(27)}[0m")
                    suggestions.append("API地址返回异常状态码，建议检查配置或使用备用域名")
        except urllib.error.URLError as e:
            print(f" ${chr(27)}[31m✗ 不可用: {str(e)[:50]}${chr(27)}[0m")
            suggestions.append("API地址不可用，建议使用备用域名或检查网络连接")
        except Exception as e:
            print(f" ${chr(27)}[33m⚠ 测试失败: {str(e)[:50]}${chr(27)}[0m")
        
        # 输出优化建议
        if suggestions:
            print(f"  ${chr(27)}[33m优化建议:${chr(27)}[0m")
            for i, suggestion in enumerate(suggestions, 1):
                print(f"    {i}. {suggestion}")
        else:
            print(f"  ${chr(27)}[32m✓ 配置正常，无需优化${chr(27)}[0m")
    
    print("\n" + "=" * 80)
    print("说明:")
    print("  - API请求频率由面板的PullInterval和PushInterval控制")
    print("  - 正常情况下，PullInterval（拉取配置）建议设置为60-300秒")
    print("  - PushInterval（上报流量）建议设置为60-300秒")
    print("  - 如果请求频率过高，可能增加服务器负担")
    print("  - 如果请求频率过低，可能导致配置更新不及时")
    
    sys.exit(0)
except Exception as e:
    print(f"检查失败: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_CHECK_API
        check_result=$?
    elif command -v python &> /dev/null; then
        python << PYTHON_CHECK_API
import json
import sys
import subprocess
import re

path = "/etc/V2bX/config.json"

try:
    with open(path, "r", encoding="utf-8") as f:
        config = json.load(f)
    nodes = config.get("Nodes", [])
    if not nodes:
        print("当前配置中未找到任何节点。")
        sys.exit(1)
    
    if "$node_index" and "$node_index".strip():
        idx = int("$node_index")
        if idx < 0 or idx >= len(nodes):
            print("节点索引超出范围，请检查后重试。")
            sys.exit(1)
        nodes = [nodes[idx]]
        print(f"检查节点 [索引 {idx}]:")
    else:
        print("检查所有节点:")
    
    print("=" * 80)
    
    for idx, node in enumerate(nodes):
        node_id = node.get("NodeID", "")
        api_host = node.get("ApiHost", "")
        node_type = node.get("NodeType", "")
        timeout = node.get("Timeout", 30)
        
        print(f"\n节点 [索引 {idx if not '$node_index' or not '$node_index'.strip() else 0}] (NodeID={node_id}, NodeType={node_type}):")
        print(f"  API地址: {api_host}")
        print(f"  超时设置: {timeout}秒")
        
        suggestions = []
        
        backup_file = "/etc/V2bX/backup_domains.json"
        try:
            with open(backup_file, "r", encoding="utf-8") as f:
                backup_data = json.load(f)
            backup_domains = backup_data.get("domains", [])
            if backup_domains:
                print(f"  ✓ 已配置备用域名列表 (共{len(backup_domains)}个)")
            else:
                suggestions.append("建议配置备用域名列表")
        except:
            suggestions.append("建议配置备用域名列表")
        
        if timeout < 10:
            suggestions.append("超时设置过短，建议设置为30秒以上")
        elif timeout > 60:
            suggestions.append("超时设置过长，建议设置为30-60秒")
        
        if suggestions:
            print(f"  优化建议:")
            for i, suggestion in enumerate(suggestions, 1):
                print(f"    {i}. {suggestion}")
        else:
            print(f"  ✓ 配置正常")
    
    print("\n" + "=" * 80)
    sys.exit(0)
except Exception as e:
    print(f"检查失败: {e}")
    sys.exit(1)
PYTHON_CHECK_API
        check_result=$?
    else
        echo -e "${red}未找到 Python，无法检查API请求频率${plain}"
        return 1
    fi

    if [ "$check_result" -eq 0 ]; then
        echo ""
    else
        echo -e "${red}检查失败，请检查上方错误信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall() {
    confirm "确定要卸载 V2bX 吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        service V2bX stop
        rc-update del V2bX
        rm /etc/init.d/V2bX -f
    else
        systemctl stop V2bX
        systemctl disable V2bX
        rm /etc/systemd/system/V2bX.service -f
        systemctl daemon-reload
        systemctl reset-failed
    fi
    rm /etc/V2bX/ -rf
    rm /usr/local/V2bX/ -rf

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/V2bX -f${plain} 进行删除"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}V2bX已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        if [[ x"${release}" == x"alpine" ]]; then
            service V2bX start
        else
            systemctl start V2bX
        fi
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}V2bX 启动成功，请使用 V2bX log 查看运行日志${plain}"
        else
            echo -e "${red}V2bX可能启动失败，请稍后使用 V2bX log 查看日志信息${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    if [[ x"${release}" == x"alpine" ]]; then
        service V2bX stop
    else
        systemctl stop V2bX
    fi
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}V2bX 停止成功${plain}"
    else
        echo -e "${red}V2bX停止失败，可能是因为停止时间超过了两秒，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    if [[ x"${release}" == x"alpine" ]]; then
        service V2bX restart
    else
        systemctl restart V2bX
    fi
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 重启成功，请使用 V2bX log 查看运行日志${plain}"
    else
        echo -e "${red}V2bX可能启动失败，请稍后使用 V2bX log 查看日志信息${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    if [[ x"${release}" == x"alpine" ]]; then
        service V2bX status
    else
        systemctl status V2bX --no-pager -l
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update add V2bX
    else
        systemctl enable V2bX
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 设置开机自启成功${plain}"
    else
        echo -e "${red}V2bX 设置开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    if [[ x"${release}" == x"alpine" ]]; then
        rc-update del V2bX
    else
        systemctl disable V2bX
    fi
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 取消开机自启成功${plain}"
    else
        echo -e "${red}V2bX 取消开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    if [[ x"${release}" == x"alpine" ]]; then
        echo -e "${red}alpine系统暂不支持日志查看${plain}\n" && exit 1
    else
        journalctl -u V2bX.service -e --no-pager -f
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    bash <(curl -L -s https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh)
}

update_shell() {
    wget -O /usr/bin/V2bX -N --no-check-certificate https://raw.githubusercontent.com/JJOGGER/V2bX-script/master/V2bX.sh
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/V2bX
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/V2bX/V2bX ]]; then
        return 2
    fi
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(service V2bX status | awk '{print $3}')
        if [[ x"${temp}" == x"started" ]]; then
            return 0
        else
            return 1
        fi
    else
        temp=$(systemctl status V2bX | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
        if [[ x"${temp}" == x"running" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

check_enabled() {
    if [[ x"${release}" == x"alpine" ]]; then
        temp=$(rc-update show | grep V2bX)
        if [[ x"${temp}" == x"" ]]; then
            return 1
        else
            return 0
        fi
    else
        temp=$(systemctl is-enabled V2bX)
        if [[ x"${temp}" == x"enabled" ]]; then
            return 0
        else
            return 1;
        fi
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}V2bX已安装，请不要重复安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装V2bX${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "V2bX状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "V2bX状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "V2bX状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

generate_x25519_key() {
    echo -n "正在生成 x25519 密钥："
    /usr/local/V2bX/V2bX x25519
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_V2bX_version() {
    echo -n "V2bX 版本："
    /usr/local/V2bX/V2bX version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

add_node_config() {
    echo -e "${green}请选择节点核心类型：${plain}"
    echo -e "${green}1. xray${plain}"
    echo -e "${green}2. singbox${plain}"
    echo -e "${green}3. hysteria2${plain}"
    read -rp "请输入：" core_type
    if [ "$core_type" == "1" ]; then
        core="xray"
        core_xray=true
    elif [ "$core_type" == "2" ]; then
        core="sing"
        core_sing=true
    elif [ "$core_type" == "3" ]; then
        core="hysteria2"
        core_hysteria2=true
    else
        echo "无效的选择。请选择 1 2 3。"
        continue
    fi
    while true; do
        read -rp "请输入节点Node ID：" NodeID
        # 判断NodeID是否为正整数
        if [[ "$NodeID" =~ ^[0-9]+$ ]]; then
            break  # 输入正确，退出循环
        else
            echo "错误：请输入正确的数字作为Node ID。"
        fi
    done

    if [ "$core_hysteria2" = true ] && [ "$core_xray" = false ] && [ "$core_sing" = false ]; then
        NodeType="hysteria2"
    else
        echo -e "${yellow}请选择节点传输协议：${plain}"
        echo -e "${green}1. Shadowsocks${plain}"
        echo -e "${green}2. Vless${plain}"
        echo -e "${green}3. Vmess${plain}"
        if [ "$core_sing" == true ]; then
            echo -e "${green}4. Hysteria${plain}"
            echo -e "${green}5. Hysteria2${plain}"
        fi
        if [ "$core_hysteria2" == true ] && [ "$core_sing" = false ]; then
            echo -e "${green}5. Hysteria2${plain}"
        fi
        echo -e "${green}6. Trojan${plain}"  
        if [ "$core_sing" == true ]; then
            echo -e "${green}7. Tuic${plain}"
            echo -e "${green}8. AnyTLS${plain}"
        fi
        read -rp "请输入：" NodeType
        case "$NodeType" in
            1 ) NodeType="shadowsocks" ;;
            2 ) NodeType="vless" ;;
            3 ) NodeType="vmess" ;;
            4 ) NodeType="hysteria" ;;
            5 ) NodeType="hysteria2" ;;
            6 ) NodeType="trojan" ;;
            7 ) NodeType="tuic" ;;
            8 ) NodeType="anytls" ;;
            * ) NodeType="shadowsocks" ;;
        esac
    fi
    fastopen=true
    isreality=""
    istls=""
    if [ "$NodeType" == "vless" ]; then
        read -rp "请选择是否为reality节点？(y/n)" isreality
    elif [ "$NodeType" == "hysteria" ] || [ "$NodeType" == "hysteria2" ] || [ "$NodeType" == "tuic" ] || [ "$NodeType" == "anytls" ]; then
        fastopen=false
        istls="y"
    fi

    if [[ "$isreality" != "y" && "$isreality" != "Y" &&  "$istls" != "y" ]]; then
        read -rp "请选择是否进行TLS配置？(y/n)" istls
    fi

    certmode="none"
    certdomain="example.com"
    if [[ "$isreality" != "y" && "$isreality" != "Y" && ( "$istls" == "y" || "$istls" == "Y" ) ]]; then
        echo -e "${yellow}请选择证书申请模式：${plain}"
        echo -e "${green}1. http模式自动申请，节点域名已正确解析${plain}"
        echo -e "${green}2. dns模式自动申请，需填入正确域名服务商API参数${plain}"
        echo -e "${green}3. self模式，自签证书或提供已有证书文件${plain}"
        read -rp "请输入：" certmode
        case "$certmode" in
            1 ) certmode="http" ;;
            2 ) certmode="dns" ;;
            3 ) certmode="self" ;;
        esac
        read -rp "请输入节点证书域名(example.com)：" certdomain
        if [ "$certmode" != "http" ]; then
            echo -e "${red}请手动修改配置文件后重启V2bX！${plain}"
        fi
    fi
    # 测试API地址是否可用，如果不可用则尝试备用域名
    echo -e "${yellow}正在测试API地址可用性...${plain}"
    available_host=$(find_available_api_host "$ApiHost" "$ApiKey" "$NodeID" "$NodeType")
    test_result=$?
    if [ $test_result -eq 0 ] && [ -n "$available_host" ]; then
        if [ "$available_host" != "$ApiHost" ]; then
            echo -e "${yellow}原API地址不可用，已自动切换到: $available_host${plain}"
            ApiHost="$available_host"
        else
            echo -e "${green}API地址可用${plain}"
        fi
    else
        echo -e "${yellow}无法测试API地址，将使用输入的地址${plain}"
    fi

    ipv6_support=$(check_ipv6_support)
    listen_ip="0.0.0.0"
    if [ "$ipv6_support" -eq 1 ]; then
        listen_ip="::"
    fi
    node_config=""
    if [ "$core_type" == "1" ]; then 
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "0.0.0.0",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "EnableProxyProtocol": false,
            "EnableUot": true,
            "EnableTFO": true,
            "DNSType": "UseIPv4",
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    elif [ "$core_type" == "2" ]; then
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "$listen_ip",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "TCPFastOpen": $fastopen,
            "SniffEnabled": true,
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    elif [ "$core_type" == "3" ]; then
    node_config=$(cat <<EOF
{
            "Core": "$core",
            "ApiHost": "$ApiHost",
            "ApiKey": "$ApiKey",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Hysteria2ConfigPath": "/etc/V2bX/hy2config.yaml",
            "Timeout": 30,
            "ListenIP": "",
            "SendIP": "0.0.0.0",
            "DeviceOnlineMinTraffic": 200,
            "MinReportTraffic": 0,
            "CertConfig": {
                "CertMode": "$certmode",
                "RejectUnknownSni": false,
                "CertDomain": "$certdomain",
                "CertFile": "/etc/V2bX/fullchain.cer",
                "KeyFile": "/etc/V2bX/cert.key",
                "Email": "v2bx@github.com",
                "Provider": "cloudflare",
                "DNSEnv": {
                    "EnvName": "env1"
                }
            }
        }
EOF
)
    fi
    nodes_config+=("$node_config")
}

generate_config_file() {
    echo -e "${yellow}V2bX 配置文件生成向导${plain}"
    echo -e "${red}请阅读以下注意事项：${plain}"
    echo -e "${red}1. 目前该功能正处测试阶段${plain}"
    echo -e "${red}2. 生成的配置文件会保存到 /etc/V2bX/config.json${plain}"
    echo -e "${red}3. 原来的配置文件会保存到 /etc/V2bX/config.json.bak${plain}"
    echo -e "${red}4. 目前仅部分支持TLS${plain}"
    echo -e "${red}5. 使用此功能生成的配置文件会自带审计，确定继续？(y/n)${plain}"
    read -rp "请输入：" continue_prompt
    if [[ "$continue_prompt" =~ ^[Nn][Oo]? ]]; then
        exit 0
    fi
    
    # 读取现有配置文件中的节点（如果存在）
    existing_nodes=""
    if [ -f "/etc/V2bX/config.json" ]; then
        echo -e "${green}检测到现有配置文件${plain}"
        read -rp "是否保留已有节点配置并追加新节点？(y/n，默认y): " keep_existing
        if [[ "$keep_existing" =~ ^[Nn][Oo]? ]]; then
            echo -e "${yellow}将创建全新配置，不保留已有节点${plain}"
        else
            echo -e "${green}将保留已有节点并追加新节点${plain}"
            # 使用 Python 提取现有节点（Python 通常已安装）
            if command -v python3 &> /dev/null; then
                result=$(python3 << 'PYTHON_SCRIPT'
import json
import sys
try:
    with open('/etc/V2bX/config.json', 'r', encoding='utf-8') as f:
        config = json.load(f)
    nodes = config.get('Nodes', [])
    if not nodes:
        sys.exit(1)
    # 输出节点数量
    print(f"NODE_COUNT:{len(nodes)}")
    # 输出格式化的节点，自动添加逗号（除了最后一个）
    for i, node in enumerate(nodes):
        node_json = json.dumps(node, indent=8, ensure_ascii=False)
        # 给每行添加8空格缩进（因为在Nodes数组内）
        lines = node_json.split('\n')
        indented_lines = ['        ' + line for line in lines]
        output = '\n'.join(indented_lines)
        print(output, end='')
        # 除了最后一个节点，其他都加逗号
        if i < len(nodes) - 1:
            print(',')
        else:
            print()
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)
                exit_code=$?
                if [ $exit_code -eq 0 ] && [ -n "$result" ]; then
                    node_count=$(echo "$result" | head -n 1 | grep "NODE_COUNT:" | cut -d: -f2)
                    existing_nodes=$(echo "$result" | tail -n +2)
                    if [ -n "$existing_nodes" ] && [ -n "$node_count" ]; then
                        echo -e "${green}已读取 $node_count 个现有节点${plain}"
                    else
                        echo -e "${yellow}未找到现有节点，将创建新配置${plain}"
                        existing_nodes=""
                    fi
                else
                    echo -e "${yellow}读取现有节点失败，将创建新配置${plain}"
                    existing_nodes=""
                fi
            elif command -v python &> /dev/null; then
                result=$(python << 'PYTHON_SCRIPT'
import json
import sys
try:
    with open('/etc/V2bX/config.json', 'r', encoding='utf-8') as f:
        config = json.load(f)
    nodes = config.get('Nodes', [])
    if not nodes:
        sys.exit(1)
    print(f"NODE_COUNT:{len(nodes)}")
    for i, node in enumerate(nodes):
        node_json = json.dumps(node, indent=8, ensure_ascii=False)
        lines = node_json.split('\n')
        indented_lines = ['        ' + line for line in lines]
        output = '\n'.join(indented_lines)
        print(output, end='')
        if i < len(nodes) - 1:
            print(',')
        else:
            print()
    sys.exit(0)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
)
                exit_code=$?
                if [ $exit_code -eq 0 ] && [ -n "$result" ]; then
                    node_count=$(echo "$result" | head -n 1 | grep "NODE_COUNT:" | cut -d: -f2)
                    existing_nodes=$(echo "$result" | tail -n +2)
                    if [ -n "$existing_nodes" ] && [ -n "$node_count" ]; then
                        echo -e "${green}已读取 $node_count 个现有节点${plain}"
                    else
                        existing_nodes=""
                    fi
                else
                    existing_nodes=""
                fi
            else
                echo -e "${yellow}未找到 Python，无法读取现有节点，将创建新配置${plain}"
                echo -e "${yellow}建议安装 Python 或手动编辑配置文件添加节点${plain}"
            fi
        fi
    fi
    
    nodes_config=()
    first_node=true
    core_xray=false
    core_sing=false
    core_hysteria2=false
    # 如果保留了已有节点，根据已存在节点的 Core 类型预置核心标记，避免覆盖原有 Cores
    if [ -n "$existing_nodes" ]; then
        if grep -q '"Core": "xray"' /etc/V2bX/config.json 2>/dev/null; then
            core_xray=true
        fi
        if grep -q '"Core": "sing"' /etc/V2bX/config.json 2>/dev/null; then
            core_sing=true
        fi
        if grep -q '"Core": "hysteria2"' /etc/V2bX/config.json 2>/dev/null; then
            core_hysteria2=true
        fi
    fi
    fixed_api_info=false
    check_api=false
    
    # 检查是否有固定的API信息
    fixed_api_data=$(read_fixed_api 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$fixed_api_data" ]; then
        fixed_api_host=$(echo "$fixed_api_data" | head -n 1)
        fixed_api_key=$(echo "$fixed_api_data" | tail -n 1)
        if [ -n "$fixed_api_host" ] && [ -n "$fixed_api_key" ]; then
            echo -e "${green}检测到已保存的固定机场网址和API Key${plain}"
            echo -e "${green}机场网址: $fixed_api_host${plain}"
            read -rp "是否使用固定的机场网址和API Key？(y/n，默认y): " use_fixed
            if [[ "$use_fixed" =~ ^[Yy]?$ ]] || [ -z "$use_fixed" ]; then
                fixed_api_info=true
                ApiHost="$fixed_api_host"
                ApiKey="$fixed_api_key"
                echo -e "${green}已使用固定的机场网址和API Key${plain}"
            fi
        fi
    fi
    
    while true; do
        if [ "$first_node" = true ]; then
            if [ "$fixed_api_info" = false ]; then
                # 检查是否有备用域名列表
                backup_domains=$(read_backup_domains 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$backup_domains" ]; then
                    echo -e "${green}检测到备用域名列表，可以选择：${plain}"
                    echo -e "${green}1. 从备用域名列表中选择${plain}"
                    echo -e "${green}2. 手动输入机场网址${plain}"
                    read -rp "请选择 (1/2，默认2): " select_method
                    if [ "$select_method" = "1" ]; then
                        echo -e "${yellow}备用域名列表：${plain}"
                        domain_index=1
                        domain_array=()
                        while IFS= read -r domain; do
                            if [ -n "$domain" ]; then
                                echo -e "${green}  ${domain_index}. ${domain}${plain}"
                                domain_array+=("$domain")
                                ((domain_index++))
                            fi
                        done <<< "$backup_domains"
                        read -rp "请选择备用域名编号: " selected_index
                        if [[ "$selected_index" =~ ^[0-9]+$ ]] && [ "$selected_index" -ge 1 ] && [ "$selected_index" -le "${#domain_array[@]}" ]; then
                            ApiHost="${domain_array[$((selected_index-1))]}"
                            echo -e "${green}已选择: $ApiHost${plain}"
                        else
                            echo -e "${red}无效的选择，将使用手动输入${plain}"
                            read -rp "请输入机场网址(https://example.com)：" ApiHost
                        fi
                    else
                        read -rp "请输入机场网址(https://example.com)：" ApiHost
                    fi
                else
                    read -rp "请输入机场网址(https://example.com)：" ApiHost
                fi
                read -rp "请输入面板对接API Key：" ApiKey
                read -rp "是否设置固定的机场网址和API Key？(y/n): " fixed_api
                if [ "$fixed_api" = "y" ] || [ "$fixed_api" = "Y" ]; then
                    fixed_api_info=true
                    save_fixed_api "$ApiHost" "$ApiKey"
                    echo -e "${green}成功固定地址${plain}"
                fi
            fi
            first_node=false
            add_node_config
        else
            read -rp "是否继续添加节点配置？(配置了证书的话先等待1-2分钟再继续。回车继续，输入n或no退出)" continue_adding_node
            if [[ "$continue_adding_node" =~ ^[Nn][Oo]? ]]; then
                break
            elif [ "$fixed_api_info" = false ]; then
                backup_domains=$(read_backup_domains 2>/dev/null)
                if [ $? -eq 0 ] && [ -n "$backup_domains" ]; then
                    echo -e "${green}检测到备用域名列表，可以选择：${plain}"
                    echo -e "${green}1. 从备用域名列表中选择${plain}"
                    echo -e "${green}2. 手动输入机场网址${plain}"
                    read -rp "请选择 (1/2，默认2): " select_method
                    if [ "$select_method" = "1" ]; then
                        echo -e "${yellow}备用域名列表：${plain}"
                        domain_index=1
                        domain_array=()
                        while IFS= read -r domain; do
                            if [ -n "$domain" ]; then
                                echo -e "${green}  ${domain_index}. ${domain}${plain}"
                                domain_array+=("$domain")
                                ((domain_index++))
                            fi
                        done <<< "$backup_domains"
                        read -rp "请选择备用域名编号: " selected_index
                        if [[ "$selected_index" =~ ^[0-9]+$ ]] && [ "$selected_index" -ge 1 ] && [ "$selected_index" -le "${#domain_array[@]}" ]; then
                            ApiHost="${domain_array[$((selected_index-1))]}"
                            echo -e "${green}已选择: $ApiHost${plain}"
                        else
                            echo -e "${red}无效的选择，将使用手动输入${plain}"
                            read -rp "请输入机场网址：" ApiHost
                        fi
                    else
                        read -rp "请输入机场网址：" ApiHost
                    fi
                else
                    read -rp "请输入机场网址：" ApiHost
                fi
                read -rp "请输入面板对接API Key：" ApiKey
            fi
            add_node_config
        fi
    done

    # 初始化核心配置数组
    cores_config="["

    # 检查并添加xray核心配置
    if [ "$core_xray" = true ]; then
        cores_config+="
    {
        \"Type\": \"xray\",
        \"Log\": {
            \"Level\": \"error\",
            \"ErrorPath\": \"/etc/V2bX/error.log\"
        },
        \"OutboundConfigPath\": \"/etc/V2bX/custom_outbound.json\",
        \"RouteConfigPath\": \"/etc/V2bX/route.json\"
    },"
    fi

    # 检查并添加sing核心配置
    if [ "$core_sing" = true ]; then
        cores_config+="
    {
        \"Type\": \"sing\",
        \"Log\": {
            \"Level\": \"error\",
            \"Timestamp\": true
        },
        \"NTP\": {
            \"Enable\": false,
            \"Server\": \"time.apple.com\",
            \"ServerPort\": 0
        },
        \"OriginalPath\": \"/etc/V2bX/sing_origin.json\"
    },"
    fi

    # 检查并添加hysteria2核心配置
    if [ "$core_hysteria2" = true ]; then
        cores_config+="
    {
        \"Type\": \"hysteria2\",
        \"Log\": {
            \"Level\": \"error\"
        }
    },"
    fi

    # 移除最后一个逗号并关闭数组
    cores_config+="]"
    # 更精确地移除最后一个核心配置的逗号
    cores_config=$(echo "$cores_config" | sed -E 's/},[[:space:]]*\]$/}]/')

    # 切换到配置文件目录
    cd /etc/V2bX
    
    # 备份旧的配置文件
    if [ -f "config.json" ]; then
        cp config.json config.json.bak.$(date +%Y%m%d_%H%M%S)
    fi
    
    # 拼接新节点配置（每个节点间用逗号+换行分隔）
    formatted_nodes_config=""
    node_count=${#nodes_config[@]}
    for i in "${!nodes_config[@]}"; do
        formatted_nodes_config+="${nodes_config[$i]}"
        # 除了最后一个节点，其他都加逗号
        if [ $i -lt $((node_count - 1)) ]; then
            formatted_nodes_config+=","
        fi
        formatted_nodes_config+=$'\n'
    done
    
    # 合并现有节点和新节点
    all_nodes_config=""
    if [ -n "$existing_nodes" ] && [ -n "$formatted_nodes_config" ]; then
        # 有现有节点 + 有新节点 = 合并（existing_nodes已有逗号）
        all_nodes_config="${existing_nodes},"$'\n'"${formatted_nodes_config}"
    elif [ -n "$existing_nodes" ]; then
        # 只有现有节点（existing_nodes的最后一个节点已经没有逗号）
        all_nodes_config="$existing_nodes"
    elif [ -n "$formatted_nodes_config" ]; then
        # 只有新节点
        all_nodes_config="$formatted_nodes_config"
    fi

    # 创建 config.json 文件
    cat <<EOF > /etc/V2bX/config.json
{
    "Log": {
        "Level": "error",
        "Output": ""
    },
    "Cores": $cores_config,
    "Nodes": [
$all_nodes_config
    ]
}
EOF

    # 验证生成的JSON格式是否正确
    if command -v python3 &> /dev/null; then
        if python3 -m json.tool /etc/V2bX/config.json > /dev/null 2>&1; then
            echo -e "${green}JSON格式验证通过${plain}"
        else
            echo -e "${red}警告：生成的JSON格式可能有问题，请检查配置文件${plain}"
            echo -e "${yellow}正在尝试修复JSON格式...${plain}"
            # 尝试修复常见的JSON格式问题
            python3 << 'PYTHON_FIX'
import json
import re
import sys

try:
    with open('/etc/V2bX/config.json', 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 修复常见的JSON格式问题：移除对象末尾的逗号
    # 匹配 }, 或 } 后面跟逗号的情况（在数组或对象末尾）
    content = re.sub(r'(\})\s*,(\s*[}\]])', r'\1\2', content)
    
    # 尝试解析JSON
    config = json.loads(content)
    
    # 重新格式化并保存
    with open('/etc/V2bX/config.json', 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    
    print("JSON格式已修复")
    sys.exit(0)
except Exception as e:
    print(f"修复失败: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_FIX
            if [ $? -eq 0 ]; then
                echo -e "${green}JSON格式已修复${plain}"
            else
                echo -e "${red}JSON格式修复失败，请手动检查配置文件${plain}"
            fi
        fi
    elif command -v python &> /dev/null; then
        if python -m json.tool /etc/V2bX/config.json > /dev/null 2>&1; then
            echo -e "${green}JSON格式验证通过${plain}"
        else
            echo -e "${red}警告：生成的JSON格式可能有问题，请检查配置文件${plain}"
        fi
    else
        echo -e "${yellow}未找到Python，跳过JSON格式验证${plain}"
    fi
    
    # 创建 custom_outbound.json 文件
    cat <<EOF > /etc/V2bX/custom_outbound.json
    [
        {
            "tag": "IPv4_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4v6"
            }
        },
        {
            "tag": "IPv6_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv6"
            }
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
EOF
    
    # 创建 route.json 文件
    cat <<EOF > /etc/V2bX/route.json
    {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "geoip:private"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "domain": [
                    "regexp:(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
                    "regexp:(.+.|^)(360|so).(cn|com)",
                    "regexp:(Subject|HELO|SMTP)",
                    "regexp:(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
                    "regexp:(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
                    "regexp:(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
                    "regexp:(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
                    "regexp:(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
                    "regexp:(.+.|^)(360).(cn|com|net)",
                    "regexp:(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
                    "regexp:(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
                    "regexp:(.*.||)(netvigator|torproject).(com|cn|net|org)",
                    "regexp:(..||)(visa|mycard|gash|beanfun|bank).",
                    "regexp:(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
                    "regexp:(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
                    "regexp:(.*.||)(mycard).(com|tw)",
                    "regexp:(.*.||)(gash).(com|tw)",
                    "regexp:(.bank.)",
                    "regexp:(.*.||)(pincong).(rocks)",
                    "regexp:(.*.||)(taobao).(com)",
                    "regexp:(.*.||)(laomoe|jiyou|ssss|lolicp|vv1234|0z|4321q|868123|ksweb|mm126).(com|cloud|fun|cn|gs|xyz|cc)",
                    "regexp:(flows|miaoko).(pages).(dev)"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "127.0.0.1/32",
                    "10.0.0.0/8",
                    "fc00::/7",
                    "fe80::/10",
                    "172.16.0.0/12"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "protocol": [
                    "bittorrent"
                ]
            }
        ]
    }
EOF

    ipv6_support=$(check_ipv6_support)
    dnsstrategy="ipv4_only"
    if [ "$ipv6_support" -eq 1 ]; then
        dnsstrategy="prefer_ipv4"
    fi
    # 创建 sing_origin.json 文件
    cat <<EOF > /etc/V2bX/sing_origin.json
{
  "dns": {
    "servers": [
      {
        "tag": "cf",
        "address": "1.1.1.1"
      }
    ],
    "strategy": "$dnsstrategy"
  },
  "outbounds": [
    {
      "tag": "direct",
      "type": "direct",
      "domain_resolver": {
        "server": "cf",
        "strategy": "$dnsstrategy"
      }
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "ip_is_private": true,
        "outbound": "block"
      },
      {
        "domain_regex": [
            "(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
            "(.+.|^)(360|so).(cn|com)",
            "(Subject|HELO|SMTP)",
            "(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
            "(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
            "(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
            "(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
            "(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
            "(.+.|^)(360).(cn|com|net)",
            "(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
            "(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
            "(.*.||)(netvigator|torproject).(com|cn|net|org)",
            "(..||)(visa|mycard|gash|beanfun|bank).",
            "(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
            "(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
            "(.*.||)(mycard).(com|tw)",
            "(.*.||)(gash).(com|tw)",
            "(.bank.)",
            "(.*.||)(pincong).(rocks)",
            "(.*.||)(taobao).(com)",
            "(.*.||)(laomoe|jiyou|ssss|lolicp|vv1234|0z|4321q|868123|ksweb|mm126).(com|cloud|fun|cn|gs|xyz|cc)",
            "(flows|miaoko).(pages).(dev)"
        ],
        "outbound": "block"
      },
      {
        "outbound": "direct",
        "network": [
          "udp","tcp"
        ]
      }
    ]
  },
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
}
EOF

    # 创建 hy2config.yaml 文件           
    cat <<EOF > /etc/V2bX/hy2config.yaml
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 30s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false
ignoreClientBandwidth: false
disableUDP: false
udpIdleTimeout: 60s
resolver:
  type: system
acl:
  inline:
    - direct(geosite:google)
    - reject(geosite:cn)
    - reject(geoip:cn)
masquerade:
  type: 404
EOF
    echo -e "${green}V2bX 配置文件生成完成，正在重新启动 V2bX 服务${plain}"
    restart 0
    before_show_menu
}

# 放开防火墙端口
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}放开防火墙端口成功！${plain}"
}

show_usage() {
    echo "V2bX 管理脚本使用方法: "
    echo "------------------------------------------"
    echo "V2bX              - 显示管理菜单 (功能更多)"
    echo "V2bX start        - 启动 V2bX"
    echo "V2bX stop         - 停止 V2bX"
    echo "V2bX restart      - 重启 V2bX"
    echo "V2bX status       - 查看 V2bX 状态"
    echo "V2bX enable       - 设置 V2bX 开机自启"
    echo "V2bX disable      - 取消 V2bX 开机自启"
    echo "V2bX log          - 查看 V2bX 日志"
    echo "V2bX x25519       - 生成 x25519 密钥"
    echo "V2bX generate     - 生成 V2bX 配置文件"
    echo "V2bX editnode     - 修改已存在节点的 NodeID"
    echo "V2bX editnodefull - 修改单个节点的完整配置（交互式）"
    echo "V2bX delnode      - 删除单个节点配置"
    echo "V2bX updateapihost - 批量修改所有节点的机场地址（ApiHost）"
    echo "V2bX updatebackupdomains - 更新备用域名列表"
    echo "V2bX checkapifrequency - 检查API请求频率和优化建议"
    echo "V2bX update       - 更新 V2bX"
    echo "V2bX update x.x.x - 安装 V2bX 指定版本"
    echo "V2bX install      - 安装 V2bX"
    echo "V2bX uninstall    - 卸载 V2bX"
    echo "V2bX version      - 查看 V2bX 版本"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}V2bX 后端管理脚本，${plain}${red}不适用于docker${plain}
--- https://github.com/JJOGGER/V2bX ---
  ${green}0.${plain} 修改配置
————————————————
  ${green}1.${plain} 安装 V2bX
  ${green}2.${plain} 更新 V2bX
  ${green}3.${plain} 卸载 V2bX
————————————————
  ${green}4.${plain} 启动 V2bX
  ${green}5.${plain} 停止 V2bX
  ${green}6.${plain} 重启 V2bX
  ${green}7.${plain} 查看 V2bX 状态
  ${green}8.${plain} 查看 V2bX 日志
————————————————
  ${green}9.${plain} 设置 V2bX 开机自启
  ${green}10.${plain} 取消 V2bX 开机自启
————————————————
  ${green}11.${plain} 一键安装 bbr (最新内核)
  ${green}12.${plain} 查看 V2bX 版本
  ${green}13.${plain} 生成 X25519 密钥
  ${green}14.${plain} 升级 V2bX 维护脚本
  ${green}15.${plain} 生成 V2bX 配置文件
  ${green}16.${plain} 放行 VPS 的所有网络端口
  ${green}17.${plain} 修改已存在节点的 NodeID
  ${green}18.${plain} 修改单个节点的完整配置
  ${green}19.${plain} 删除单个节点配置
  ${green}20.${plain} 批量修改所有节点的机场地址（ApiHost）
  ${green}21.${plain} 更新备用域名列表
  ${green}22.${plain} 检查API请求频率和优化建议
  ${green}23.${plain} 退出脚本
 "
 #后续更新可加入上方字符串中
    show_status
    echo && read -rp "请输入选择 [0-23]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) install_bbr ;;
        12) check_install && show_V2bX_version ;;
        13) check_install && generate_x25519_key ;;
        14) update_shell ;;
        15) generate_config_file ;;
        16) open_ports ;;
        17) check_install && edit_node_id ;;
        18) check_install && edit_node_full ;;
        19) check_install && delete_node ;;
        20) check_install && batch_update_api_host ;;
        21) update_backup_domains ;;
        22) check_install && check_api_frequency ;;
        23) exit ;;
        *) echo -e "${red}请输入正确的数字 [0-23]${plain}" ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 $2 ;;
        "config") config $* ;;
        "generate") generate_config_file ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "x25519") check_install 0 && generate_x25519_key 0 ;;
        "version") check_install 0 && show_V2bX_version 0 ;;
        "editnode") check_install 0 && edit_node_id ;;
        "editnodefull") check_install 0 && edit_node_full ;;
        "delnode") check_install 0 && delete_node ;;
        "updateapihost") check_install 0 && batch_update_api_host ;;
        "updatebackupdomains") update_backup_domains ;;
        "checkapifrequency") check_install 0 && check_api_frequency ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
