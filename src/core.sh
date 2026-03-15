#!/bin/bash

protocol_list=(
    TUIC
    Trojan
    Hysteria2
    VMess-WS
    VMess-TCP
    VMess-HTTP
    VMess-QUIC
    Shadowsocks
    VMess-H2-TLS
    VMess-WS-TLS
    VLESS-H2-TLS
    VLESS-WS-TLS
    Trojan-H2-TLS
    Trojan-WS-TLS
    VMess-HTTPUpgrade-TLS
    VLESS-HTTPUpgrade-TLS
    Trojan-HTTPUpgrade-TLS
    VLESS-REALITY
    VLESS-HTTP2-REALITY
    AnyTLS
    CFtunnel
    Socks
)

ss_method_list=(
    aes-128-gcm
    aes-256-gcm
    chacha20-ietf-poly1305
    xchacha20-ietf-poly1305
    2022-blake3-aes-128-gcm
    2022-blake3-aes-256-gcm
    2022-blake3-chacha20-poly1305
)

info_list=(
    "协议 (protocol)"
    "地址 (address)"
    "端口 (port)"
    "用户ID (id)"
    "传输协议 (network)"
    "伪装类型 (type)"
    "伪装域名 (host)"
    "路径 (path)"
    "传输层安全 (TLS)"
    "应用层协议协商 (Alpn)"
    "密码 (password)"
    "加密方式 (encryption)"
    "链接 (URL)"
    "目标地址 (remote addr)"
    "目标端口 (remote port)"
    "流控 (flow)"
    "SNI (serverName)"
    "指纹 (Fingerprint)"
    "公钥 (Public key)"
    "用户名 (Username)"
    "跳过证书验证 (allowInsecure)"
    "拥塞控制算法 (congestion_control)"
)

change_list=(
    "更改协议"
    "更改端口"
    "更改域名"
    "更改路径"
    "更改密码"
    "更改 UUID"
    "更改加密方式"
    "更改目标地址"
    "更改目标端口"
    "更改密钥"
    "更改 SNI (serverName)"
    "更改伪装网站"
    "更改用户名 (Username)"
)

servername_list=(
    www.amazon.com
    www.ebay.com
    www.paypal.com
    www.cloudflare.com
    dash.cloudflare.com
    aws.amazon.com
)

is_random_ss_method=${ss_method_list[$(shuf -i 4-6 -n1)]} 
is_random_servername=${servername_list[$(shuf -i 0-${#servername_list[@]} -n1) - 1]}

msg() {
    echo -e "$@"
}

msg_ul() {
    echo -e "\e[4m$@\e[0m"
}

pause() {
    echo
    echo -ne "按 $(_green Enter 回车键) 继续, 或按 $(_red Ctrl + C) 取消."
    read -rs -d $'\n'
    echo
}

get_uuid() {
    tmp_uuid=$(cat /proc/sys/kernel/random/uuid)
}

get_ip() {
    if [[ $ip || $is_no_auto_tls || $is_gen || $is_dont_get_ip ]]; then
        return
    fi
    export "$(_wget -4 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip=)" &>/dev/null
    if [[ ! $ip ]]; then
        export "$(_wget -6 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip=)" &>/dev/null
    fi
    if [[ ! $ip ]]; then
        err "获取服务器 IP 失败.."
    fi
}

install_cloudflared() {
    if [[ ! $(type -P cloudflared) ]]; then
        msg "正在下载并安装 Cloudflare Tunnel (cloudflared)..."
        local cf_arch="amd64"
        if [[ $(uname -m) =~ "aarch64" || $(uname -m) =~ "armv8" ]]; then
            cf_arch="arm64"
        fi
        wget -qO /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${cf_arch}
        chmod +x /usr/local/bin/cloudflared
        msg "✅ Cloudflare Tunnel 安装完成."
    fi
}

create_cftunnel_service() {
    local token=$1
    local l_port=$2
    cat <<EOF > /lib/systemd/system/cftunnel-${l_port}.service
[Unit]
Description=Cloudflare Tunnel for Port ${l_port}
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate run --token ${token}
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now cftunnel-${l_port}.service &>/dev/null
    msg "✅ CFtunnel 穿透守护服务 (关联内部端口: ${l_port}) 已创建并启动."
    msg "⚠️  $(_yellow "重要：你还需要在 Cloudflare 面板完成最后一步映射！")"
    msg "👉 $(_cyan "图文配置教程：https://github.com/LuoPoJunZi/Sing-box-LPMG/blob/main/CFTunnels.md")"
}

firewall_allow() {
    local target_port=$1
    if [[ -z "$target_port" ]]; then
        return
    fi
    
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        ufw allow ${target_port}/tcp >/dev/null 2>&1
        ufw allow ${target_port}/udp >/dev/null 2>&1
        msg "✅ 防火墙 (UFW): 已自动放行端口 ${target_port}"
    elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld | grep -q "^active"; then
        firewall-cmd --add-port=${target_port}/tcp --permanent >/dev/null 2>&1
        firewall-cmd --add-port=${target_port}/udp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        msg "✅ 防火墙 (Firewalld): 已自动放行端口 ${target_port}"
    elif command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport ${target_port} -j ACCEPT >/dev/null 2>&1
        iptables -I INPUT -p udp --dport ${target_port} -j ACCEPT >/dev/null 2>&1
        if [[ -f /etc/sysconfig/iptables ]]; then
            service iptables save >/dev/null 2>&1
        fi
        if command -v netfilter-persistent >/dev/null 2>&1; then
            netfilter-persistent save >/dev/null 2>&1
        fi
        msg "✅ 防火墙 (Iptables): 已尝试放行端口 ${target_port}"
    fi
}

get_port() {
    is_count=0
    while :; do
        ((is_count++))
        if [[ $is_count -ge 233 ]]; then
            err "自动获取可用端口失败次数达到 233 次, 请检查端口占用情况."
        fi
        tmp_port=$(shuf -i 20000-65535 -n 1)
        if [[ ! $(is_test port_used $tmp_port) && $tmp_port != $port ]]; then
            break
        fi
    done
    
    if [[ $tmp_port ]]; then
        firewall_allow "$tmp_port"
    fi
}

get_pbk() {
    is_tmp_pbk=($($is_core_bin generate reality-keypair | sed 's/.*://'))
    is_public_key=${is_tmp_pbk[1]}
    is_private_key=${is_tmp_pbk[0]}
}

show_list() {
    PS3=''
    COLUMNS=1
    select i in "$@"; do echo; done &
    wait
}

is_test() {
    case $1 in
    number)
        echo $2 | grep -E '^[1-9][0-9]?+$'
        ;;
    port)
        if [[ $(is_test number $2) ]]; then
            if [[ $2 -le 65535 ]]; then
                echo ok
            fi
        fi
        ;;
    port_used)
        if [[ $(is_port_used $2) && ! $is_cant_test_port ]]; then
            echo ok
        fi
        ;;
    domain)
        echo $2 | grep -E -i '^\w(\w|\-|\.)?+\.\w+$'
        ;;
    path)
        echo $2 | grep -E -i '^\/\w(\w|\-|\/)?+\w$'
        ;;
    uuid)
        echo $2 | grep -E -i '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        ;;
    esac
}

is_port_used() {
    if [[ $(type -P netstat) ]]; then
        if [[ ! $is_used_port ]]; then
            is_used_port="$(netstat -tunlp | sed -n 's/.*:\([0-9]\+\).*/\1/p' | sort -nu)"
        fi
        echo $is_used_port | sed 's/ /\n/g' | grep ^${1}$
        return
    fi
    if [[ $(type -P ss) ]]; then
        if [[ ! $is_used_port ]]; then
            is_used_port="$(ss -tunlp | sed -n 's/.*:\([0-9]\+\).*/\1/p' | sort -nu)"
        fi
        echo $is_used_port | sed 's/ /\n/g' | grep ^${1}$
        return
    fi
    is_cant_test_port=1
    msg "$is_warn 无法检测端口是否可用."
    msg "请执行: $(_yellow "${cmd} update -y; ${cmd} install net-tools -y") 来修复此问题."
}

ask() {
    case $1 in
    set_ss_method)
        is_tmp_list=(${ss_method_list[@]})
        is_default_arg=$is_random_ss_method
        is_opt_msg="\n请选择加密方式:\n"
        is_opt_input_msg="(默认\e[92m $is_default_arg\e[0m):"
        is_ask_set=ss_method
        ;;
    set_protocol)
        echo -e "\e[96m=====================================================\e[0m"
        echo -e "                 请选择要添加的协议"
        echo -e "\e[96m=====================================================\e[0m"
        echo -e "  \e[93m[ 基础协议 ]\e[0m"
        echo -e "  \e[92m(1)\e[0m TUIC        \e[92m(2)\e[0m Trojan       \e[92m(3)\e[0m Hysteria2   \e[92m(4)\e[0m VMess-WS"
        echo -e "  \e[92m(5)\e[0m VMess-TCP   \e[92m(6)\e[0m VMess-HTTP   \e[92m(7)\e[0m VMess-QUIC  \e[92m(8)\e[0m Shadowsocks"
        echo -e "  \e[93m[ TLS 隧道 ]\e[0m"
        echo -e "  \e[92m(9)\e[0m VMess-H2    \e[92m(10)\e[0m VMess-WS   \e[92m(11)\e[0m VLESS-H2   \e[92m(12)\e[0m VLESS-WS"
        echo -e "  \e[92m(13)\e[0m Trojan-H2  \e[92m(14)\e[0m Trojan-WS  \e[92m(15)\e[0m VMess-HU   \e[92m(16)\e[0m VLESS-HU"
        echo -e "  \e[92m(17)\e[0m Trojan-HU\n"
        echo -e "  \e[93m[ 强力抗封锁 ]\e[0m"
        echo -e "  \e[92m(18)\e[0m VLESS-REALITY     \e[92m(19)\e[0m VLESS-HTTP2-REALITY"
        echo -e "  \e[92m(20)\e[0m AnyTLS\n"
        echo -e "  \e[93m[ 隧道穿透 ]\e[0m"
        echo -e "  \e[92m(21)\e[0m CFtunnel          \e[92m(22)\e[0m Socks"
        echo -e "\e[90m-----------------------------------------------------\e[0m"
        is_ask_set=is_new_protocol
        is_opt_input_msg="➡️ 请选择协议序号 [\e[91m1-22\e[0m]: "
        ;;
    set_change_list)
        is_tmp_list=()
        for v in ${is_can_change[@]}; do
            is_tmp_list+=("${change_list[$v]}")
        done
        is_opt_msg="\n请选择更改:\n"
        is_ask_set=is_change_str
        is_opt_input_msg=$3
        ;;
    string)
        is_ask_set=$2
        is_opt_input_msg=$3
        ;;
    list)
        is_ask_set=$2
        if [[ ! $is_tmp_list ]]; then
            is_tmp_list=($3)
        fi
        is_opt_msg=$4
        is_opt_input_msg=$5
        ;;
    get_config_file)
        is_tmp_list=("${is_all_json[@]}")
        is_opt_msg="\n请选择配置:\n"
        is_ask_set=is_config_file
        ;;
    esac
    
    if [[ $is_opt_msg ]]; then
        msg "$is_opt_msg"
    fi
    if [[ $is_tmp_list ]]; then
        show_list "${is_tmp_list[@]}"
    fi
    
    while :; do
        echo -ne "$is_opt_input_msg"
        read REPLY
        if [[ ! $REPLY && $is_emtpy_exit ]]; then
            exit
        fi
        if [[ ! $REPLY && $is_default_arg ]]; then
            export $is_ask_set=$is_default_arg
            break
        fi
        if [[ ! $REPLY && ! $is_default_arg && ! $is_emtpy_exit ]]; then
            continue
        fi

        if [[ $1 == "set_protocol" ]]; then
            if [[ "$REPLY" =~ ^([1-9]|1[0-9]|2[0-2])$ ]]; then
                export $is_ask_set="${protocol_list[$REPLY-1]}"
                break
            fi
        elif [[ ! $is_tmp_list ]]; then
            if [[ $(grep port <<<$is_ask_set) ]]; then
                if [[ ! $(is_test port "$REPLY") ]]; then
                    msg "$is_err 请输入正确的端口, 可选(1-65535)"
                    continue
                fi
                if [[ $(is_test port_used $REPLY) && $is_ask_set != 'door_port' ]]; then
                    msg "$is_err 无法使用 ($REPLY) 端口."
                    continue
                fi
            fi
            if [[ $(grep path <<<$is_ask_set) && ! $(is_test path "$REPLY") ]]; then
                if [[ ! $tmp_uuid ]]; then
                    get_uuid
                fi
                msg "$is_err 请输入正确的路径, 例如: /$tmp_uuid"
                continue
            fi
            if [[ $(grep uuid <<<$is_ask_set) && ! $(is_test uuid "$REPLY") ]]; then
                if [[ ! $tmp_uuid ]]; then
                    get_uuid
                fi
                msg "$is_err 请输入正确的 UUID, 例如: $tmp_uuid"
                continue
            fi
            if [[ $(grep ^y$ <<<$is_ask_set) ]]; then
                if [[ $(grep -i ^y$ <<<"$REPLY") ]]; then
                    break
                fi
                msg "请输入 (y)"
                continue
            fi
            if [[ $REPLY ]]; then
                export $is_ask_set=$REPLY
                msg "使用: ${!is_ask_set}"
                break
            fi
        else
            if [[ $(is_test number "$REPLY") ]]; then
                is_ask_result=${is_tmp_list[$REPLY - 1]}
            fi
            if [[ $is_ask_result ]]; then
                export $is_ask_set="$is_ask_result"
                msg "选择: ${!is_ask_set}"
                break
            fi
        fi

        msg "输入${is_err}"
    done
    unset is_opt_msg is_opt_input_msg is_tmp_list is_ask_result is_default_arg is_emtpy_exit
}

create() {
    case $1 in
    server)
        is_tls=none
        get new
        is_listen='listen: "::"'
        
        if [[ $is_new_protocol == 'CFtunnel' ]]; then
            is_listen='listen: "127.0.0.1"'
        fi
        
        local safe_remark="${custom_remark//\//_}"
        if [[ -z "$safe_remark" ]]; then
            safe_remark="luopojunzi"
        fi

        if [[ $host ]]; then
            is_config_name=$2-${safe_remark}-${host}.json
            if [[ $is_new_protocol != 'CFtunnel' ]]; then
                is_listen='listen: "127.0.0.1"'
            fi
        else
            is_config_name=$2-${safe_remark}-${port}.json
        fi
        
        is_json_file=$is_conf_dir/$is_config_name
        
        if [[ $is_change || ! $json_str ]]; then
            get protocol $2
        fi
        if [[ $net == "reality" ]]; then
            is_add_public_key=",outbounds:[{type:\"direct\"},{tag:\"public_key_$is_public_key\",type:\"direct\"}]"
        fi
        is_new_json=$(jq "{inbounds:[{tag:\"$is_config_name\",type:\"$is_protocol\",$is_listen,listen_port:$port,$json_str}]$is_add_public_key}" <<<{})
        if [[ $is_test_json ]]; then
            return 
        fi
        if [[ $is_gen ]]; then
            msg
            jq <<<$is_new_json
            msg
            return
        fi
        if [[ $is_config_file ]]; then
            is_no_del_msg=1
            del $is_config_file
        fi
        
        cat <<<$is_new_json >$is_json_file
        
        if [[ $is_new_protocol == 'CFtunnel' && $cf_token ]]; then
            install_cloudflared
            create_cftunnel_service "$cf_token" "$port"
        fi
        
        if [[ $is_new_install ]]; then
            create config.json
        fi
        if [[ $is_caddy && $host && ! $is_no_auto_tls ]]; then
            create caddy $net
        fi
        manage restart &
        ;;
    client)
        is_tls=tls
        is_client=1
        get info $2
        if [[ ! $is_client_id_json ]]; then
            err "($is_config_name) 不支持生成客户端配置."
        fi
        is_new_json=$(jq '{outbounds:[{tag:'\"$is_config_name\"',protocol:'\"$is_protocol\"','"$is_client_id_json"','"$is_stream"'}]}' <<<{})
        msg
        jq <<<$is_new_json
        msg
        ;;
    caddy)
        load caddy.sh
        if [[ $is_install_caddy ]]; then
            caddy_config new
        fi
        if [[ ! $(grep "$is_caddy_conf" $is_caddyfile) ]]; then
            msg "import $is_caddy_conf/*.conf" >>$is_caddyfile
        fi
        if [[ ! -d $is_caddy_conf ]]; then
            mkdir -p $is_caddy_conf
        fi
        caddy_config $2
        manage restart caddy &
        ;;
    config.json)
        is_log='log:{output:"/var/log/'$is_core'/access.log",level:"info","timestamp":true}'
        is_dns='dns:{}'
        is_ntp='ntp:{"enabled":true,"server":"time.apple.com"},'
        if [[ -f $is_config_json ]]; then
            if [[ $(jq .ntp.enabled $is_config_json) != "true" ]]; then
                is_ntp=
            fi
        else
            if [[ ! $is_ntp_on ]]; then
                is_ntp=
            fi
        fi
        is_outbounds='outbounds:[{tag:"direct",type:"direct"}]'
        is_server_config_json=$(jq "{$is_log,$is_dns,$is_ntp$is_outbounds}" <<<{})
        cat <<<$is_server_config_json >$is_config_json
        manage restart &
        ;;
    esac
}

change() {
    is_change=1
    is_dont_show_info=1
    if [[ $2 ]]; then
        case ${2,,} in
        full)
            is_change_id=full
            ;;
        new)
            is_change_id=0
            ;;
        port)
            is_change_id=1
            ;;
        host)
            is_change_id=2
            ;;
        path)
            is_change_id=3
            ;;
        pass | passwd | password)
            is_change_id=4
            ;;
        id | uuid)
            is_change_id=5
            ;;
        ssm | method | ss-method | ss_method)
            is_change_id=6
            ;;
        dda | door-addr | door_addr)
            is_change_id=7
            ;;
        ddp | door-port | door_port)
            is_change_id=8
            ;;
        key | publickey | privatekey)
            is_change_id=9
            ;;
        sni | servername | servernames)
            is_change_id=10
            ;;
        web | proxy-site)
            is_change_id=11
            ;;
        *)
            if [[ $is_try_change ]]; then
                return
            fi
            err "无法识别 ($2) 更改类型."
            ;;
        esac
    fi
    if [[ $is_try_change ]]; then
        return
    fi
    if [[ $is_dont_auto_exit ]]; then
        get info $1
    else
        if [[ $is_change_id ]]; then
            is_change_msg=${change_list[$is_change_id]}
            if [[ $is_change_id == 'full' ]]; then
                if [[ $3 ]]; then
                    is_change_msg="更改多个参数"
                else
                    is_change_msg=
                fi
            fi
            if [[ $is_change_msg ]]; then
                _green "\n快速执行: $is_change_msg"
            fi
        fi
        info $1
        if [[ $is_auto_get_config ]]; then
            msg "\n自动选择: $is_config_file"
        fi
    fi
    
    is_old_net=$net
    if [[ $is_tcp_http ]]; then
        net=http
    fi
    if [[ $host ]]; then
        net=$is_protocol-$net-tls
    fi
    if [[ $is_reality && $net_type =~ 'http' ]]; then
        net=rh2
    fi

    if [[ $3 == 'auto' ]]; then
        is_auto=1
    fi
    is_dont_show_info=
    if [[ ! $is_change_id ]]; then
        ask set_change_list
        is_change_id=${is_can_change[$REPLY - 1]}
    fi
    
    case $is_change_id in
    full)
        add $net ${@:3}
        ;;
    0)
        is_set_new_protocol=1
        add ${@:3}
        ;;
    1)
        is_new_port=$3
        if [[ $host && ! $is_caddy || $is_no_auto_tls ]]; then
            err "($is_config_file) 不支持更改端口, 因为没啥意义."
        fi
        if [[ $is_new_port && ! $is_auto ]]; then
            if [[ ! $(is_test port $is_new_port) ]]; then
                err "请输入正确的端口, 可选(1-65535)"
            fi
            if [[ $is_new_port != 443 && $(is_test port_used $is_new_port) ]]; then
                err "无法使用 ($is_new_port) 端口"
            fi
        fi
        if [[ $is_auto ]]; then
            get_port
            is_new_port=$tmp_port
        fi
        if [[ ! $is_new_port ]]; then
            ask string is_new_port "请输入新端口:"
        fi
        if [[ $is_caddy && $host ]]; then
            net=$is_old_net
            is_https_port=$is_new_port
            load caddy.sh
            caddy_config $net
            manage restart caddy &
            info
        else
            add $net $is_new_port
        fi
        ;;
    2)
        is_new_host=$3
        if [[ ! $host ]]; then
            err "($is_config_file) 不支持更改域名."
        fi
        if [[ ! $is_new_host ]]; then
            ask string is_new_host "请输入新域名:"
        fi
        old_host=$host
        add $net $is_new_host
        ;;
    3)
        is_new_path=$3
        if [[ ! $path ]]; then
            err "($is_config_file) 不支持更改路径."
        fi
        if [[ $is_auto ]]; then
            get_uuid
            is_new_path=/$tmp_uuid
        fi
        if [[ ! $is_new_path ]]; then
            ask string is_new_path "请输入新路径:"
        fi
        add $net auto auto $is_new_path
        ;;
    4)
        is_new_pass=$3
        if [[ $ss_password || $password ]]; then
            if [[ $is_auto ]]; then
                get_uuid
                is_new_pass=$tmp_uuid
                if [[ $ss_password ]]; then
                    is_new_pass=$(get ss2022)
                fi
            fi
        else
            err "($is_config_file) 不支持更改密码."
        fi
        if [[ ! $is_new_pass ]]; then
            ask string is_new_pass "请输入新密码:"
        fi
        password=$is_new_pass
        ss_password=$is_new_pass
        is_socks_pass=$is_new_pass
        add $net
        ;;
    5)
        is_new_uuid=$3
        if [[ ! $uuid ]]; then
            err "($is_config_file) 不支持更改 UUID."
        fi
        if [[ $is_auto ]]; then
            get_uuid
            is_new_uuid=$tmp_uuid
        fi
        if [[ ! $is_new_uuid ]]; then
            ask string is_new_uuid "请输入新 UUID:"
        fi
        add $net auto $is_new_uuid
        ;;
    6)
        is_new_method=$3
        if [[ $net != 'ss' ]]; then
            err "($is_config_file) 不支持更改加密方式."
        fi
        if [[ $is_auto ]]; then
            is_new_method=$is_random_ss_method
        fi
        if [[ ! $is_new_method ]]; then
            ask set_ss_method
            is_new_method=$ss_method
        fi
        add $net auto auto $is_new_method
        ;;
    7)
        is_new_door_addr=$3
        if [[ $net != 'direct' ]]; then
            err "($is_config_file) 不支持更改目标地址."
        fi
        if [[ ! $is_new_door_addr ]]; then
            ask string is_new_door_addr "请输入新的目标地址:"
        fi
        door_addr=$is_new_door_addr
        add $net
        ;;
    8)
        is_new_door_port=$3
        if [[ $net != 'direct' ]]; then
            err "($is_config_file) 不支持更改目标端口."
        fi
        if [[ ! $is_new_door_port ]]; then
            ask string door_port "请输入新的目标端口:"
            is_new_door_port=$door_port
        fi
        add $net auto auto $is_new_door_port
        ;;
    9)
        is_new_private_key=$3
        is_new_public_key=$4
        if [[ ! $is_reality ]]; then
            err "($is_config_file) 不支持更改密钥."
        fi
        if [[ $is_auto ]]; then
            get_pbk
            add $net
        else
            if [[ $is_new_private_key && ! $is_new_public_key ]]; then
                err "无法找到 Public key."
            fi
            if [[ ! $is_new_private_key ]]; then
                ask string is_new_private_key "请输入新 Private key:"
            fi
            if [[ ! $is_new_public_key ]]; then
                ask string is_new_public_key "请输入新 Public key:"
            fi
            if [[ $is_new_private_key == $is_new_public_key ]]; then
                err "Private key 和 Public key 不能一样."
            fi
            is_tmp_json=$is_conf_dir/$is_config_file-$uuid
            cp -f $is_conf_dir/$is_config_file $is_tmp_json
            sed -i s#$is_private_key #$is_new_private_key# $is_tmp_json
            $is_core_bin check -c $is_tmp_json &>/dev/null
            if [[ $? != 0 ]]; then
                is_key_err=1
                is_key_err_msg="Private key 无法通过测试."
            fi
            sed -i s#$is_new_private_key #$is_new_public_key# $is_tmp_json
            $is_core_bin check -c $is_tmp_json &>/dev/null
            if [[ $? != 0 ]]; then
                is_key_err=1
                is_key_err_msg+="Public key 无法通过测试."
            fi
            rm $is_tmp_json
            if [[ $is_key_err ]]; then
                err $is_key_err_msg
            fi
            is_private_key=$is_new_private_key
            is_public_key=$is_new_public_key
            is_test_json=
            add $net
        fi
        ;;
    10)
        is_new_servername=$3
        if [[ ! $is_reality ]]; then
            err "($is_config_file) 不支持更改 serverName."
        fi
        if [[ $is_auto ]]; then
            is_new_servername=$is_random_servername
        fi
        if [[ ! $is_new_servername ]]; then
            ask string is_new_servername "请输入新的 serverName:"
        fi
        is_servername=$is_new_servername
        add $net
        ;;
    11)
        is_new_proxy_site=$3
        if [[ ! $is_caddy && ! $host ]]; then
            err "($is_config_file) 不支持更改伪装网站."
        fi
        if [[ ! -f $is_caddy_conf/${host}.conf.add ]]; then
            err "无法配置伪装网站."
        fi
        if [[ ! $is_new_proxy_site ]]; then
            ask string is_new_proxy_site "请输入新的伪装网站 (例如 example.com):"
        fi
        proxy_site=$(sed 's#^.*//##;s#/$##' <<<$is_new_proxy_site)
        load caddy.sh
        caddy_config proxy
        manage restart caddy &
        msg "\n已更新伪装网站为: $(_green $proxy_site) \n"
        ;;
    12)
        if [[ ! $is_socks_user ]]; then
            err "($is_config_file) 不支持更改用户名 (Username)."
        fi
        ask string is_socks_user "请输入新用户名 (Username):"
        add $net
        ;;
    esac
}

del() {
    is_dont_get_ip=1
    if [[ $is_conf_dir_empty ]]; then
        return 
    fi
    if [[ ! $is_config_file ]]; then
        get info $1
    fi
    if [[ $is_config_file ]]; then
        if [[ $is_main_start && ! $is_no_del_msg ]]; then
            msg "\n是否删除配置文件?: $is_config_file"
            pause
        fi
        rm -rf $is_conf_dir/"$is_config_file"
        
        if [[ $is_config_file =~ "CFtunnel" ]]; then
            local del_port=$(echo $is_config_file | grep -oE "[0-9]+")
            if [[ $del_port ]]; then
                systemctl disable --now cftunnel-${del_port}.service &>/dev/null
                rm -f /lib/systemd/system/cftunnel-${del_port}.service
                systemctl daemon-reload
                msg "✅ 已清理对应的 CFtunnel 穿透守护服务."
            fi
        fi
        
        if [[ ! $is_new_json ]]; then
            manage restart &
        fi
        if [[ ! $is_no_del_msg ]]; then
            _green "\n已删除: $is_config_file\n"
        fi

        if [[ $is_caddy ]]; then
            is_del_host=$host
            if [[ $is_change ]]; then
                if [[ ! $old_host ]]; then
                    return
                fi
                is_del_host=$old_host
            fi
            if [[ $is_del_host && $host != $old_host && -f $is_caddy_conf/$is_del_host.conf ]]; then
                rm -rf $is_caddy_conf/$is_del_host.conf $is_caddy_conf/$is_del_host.conf.add
                if [[ ! $is_new_json ]]; then
                    manage restart caddy &
                fi
            fi
        fi
    fi
    if [[ ! $(ls $is_conf_dir | grep .json) && ! $is_change ]]; then
        warn "当前配置目录为空! 因为你刚刚删除了最后一个配置文件."
        is_conf_dir_empty=1
    fi
    unset is_dont_get_ip
    if [[ $is_dont_auto_exit ]]; then
        unset is_config_file
    fi
}

get() {
    case $1 in
    addr)
        is_addr=$host
        if [[ ! $is_addr ]]; then
            get_ip
            is_addr=$ip
            if [[ $(grep ":" <<<$ip) ]]; then
                is_addr="[$ip]"
            fi
        fi
        ;;
    new)
        if [[ ! $host ]]; then
            get_ip
        fi
        if [[ ! $port ]]; then
            get_port
            port=$tmp_port
        fi
        if [[ ! $uuid ]]; then
            get_uuid
            uuid=$tmp_uuid
        fi
        ;;
    file)
        is_file_str=$2
        if [[ ! $is_file_str ]]; then
            is_file_str='.json$'
        fi
        readarray -t is_all_json <<<"$(ls $is_conf_dir | grep -E -i "$is_file_str" | sed '/dynamic-port-.*-link/d' | head -233)" 
        if [[ ! $is_all_json ]]; then
            err "无法找到相关的配置文件: $2"
        fi
        if [[ ${#is_all_json[@]} -eq 1 ]]; then
            is_config_file=$is_all_json
            is_auto_get_config=1
        fi
        if [[ ! $is_config_file ]]; then
            if [[ $is_dont_auto_exit ]]; then
                return
            fi
            ask get_config_file
        fi
        ;;
    info)
        get file $2
        if [[ $is_config_file ]]; then
            is_json_str=$(cat $is_conf_dir/"$is_config_file" | sed s#//.*##)
            is_json_data=$(jq '(.inbounds[0]|.type,.listen_port,(.users[0]|.uuid,.password,.username),.method,.password,.override_port,.override_address,(.transport|.type,.path,.headers.host),(.tls|.server_name,.reality.private_key)),(.outbounds[1].tag)' <<<$is_json_str)
            if [[ $? != 0 ]]; then
                err "无法读取此文件: $is_config_file"
            fi
            is_up_var_set=(null is_protocol port uuid password username ss_method ss_password door_port door_addr net_type path host is_servername is_private_key is_public_key)
            if [[ $is_debug ]]; then
                msg "\n------------- debug: $is_config_file -------------"
            fi
            i=0
            for v in $(sed 's/""/null/g;s/"//g' <<<"$is_json_data"); do
                ((i++))
                if [[ $is_debug ]]; then
                    msg "$i-${is_up_var_set[$i]}: $v"
                fi
                export ${is_up_var_set[$i]}="${v}"
            done
            for v in ${is_up_var_set[@]}; do
                if [[ ${!v} == 'null' ]]; then
                    unset $v
                fi
            done

            if [[ $is_private_key ]]; then
                is_reality=1
                net_type+=reality
                is_public_key=${is_public_key/public_key_/}
            fi
            is_socks_user=$username
            is_socks_pass=$password

            is_config_name=$is_config_file

            if [[ $is_caddy && $host && -f $is_caddy_conf/$host.conf ]]; then
                is_tmp_https_port=$(grep -E -o "$host:[1-9][0-9]?+" $is_caddy_conf/$host.conf | sed s/.*://)
            fi
            if [[ $host && ! -f $is_caddy_conf/$host.conf ]]; then
                is_no_auto_tls=1
            fi
            if [[ $is_tmp_https_port ]]; then
                is_https_port=$is_tmp_https_port
            fi
            if [[ $is_client && $host ]]; then
                port=$is_https_port
            fi
            get protocol $is_protocol-$net_type
        fi
        ;;
    protocol)
        get addr
        is_lower=${2,,}
        net=
        is_users="users:[{uuid:\"$uuid\"}]"
        is_tls_json='tls:{enabled:true,alpn:["h3"],key_path:"'$is_tls_key'",certificate_path:"'$is_tls_cer'"}'
        case $is_lower in
        vmess*)
            is_protocol=vmess
            if [[ $is_lower =~ "tcp" || ! $net_type && $is_up_var_set ]]; then
                net=tcp
                json_str=$is_users
            fi
            ;;
        vless*)
            is_protocol=vless
            ;;
        anytls)
            is_protocol=vless
            net=reality
            if [[ ! $is_servername ]]; then
                is_servername=$is_random_servername
            fi
            if [[ ! $is_private_key ]]; then
                get_pbk
            fi
            is_json_add="tls:{enabled:true,server_name:\"$is_servername\",reality:{enabled:true,handshake:{server:\"$is_servername\",server_port:443},private_key:\"$is_private_key\",short_id:[\"\"]}}"
            is_users=${is_users/uuid/flow:\"xtls-rprx-vision\",uuid}
            json_str="$is_users,$is_json_add"
            ;;
        cftunnel)
            is_protocol=vless
            net=ws
            host="cftunnel.com"
            if [[ ! $path ]]; then
                path="/$uuid"
            fi
            is_path_host_json=",path:\"$path\",headers:{host:\"$host\"}"
            is_json_add="transport:{type:\"$net\"$is_path_host_json,early_data_header_name:\"Sec-WebSocket-Protocol\"}"
            json_str="$is_users,$is_json_add"
            ;;
        tuic*)
            net=tuic
            is_protocol=$net
            if [[ ! $password ]]; then
                password=$uuid
            fi
            is_users="users:[{uuid:\"$uuid\",password:\"$password\"}]"
            json_str="$is_users,congestion_control:\"bbr\",$is_tls_json"
            ;;
        trojan*)
            is_protocol=trojan
            if [[ ! $password ]]; then
                password=$uuid
            fi
            is_users="users:[{password:\"$password\"}]"
            if [[ ! $host ]]; then
                net=trojan
                json_str="$is_users,${is_tls_json/alpn\:\[\"h3\"\],/}"
            fi
            ;;
        hysteria2*)
            net=hysteria2
            is_protocol=$net
            if [[ ! $password ]]; then
                password=$uuid
            fi
            json_str="users:[{password:\"$password\"}],$is_tls_json"
            ;;
        shadowsocks*)
            net=ss
            is_protocol=shadowsocks
            if [[ ! $ss_method ]]; then
                ss_method=$is_random_ss_method
            fi
            if [[ ! $ss_password ]]; then
                ss_password=$uuid
                if [[ $(grep 2022 <<<$ss_method) ]]; then
                    ss_password=$(get ss2022)
                fi
            fi
            json_str="method:\"$ss_method\",password:\"$ss_password\""
            ;;
        direct*)
            net=direct
            is_protocol=$net
            json_str="override_port:$door_port,override_address:\"$door_addr\""
            ;;
        socks*)
            net=socks
            is_protocol=$net
            if [[ ! $is_socks_user ]]; then
                is_socks_user=luopojunzi
            fi
            if [[ ! $is_socks_pass ]]; then
                is_socks_pass=$uuid
            fi
            json_str="users:[{username: \"$is_socks_user\", password: \"$is_socks_pass\"}]"
            ;;
        *)
            err "无法识别协议: $is_config_file"
            ;;
        esac
        if [[ $net ]]; then
            return
        fi
        if [[ $host && $is_lower =~ "tls" ]]; then
            if [[ ! $path ]]; then
                path="/$uuid"
            fi
            is_path_host_json=",path:\"$path\",headers:{host:\"$host\"}"
        fi
        case $is_lower in
        *quic*)
            net=quic
            is_json_add="$is_tls_json,transport:{type:\"$net\"}"
            ;;
        *ws*)
            net=ws
            is_json_add="transport:{type:\"$net\"$is_path_host_json,early_data_header_name:\"Sec-WebSocket-Protocol\"}"
            ;;
        *reality*)
            net=reality
            if [[ ! $is_servername ]]; then
                is_servername=$is_random_servername
            fi
            if [[ ! $is_private_key ]]; then
                get_pbk
            fi
            is_json_add="tls:{enabled:true,server_name:\"$is_servername\",reality:{enabled:true,handshake:{server:\"$is_servername\",server_port:443},private_key:\"$is_private_key\",short_id:[\"\"]}}"
            if [[ $is_lower =~ "http" ]]; then
                is_json_add="$is_json_add,transport:{type:\"http\"}"
            else
                is_users=${is_users/uuid/flow:\"xtls-rprx-vision\",uuid}
            fi
            ;;
        *http* | *h2*)
            net=http
            if [[ $is_lower =~ "up" ]]; then
                net=httpupgrade
            fi
            is_json_add="transport:{type:\"$net\"$is_path_host_json}"
            if [[ $is_lower =~ "h2" || ! $is_lower =~ "httpupgrade" && $host ]]; then
                net=h2
                is_json_add="${is_tls_json/alpn\:\[\"h3\"\],/},$is_json_add"
            fi
            ;;
        esac
        json_str="$is_users,$is_json_add"
        ;;
    host-test)
        if [[ $is_no_auto_tls || $is_gen || $is_dont_test_host ]]; then
            return
        fi
        get_ip
        get ping
        if [[ ! $(grep $ip <<<$is_host_dns) ]]; then
            msg "\n请将 ($(_red_bg $host)) 解析到 ($(_red_bg $ip))"
            msg "\n如果使用 Cloudflare, 在 DNS 那; 关闭 (Proxy status / 代理状态), 即是 (DNS only / 仅限 DNS)"
            ask string y "我已经确定解析 [y]:"
            get ping
            if [[ ! $(grep $ip <<<$is_host_dns) ]]; then
                _cyan "\n测试结果: $is_host_dns"
                err "域名 ($host) 没有解析到 ($ip)"
            fi
        fi
        ;;
    ssss | ss2022)
        if [[ $(grep 128 <<<$ss_method) ]]; then
            $is_core_bin generate rand 16 --base64
        else
            $is_core_bin generate rand 32 --base64
        fi
        ;;
    ping)
        is_dns_type="a"
        if [[ $(grep ":" <<<$ip) ]]; then
            is_dns_type="aaaa"
        fi
        is_host_dns=$(_wget -qO- --header="accept: application/dns-json" "https://one.one.one.one/dns-query?name=$host&type=$is_dns_type")
        ;;
    install-caddy)
        _green "\n安装 Caddy 实现自动配置 TLS.\n"
        load download.sh
        download caddy
        load systemd.sh
        install_service caddy &>/dev/null
        is_caddy=1
        _green "安装 Caddy 成功.\n"
        ;;
    reinstall)
        is_install_sh=$(cat $is_sh_dir/install.sh)
        uninstall
        bash <<<$is_install_sh
        ;;
    test-run)
        systemctl list-units --full -all &>/dev/null
        if [[ $? != 0 ]]; then
            _yellow "\n无法执行测试, 请检查 systemctl 状态.\n"
            return
        fi
        is_no_manage_msg=1
        if [[ ! $(pgrep -f $is_core_bin) ]]; then
            _yellow "\n测试运行 $is_core_name ..\n"
            manage start &>/dev/null
            if [[ $is_run_fail == $is_core ]]; then
                _red "$is_core_name 运行失败信息:"
                $is_core_bin run -c $is_config_json -C $is_conf_dir
            else
                _green "\n测试通过, 已启动 $is_core_name ..\n"
            fi
        else
            _green "\n$is_core_name 正在运行, 跳过测试\n"
        fi
        if [[ $is_caddy ]]; then
            if [[ ! $(pgrep -f $is_caddy_bin) ]]; then
                _yellow "\n测试运行 Caddy ..\n"
                manage start caddy &>/dev/null
                if [[ $is_run_fail == 'caddy' ]]; then
                    _red "Caddy 运行失败信息:"
                    $is_caddy_bin run --config $is_caddyfile
                else
                    _green "\n测试通过, 已启动 Caddy ..\n"
                fi
            else
                _green "\nCaddy 正在运行, 跳过测试\n"
            fi
        fi
        ;;
    esac
}

info() {
    if [[ ! $is_protocol ]]; then
        get info $1
    fi
    is_color=44

    if [[ -z "$custom_remark" ]]; then
        local tmp_name="${is_config_name%.json}"
        local stripped_port="${tmp_name%-[0-9]*}"
        custom_remark="${stripped_port#*-}"
        if [[ -z "$custom_remark" || "$custom_remark" == "$is_protocol" ]]; then
            custom_remark="luopojunzi"
        fi
    fi

    if [[ $is_config_name =~ "CFtunnel" ]]; then
        is_color=45
        is_can_change=(0 5)
        is_info_show=(0 1 2 3 4 6 7 8)
        is_info_str=(vless "你的CF绑定域名(需修改)" "443" $uuid ws "你的CF绑定域名(需修改)" "/$uuid" tls)
        is_url="vless://$uuid@你的CF绑定域名:443?encryption=none&security=tls&type=ws&host=你的CF绑定域名&path=/$uuid#$custom_remark"
        net="cftunnel_handled"
    fi
    
    if [[ $is_config_name =~ "AnyTLS" ]]; then
        net="reality"
    fi

    case $net in
    ws | tcp | h2 | quic | http*)
        if [[ $host ]]; then
            is_color=45
            is_can_change=(0 1 2 3 5)
            is_info_show=(0 1 2 3 4 6 7 8)
            if [[ $is_protocol == 'vmess' ]]; then
                is_vmess_url=$(jq -c "{v:2,ps:\"$custom_remark\",add:\"$is_addr\",port:\"$is_https_port\",id:\"$uuid\",aid:\"0\",net:\"$net\",host:\"$host\",path:\"$path\",tls:\"tls\"}" <<<{})
                is_url=vmess://$(echo -n $is_vmess_url | base64 -w 0)
            else
                if [[ $is_protocol == "trojan" ]]; then
                    uuid=$password
                    is_can_change=(0 1 2 3 4)
                    is_info_show=(0 1 2 10 4 6 7 8)
                fi
                is_url="$is_protocol://$uuid@$is_addr:$is_https_port?encryption=none&security=tls&type=$net&host=$host&path=$path#$custom_remark"
            fi
            if [[ $is_caddy ]]; then
                is_can_change+=(11)
            fi
            is_info_str=($is_protocol $is_addr $is_https_port $uuid $net $host $path 'tls')
        else
            is_type=none
            is_can_change=(0 1 5)
            is_info_show=(0 1 2 3 4)
            is_info_str=($is_protocol $is_addr $port $uuid $net)
            if [[ $net == "http" ]]; then
                net=tcp
                is_type=http
                is_tcp_http=1
                is_info_show+=(5)
                is_info_str=(${is_info_str[@]/http/tcp http})
            fi
            if [[ $net == "quic" ]]; then
                is_insecure=1
                is_info_show+=(8 9 20)
                is_info_str+=(tls h3 true)
                is_quic_add=",tls:\"tls\",alpn:\"h3\""
            fi
            is_vmess_url=$(jq -c "{v:2,ps:\"$custom_remark\",add:\"$is_addr\",port:\"$port\",id:\"$uuid\",aid:\"0\",net:\"$net\",type:\"$is_type\"$is_quic_add}" <<<{})
            is_url=vmess://$(echo -n $is_vmess_url | base64 -w 0)
        fi
        ;;
    ss)
        is_can_change=(0 1 4 6)
        is_info_show=(0 1 2 10 11)
        is_url="ss://$(echo -n ${ss_method}:${ss_password} | base64 -w 0)@${is_addr}:${port}#$custom_remark"
        is_info_str=($is_protocol $is_addr $port $ss_password $ss_method)
        ;;
    trojan)
        is_insecure=1
        is_can_change=(0 1 4)
        is_info_show=(0 1 2 10 4 8 20)
        is_url="$is_protocol://$password@$is_addr:$port?type=tcp&security=tls&allowInsecure=1#$custom_remark"
        is_info_str=($is_protocol $is_addr $port $password tcp tls true)
        ;;
    hy*)
        is_can_change=(0 1 4)
        is_info_show=(0 1 2 10 8 9 20)
        is_url="$is_protocol://$password@$is_addr:$port?alpn=h3&insecure=1#$custom_remark"
        is_info_str=($is_protocol $is_addr $port $password tls h3 true)
        ;;
    tuic)
        is_insecure=1
        is_can_change=(0 1 4 5)
        is_info_show=(0 1 2 3 10 8 9 20 21)
        is_url="$is_protocol://$uuid:$password@$is_addr:$port?alpn=h3&allow_insecure=1&congestion_control=bbr#$custom_remark"
        is_info_str=($is_protocol $is_addr $port $uuid $password tls h3 true bbr)
        ;;
    reality)
        is_color=41
        is_can_change=(0 1 5 9 10)
        is_info_show=(0 1 2 3 15 4 8 16 17 18)
        is_flow=xtls-rprx-vision
        is_net_type=tcp
        if [[ $net_type =~ "http" || ${is_new_protocol,,} =~ "http" ]]; then
            is_flow=
            is_net_type=h2
            is_info_show=(${is_info_show[@]/15/})
        fi
        is_info_str=($is_protocol $is_addr $port $uuid $is_flow $is_net_type reality $is_servername chrome $is_public_key)
        is_url="$is_protocol://$uuid@$is_addr:$port?encryption=none&security=reality&flow=$is_flow&type=$is_net_type&sni=$is_servername&pbk=$is_public_key&fp=chrome#$custom_remark"
        ;;
    direct)
        is_can_change=(0 1 7 8)
        is_info_show=(0 1 2 13 14)
        is_info_str=($is_protocol $is_addr $port $door_addr $door_port)
        ;;
    socks)
        is_can_change=(0 1 12 4)
        is_info_show=(0 1 2 19 10)
        is_info_str=($is_protocol $is_addr $port $is_socks_user $is_socks_pass)
        is_url="socks://$(echo -n ${is_socks_user}:${is_socks_pass} | base64 -w 0)@${is_addr}:${port}#$custom_remark"
        ;;
    esac
    
    if [[ $is_show_all ]]; then
        echo -e "\e[93m[${is_config_name}]\e[0m 协议: \e[96m${is_protocol}\e[0m | 端口: \e[92m${port}\e[0m"
        echo -e "\e[4;${is_color}m${is_url}\e[0m"
        echo -e "\e[90m-----------------------------------------------------\e[0m"
        return
    fi
    
    if [[ $is_dont_show_info || $is_gen || $is_dont_auto_exit ]]; then
        return 
    fi
    
    msg "-------------- $is_config_name -------------"
    for ((i = 0; i < ${#is_info_show[@]}; i++)); do
        a=${info_list[${is_info_show[$i]}]}
        if [[ ${#a} -eq 11 || ${#a} -ge 13 ]]; then
            tt='\t'
        else
            tt='\t\t'
        fi
        msg "$a $tt= \e[${is_color}m${is_info_str[$i]}\e[0m"
    done
    if [[ $is_new_install ]]; then
        warn "首次安装请查看项目文档: $(msg_ul https://github.com/LuoPoJunZi/Sing-box-LPMG)"
    fi
    if [[ $is_url ]]; then
        msg "------------- ${info_list[12]} -------------"
        msg "\e[4;${is_color}m${is_url}\e[0m"
        if [[ $is_insecure ]]; then
            warn "某些客户端如(V2rayN 等)导入URL需手动将: 跳过证书验证(allowInsecure) 设置为 true, 或打开: 允许不安全的连接"
        fi
    fi
    if [[ $is_no_auto_tls ]]; then
        msg "------------- no-auto-tls INFO -------------"
        msg "端口(port): $port"
        msg "路径(path): $path"
        msg "\e[41m帮助(help)\e[0m: $(msg_ul https://github.com/LuoPoJunZi/Sing-box-LPMG)"
    fi
    footer_msg
}

show_all_nodes() {
    is_dont_auto_exit=1
    is_show_all=1
    clear
    echo -e "\e[96m=====================================================\e[0m"
    echo -e "              Sing-box-LPMG 节点配置总览"
    echo -e "\e[96m=====================================================\e[0m\n"
    
    local config_count=0
    for v in $(ls $is_conf_dir | grep .json$ | sed '/dynamic-port-.*-link/d'); do
        ((config_count++))
        unset is_protocol port uuid password net is_url custom_remark is_json_str
        get info $v > /dev/null 2>&1
        info $v
    done
    
    if [[ $config_count -eq 0 ]]; then
        echo -e " \e[91m目前没有找到任何节点配置，请先添加配置。\e[0m\n"
    else
        echo -e "\n \e[92m共为您列出 $config_count 个节点链接，请直接复制上方链接使用。\e[0m\n"
    fi
    
    is_show_all=
    is_dont_auto_exit=
    pause
}

add() {
    unset custom_remark
    is_lower=${1,,}
    if [[ $is_lower ]]; then
        case $is_lower in
        ws | tcp | quic | http)
            is_new_protocol=VMess-${is_lower^^}
            ;;
        wss | h2 | hu | vws | vh2 | vhu | tws | th2 | thu)
            is_new_protocol=$(sed -E "s/^V/VLESS-/;s/^T/Trojan-/;/^(W|H)/{s/^/VMess-/};s/WSS/WS/;s/HU/HTTPUpgrade/" <<<${is_lower^^})-TLS
            ;;
        r | reality)
            is_new_protocol=VLESS-REALITY
            ;;
        rh2)
            is_new_protocol=VLESS-HTTP2-REALITY
            ;;
        anytls)
            is_new_protocol=AnyTLS
            ;;
        cftunnel)
            is_new_protocol=CFtunnel
            ;;
        ss)
            is_new_protocol=Shadowsocks
            ;;
        door | direct)
            is_new_protocol=Direct
            ;;
        tuic)
            is_new_protocol=TUIC
            ;;
        hy | hy2 | hysteria*)
            is_new_protocol=Hysteria2
            ;;
        trojan)
            is_new_protocol=Trojan
            ;;
        socks)
            is_new_protocol=Socks
            ;;
        *)
            for v in ${protocol_list[@]}; do
                if [[ $(grep -E -i "^$is_lower$" <<<$v) ]]; then
                    is_new_protocol=$v
                    break
                fi
            done

            if [[ ! $is_new_protocol ]]; then
                err "无法识别 ($1), 请使用: $is_core add [protocol] [args... | auto]"
            fi
            ;;
        esac
    fi

    if [[ ! $is_new_protocol ]]; then
        ask set_protocol
    fi

    case ${is_new_protocol,,} in
    *-tls)
        is_use_tls=1
        is_use_host=$2
        is_use_uuid=$3
        is_use_path=$4
        is_add_opts="[host] [uuid] [/path]"
        ;;
    vmess* | tuic*)
        is_use_port=$2
        is_use_uuid=$3
        is_add_opts="[port] [uuid]"
        ;;
    trojan* | hysteria*)
        is_use_port=$2
        is_use_pass=$3
        is_add_opts="[port] [password]"
        ;;
    *reality* | anytls)
        is_reality=1
        is_use_port=$2
        is_use_uuid=$3
        is_use_servername=$4
        is_add_opts="[port] [uuid] [sni]"
        ;;
    cftunnel)
        is_use_port=$2
        is_use_uuid=$3
        is_use_cf_token=$4
        is_add_opts="[port] [uuid] [cf_token]"
        ;;
    shadowsocks)
        is_use_port=$2
        is_use_pass=$3
        is_use_method=$4
        is_add_opts="[port] [password] [method]"
        ;;
    direct)
        is_use_port=$2
        is_use_door_addr=$3
        is_use_door_port=$4
        is_add_opts="[port] [remote_addr] [remote_port]"
        ;;
    socks)
        is_socks=1
        is_use_port=$2
        is_use_socks_user=$3
        is_use_socks_pass=$4
        is_add_opts="[port] [username] [password]"
        ;;
    esac

    if [[ $1 && ! $is_change ]]; then
        msg "\n使用协议: $is_new_protocol"
        is_err_tips="\n\n请使用: $(_green $is_core add $1 $is_add_opts) 来添加 $is_new_protocol 配置"
    fi

    if [[ $is_set_new_protocol ]]; then
        case $is_old_net in
        h2 | ws | httpupgrade)
            old_host=$host
            if [[ ! $is_use_tls ]]; then
                unset host is_no_auto_tls
            fi
            ;;
        reality)
            net_type=
            if [[ ! $(grep -i reality <<<$is_new_protocol) ]]; then
                is_reality=
            fi
            ;;
        ss)
            if [[ $(is_test uuid $ss_password) ]]; then
                uuid=$ss_password
            fi
            ;;
        esac
        if [[ ! $(is_test uuid $uuid) ]]; then
            uuid=
        fi
        if [[ $(is_test uuid $password) ]]; then
            uuid=$password
        fi
    fi

    if [[ $is_no_auto_tls && ! $is_use_tls ]]; then
        err "$is_new_protocol 不支持手动配置 tls."
    fi

    if [[ $2 ]]; then
        for v in is_use_port is_use_uuid is_use_host is_use_path is_use_pass is_use_method is_use_door_addr is_use_door_port; do
            if [[ ${!v} == 'auto' ]]; then
                unset $v
            fi
        done

        if [[ $is_use_port ]]; then
            if [[ ! $(is_test port ${is_use_port}) ]]; then
                err "($is_use_port) 不是一个有效的端口. $is_err_tips"
            fi
            if [[ $(is_test port_used $is_use_port) && ! $is_gen ]]; then
                err "无法使用 ($is_use_port) 端口. $is_err_tips"
            fi
            port=$is_use_port
        fi
        if [[ $is_use_door_port ]]; then
            if [[ ! $(is_test port ${is_use_door_port}) ]]; then
                err "(${is_use_door_port}) 不是一个有效的目标端口. $is_err_tips"
            fi
            door_port=$is_use_door_port
        fi
        if [[ $is_use_uuid ]]; then
            if [[ ! $(is_test uuid $is_use_uuid) ]]; then
                err "($is_use_uuid) 不是一个有效的 UUID. $is_err_tips"
            fi
            uuid=$is_use_uuid
        fi
        if [[ $is_use_path ]]; then
            if [[ ! $(is_test path $is_use_path) ]]; then
                err "($is_use_path) 不是有效的路径. $is_err_tips"
            fi
            path=$is_use_path
        fi
        if [[ $is_use_method ]]; then
            is_tmp_use_name=加密方式
            is_tmp_list=${ss_method_list[@]}
            for v in ${is_tmp_list[@]}; do
                if [[ $(grep -E -i "^${is_use_method}$" <<<$v) ]]; then
                    is_tmp_use_type=$v
                    break
                fi
            done
            if [[ ! ${is_tmp_use_type} ]]; then
                warn "(${is_use_method}) 不是一个可用的${is_tmp_use_name}."
                msg "${is_tmp_use_name}可用如下: "
                for v in ${is_tmp_list[@]}; do
                    msg "\t\t$v"
                done
                msg "$is_err_tips\n"
                exit 1
            fi
            ss_method=$is_tmp_use_type
        fi
        if [[ $is_use_pass ]]; then
            ss_password=$is_use_pass
            password=$is_use_pass
        fi
        if [[ $is_use_host ]]; then
            host=$is_use_host
        fi
        if [[ $is_use_door_addr ]]; then
            door_addr=$is_use_door_addr
        fi
        if [[ $is_use_servername ]]; then
            is_servername=$is_use_servername
        fi
        if [[ $is_use_socks_user ]]; then
            is_socks_user=$is_use_socks_user
        fi
        if [[ $is_use_socks_pass ]]; then
            is_socks_pass=$is_use_socks_pass
        fi
        if [[ $is_use_cf_token ]]; then
            cf_token=$is_use_cf_token
        fi
    fi

    if [[ $is_use_tls ]]; then
        if [[ ! $is_no_auto_tls && ! $is_caddy && ! $is_gen && ! $is_dont_test_host ]]; then
            if [[ $(is_test port_used 80) || $(is_test port_used 443) ]]; then
                get_port
                is_http_port=$tmp_port
                get_port
                is_https_port=$tmp_port
                warn "端口 (80 或 443) 已经被占用, 你也可以考虑使用 no-auto-tls"
                msg "\e[41m no-auto-tls 帮助(help)\e[0m: $(msg_ul https://github.com/LuoPoJunZi/Sing-box-LPMG)\n"
                msg "\n Caddy 将使用非标准端口实现自动配置 TLS, HTTP:$is_http_port HTTPS:$is_https_port\n"
                msg "请确定是否继续???"
                pause
            fi
            is_install_caddy=1
        fi
        if [[ ! $host ]]; then
            ask string host "请输入域名:"
        fi
        get host-test
    else
        if [[ $is_main_start ]]; then

            if [[ ! $port ]]; then
                get_port
                port=$tmp_port
                echo ""
                echo -e "--------------------------------------------------------"
                echo -e "端口分配: 已自动为您分配空闲端口 [\e[92m$port\e[0m]"
                echo -e "--------------------------------------------------------"
            fi
            
            if [[ $is_new_protocol == 'CFtunnel' ]]; then
                if [[ ! $cf_token ]]; then
                    ask string cf_token "请输入 Cloudflare Tunnel Token:"
                fi
            fi

            case ${is_new_protocol,,} in
            socks)
                if [[ ! $is_socks_user ]]; then
                    ask string is_socks_user "请设置用户名:"
                fi
                if [[ ! $is_socks_pass ]]; then
                    ask string is_socks_pass "请设置密码:"
                fi
                ;;
            shadowsocks)
                if [[ ! $ss_method ]]; then
                    ask set_ss_method
                fi
                if [[ ! $ss_password ]]; then
                    ask string ss_password "请设置密码:"
                fi
                ;;
            esac

        fi
    fi

    if [[ $is_new_protocol == 'Direct' ]]; then
        if [[ ! $door_addr ]]; then
            ask string door_addr "请输入目标地址:"
        fi
        if [[ ! $door_port ]]; then
            ask string door_port "请输入目标端口:"
        fi
    fi

    if [[ $(grep 2022 <<<$ss_method) ]]; then
        if [[ $ss_password ]]; then
            is_test_json=1
            create server Shadowsocks
            if [[ ! $tmp_uuid ]]; then
                get_uuid
            fi
            is_test_json_save=$is_conf_dir/tmp-test-$tmp_uuid
            cat <<<"$is_new_json" >$is_test_json_save
            $is_core_bin check -c $is_test_json_save &>/dev/null
            if [[ $? != 0 ]]; then
                warn "Shadowsocks 协议 ($ss_method) 不支持使用密码 ($(_red_bg $ss_password))\n\n你可以使用命令: $(_green $is_core ss2022) 生成支持的密码.\n\n脚本将自动创建可用密码:)"
                ss_password=
                json_str=
            fi
            is_test_json=
            rm -f $is_test_json_save
        fi
    fi

    echo ""
    echo -e "--------------------------------------------------------"
    read -p "请输入该节点的自定义备注 (如留空按回车，则默认使用 luopojunzi): " custom_remark
    if [[ -z "$custom_remark" ]]; then
        custom_remark="luopojunzi"
    fi
    echo -e "--------------------------------------------------------"

    if [[ $is_install_caddy ]]; then
        get install-caddy
    fi

    create server $is_new_protocol
    info
}

footer_msg() {
    if [[ $is_core_stop && ! $is_new_json ]]; then
        warn "$is_core_name 当前处于停止状态."
    fi
    if [[ $is_caddy_stop && $host ]]; then
        warn "Caddy 当前处于停止状态."
    fi
    
    msg "------------- END -------------"
    msg "项目(Github): $(msg_ul https://github.com/LuoPoJunZi/Sing-box-LPMG)"
    msg
}

url_qr() {
    is_dont_show_info=1
    info $2
    if [[ $is_url ]]; then
        if [[ $1 == 'url' ]]; then
            msg "\n------------- $is_config_name & URL 链接 -------------"
            msg "\n\e[${is_color}m${is_url}\e[0m\n"
            footer_msg
        else
            link="https://api.qrserver.com/v1/create-qr-code/?size=400x400&data=${is_url}"
            msg "\n------------- $is_config_name & QR code 二维码 -------------"
            msg
            if [[ $(type -P qrencode) ]]; then
                qrencode -t ANSI "${is_url}"
            else
                msg "请安装 qrencode: $(_green "$cmd update -y; $cmd install qrencode -y")"
            fi
            msg
            msg "如果终端无法正常显示二维码, 请复制以下链接到浏览器打开生成:"
            msg "\n\e[4;${is_color}m${link}\e[0m\n"
            footer_msg
        fi
    else
        if [[ $1 == 'url' ]]; then
            err "($is_config_name) 无法生成 URL 链接."
        else
            err "($is_config_name) 无法生成 QR code 二维码."
        fi
    fi
}

update() {
    case $1 in
    1 | core | $is_core)
        is_update_name=core
        is_show_name=$is_core_name
        is_run_ver=v${is_core_ver##* }
        is_update_repo=$is_core_repo
        ;;
    2 | sh)
        is_update_name=sh
        is_show_name="$is_core_name 脚本"
        is_run_ver=$is_sh_ver
        is_update_repo=$is_sh_repo
        ;;
    3 | caddy)
        if [[ ! $is_caddy ]]; then
            err "不支持更新 Caddy."
        fi
        is_update_name=caddy
        is_show_name="Caddy"
        is_run_ver=$is_caddy_ver
        is_update_repo=$is_caddy_repo
        ;;
    *)
        err "无法识别 ($1), 请使用: $is_core update [core | sh | caddy] [ver]"
        ;;
    esac
    if [[ $2 ]]; then
        is_new_ver=v${2#v}
    fi
    if [[ $is_run_ver == $is_new_ver ]]; then
        msg "\n自定义版本和当前 $is_show_name 版本一样, 无需更新.\n"
        exit
    fi
    load download.sh
    if [[ $is_new_ver ]]; then
        msg "\n使用自定义版本更新 $is_show_name: $(_green $is_new_ver)\n"
    else
        get_latest_version $is_update_name
        if [[ $is_run_ver == $latest_ver ]]; then
            msg "\n$is_show_name 当前已经是最新版本了.\n"
            exit
        fi
        msg "\n发现 $is_show_name 新版本: $(_green $latest_ver)\n"
        is_new_ver=$latest_ver
    fi
    download $is_update_name $is_new_ver
    msg "更新成功, 当前 $is_show_name 版本: $(_green $is_new_ver)\n"
    msg "$(_green 请查看更新说明: https://github.com/$is_update_repo/releases/tag/$is_new_ver)\n"
    if [[ $is_update_name != 'sh' ]]; then
        manage restart $is_update_name &
    fi
}

uninstall() {
    if [[ $is_caddy ]]; then
        is_tmp_list=("卸载 $is_core_name" "卸载 ${is_core_name} & Caddy")
        ask list is_do_uninstall
    else
        ask string y "是否卸载 ${is_core_name}? [y]:"
    fi
    manage stop &>/dev/null
    manage disable &>/dev/null
    
    crontab -l 2>/dev/null | grep -v -E "sing-box update|/var/log/sing-box" | crontab -

    rm -rf $is_core_dir $is_log_dir $is_sh_bin ${is_sh_bin/$is_core/sb} /lib/systemd/system/$is_core.service
    sed -i "/$is_core/d" /root/.bashrc
    
    if [[ $REPLY == '2' ]]; then
        manage stop caddy &>/dev/null
        manage disable caddy &>/dev/null
        rm -rf $is_caddy_dir $is_caddy_bin /lib/systemd/system/caddy.service
    fi
    if [[ $is_install_sh ]]; then
        return
    fi
    _green "\n卸载完成!"
    msg "脚本哪里需要完善? 请反馈"
    msg "反馈问题) $(msg_ul https://github.com/LuoPoJunZi/Sing-box-LPMG/issues)\n"
}

manage() {
    if [[ $is_dont_auto_exit ]]; then
        return
    fi
    case $1 in
    1 | start)
        is_do=start
        is_do_msg=启动
        is_test_run=1
        ;;
    2 | stop)
        is_do=stop
        is_do_msg=停止
        ;;
    3 | r | restart)
        is_do=restart
        is_do_msg=重启
        is_test_run=1
        ;;
    *)
        is_do=$1
        is_do_msg=$1
        ;;
    esac
    case $2 in
    caddy)
        is_do_name=$2
        is_run_bin=$is_caddy_bin
        is_do_name_msg=Caddy
        ;;
    *)
        is_do_name=$is_core
        is_run_bin=$is_core_bin
        is_do_name_msg=$is_core_name
        ;;
    esac
    systemctl $is_do $is_do_name
    if [[ $is_test_run && ! $is_new_install ]]; then
        sleep 2
        if [[ ! $(pgrep -f $is_run_bin) ]]; then
            is_run_fail=${is_do_name_msg,,}
            if [[ ! $is_no_manage_msg ]]; then
                msg
                warn "($is_do_msg) $is_do_name_msg 失败"
                _yellow "检测到运行失败, 自动执行测试运行."
                get test-run
                _yellow "测试结束, 请按 Enter 退出."
            fi
        fi
    fi
}

cron_task() {
    msg "\n------------- 自动维护任务 (Cron) -------------"
    msg "注意: 日志清理是保持 VPS 稳定运行的必要选项."
    msg "1. 启用: 自动更新核心 + 自动清空日志 (推荐)"
    msg "2. 启用: 仅自动清空日志 (手动更新核心)"
    msg "3. 关闭: 停止所有自动维护任务"
    msg "4. 退出"
    ask list is_do_cron null "请选择 [1-4]:"
    case $REPLY in
    1)
        (crontab -l 2>/dev/null | grep -v -E "sing-box update core|/var/log/sing-box"; echo "0 3 * * 1 /usr/local/bin/sing-box update core >/dev/null 2>&1"; echo "0 4 * * * echo > /var/log/sing-box/access.log 2>/dev/null; echo > /var/log/sing-box/error.log 2>/dev/null") | crontab -
        _green "\n已设置: 每周一自动更新核心，每天自动清空日志！(无人值守模式已开启)\n"
        ;;
    2)
        (crontab -l 2>/dev/null | grep -v -E "sing-box update core|/var/log/sing-box"; echo "0 4 * * * echo > /var/log/sing-box/access.log 2>/dev/null; echo > /var/log/sing-box/error.log 2>/dev/null") | crontab -
        _green "\n已设置: 每天凌晨 04:00 自动清空日志释放硬盘空间。\n"
        ;;
    3)
        crontab -l 2>/dev/null | grep -v -E "sing-box update|/var/log/sing-box" | crontab -
        _green "\n已关闭: 所有 Sing-box 相关的定时维护任务\n"
        ;;
    4)
        exit
        ;;
    esac
}

is_main_menu() {
    is_main_start=1
    while :; do
        clear
        echo -e "\e[96m=====================================================\e[0m"
        echo -e "\e[96m          Sing-box-LPMG 魔改管理面板 $is_sh_ver\e[0m"
        echo -e "\e[96m=====================================================\e[0m"
        
        local caddy_show=""
        if [[ $is_caddy ]]; then
            caddy_show=" | Caddy: ${is_caddy_status}"
        fi
        echo -e "  [状态] Core: ${is_core_ver} (${is_core_status})${caddy_show}"
        echo -e "\e[90m-----------------------------------------------------\e[0m"
        
        echo -e "  \e[93m◈ 节点管理\e[0m"
        echo -e "    \e[92m(1)\e[0m 添加配置        \e[92m(2)\e[0m 更改配置"
        echo -e "    \e[92m(3)\e[0m 查看单节点      \e[92m(4)\e[0m 删除配置\n"
        
        echo -e "  \e[93m◈ 系统控制\e[0m"
        echo -e "    \e[92m(5)\e[0m 启动/停止       \e[92m(6)\e[0m 自动更新/清理"
        echo -e "    \e[92m(7)\e[0m 完全卸载        \e[92m(8)\e[0m 帮助文档\n"
        
        echo -e "  \e[93m◈ 高级工具\e[0m"
        echo -e "    \e[92m(9)\e[0m 进阶选项       \e[92m(10)\e[0m 关于本脚本"
        echo -e "    \e[92m(0)\e[0m 退出面板"
        echo -e "\e[90m-----------------------------------------------------\e[0m"
        
        echo -ne "➡️ 请输入对应的数字进行操作 [\e[91m0-10\e[0m]: "
        read REPLY
        
        if [[ ! $REPLY ]]; then
            continue
        fi
        if [[ "$REPLY" == "0" ]]; then
            exit
        fi
        if [[ "$REPLY" =~ ^([1-9]|10)$ ]]; then
            break
        fi
        echo -e "\e[31m输入错误, 请输入 0-10 之间的数字\e[0m"
        sleep 1
    done

    case $REPLY in
    1)
        add
        ;;
    2)
        change
        ;;
    3)
        info
        ;;
    4)
        del
        ;;
    5)
        ask list is_do_manage "启动 停止 重启"
        manage $REPLY &
        msg "\n管理状态执行: $(_green $is_do_manage)\n"
        ;;
    6)
        cron_task
        ;;
    7)
        uninstall
        ;;
    8)
        msg
        load help.sh
        show_help
        ;;
    9)
        ask list is_do_other "一键查看所有节点信息 启用BBR 查看日志 测试运行 重装脚本 设置DNS 手动更新"
        case $REPLY in
        1)
            show_all_nodes
            ;;
        2)
            load bbr.sh
            _try_enable_bbr
            ;;
        3)
            load log.sh
            log_set
            ;;
        4)
            get test-run
            ;;
        5)
            get reinstall
            ;;
        6)
            load dns.sh
            dns_set
            ;;
        7)
            is_tmp_list=("更新$is_core_name" "更新脚本")
            if [[ $is_caddy ]]; then
                is_tmp_list+=("更新Caddy")
            fi
            ask list is_do_update null "\n请选择手动更新:\n"
            update $REPLY
            ;;
        esac
        ;;
    10)
        load help.sh
        about
        ;;
    esac
}

main() {
    case $1 in
    a | add | gen | no-auto-tls)
        if [[ $1 == 'gen' ]]; then
            is_gen=1
        fi
        if [[ $1 == 'no-auto-tls' ]]; then
            is_no_auto_tls=1
        fi
        add ${@:2}
        ;;
    bin | pbk | check | completion | format | generate | geoip | geosite | merge | rule-set | run | tools)
        is_run_command=$1
        if [[ $1 == 'bin' ]]; then
            $is_core_bin ${@:2}
        else
            if [[ $is_run_command == 'pbk' ]]; then
                is_run_command="generate reality-keypair"
            fi
            $is_core_bin $is_run_command ${@:2}
        fi
        ;;
    bbr)
        load bbr.sh
        _try_enable_bbr
        ;;
    c | config | change)
        change ${@:2}
        ;;
    d | del | rm)
        del $2
        ;;
    dd | ddel | fix | fix-all)
        case $1 in
        fix)
            if [[ $2 ]]; then
                change $2 full
            else
                is_change_id=full && change
            fi
            return
            ;;
        fix-all)
            is_dont_auto_exit=1
            msg
            for v in $(ls $is_conf_dir | grep .json$ | sed '/dynamic-port-.*-link/d'); do
                msg "fix: $v"
                change $v full
            done
            _green "\nfix 完成.\n"
            ;;
        *)
            is_dont_auto_exit=1
            if [[ ! $2 ]]; then
                err "无法找到需要删除的参数"
            else
                for v in ${@:2}; do
                    del $v
                done
            fi
            ;;
        esac
        is_dont_auto_exit=
        manage restart &
        if [[ $is_del_host ]]; then
            manage restart caddy &
        fi
        ;;
    dns)
        load dns.sh
        dns_set ${@:2}
        ;;
    cron)
        cron_task
        ;;
    all)
        show_all_nodes
        ;;
    debug)
        is_debug=1
        get info $2
        warn "如果需要复制; 请把 *uuid, *password, *host, *key 的值改写, 以避免泄露."
        ;;
    fix-config.json)
        create config.json
        ;;
    fix-caddyfile)
        if [[ $is_caddy ]]; then
            load caddy.sh
            caddy_config new
            manage restart caddy &
            _green "\nfix 完成.\n"
        else
            err "无法执行此操作"
        fi
        ;;
    i | info)
        info $2
        ;;
    ip)
        get_ip
        msg $ip
        ;;
    in | import)
        load import.sh
        ;;
    log)
        load log.sh
        log_set $2
        ;;
    url | qr)
        url_qr $@
        ;;
    un | uninstall)
        uninstall
        ;;
    u | up | update | U | update.sh)
        is_update_name=$2
        is_update_ver=$3
        if [[ ! $is_update_name ]]; then
            is_update_name=core
        fi
        if [[ $1 == 'U' || $1 == 'update.sh' ]]; then
            is_update_name=sh
            is_update_ver=
        fi
        update $is_update_name $is_update_ver
        ;;
    ssss | ss2022)
        get $@
        ;;
    s | status)
        msg "\n$is_core_name $is_core_ver: $is_core_status\n"
        if [[ $is_caddy ]]; then
            msg "Caddy $is_caddy_ver: $is_caddy_status\n"
        fi
        ;;
    start | stop | r | restart)
        if [[ $2 && $2 != 'caddy' ]]; then
            err "无法识别 ($2), 请使用: $is_core $1 [caddy]"
        fi
        manage $1 $2 &
        ;;
    t | test)
        get test-run
        ;;
    reinstall)
        get $1
        ;;
    get-port)
        get_port
        msg $tmp_port
        ;;
    main)
        is_main_menu
        ;;
    v | ver | version)
        if [[ $is_caddy_ver ]]; then
            is_caddy_ver="/ $(_blue Caddy $is_caddy_ver)"
        fi
        msg "\n$(_green $is_core_name $is_core_ver) / $(_cyan $is_core_name script $is_sh_ver) $is_caddy_ver\n"
        ;;
    h | help | --help)
        load help.sh
        show_help ${@:2}
        ;;
    *)
        is_try_change=1
        change test $1
        if [[ $is_change_id ]]; then
            unset is_try_change
            if [[ $2 ]]; then
                change $2 $1 ${@:3}
            else
                change
            fi
        else
            err "无法识别 ($1), 获取帮助请使用: $is_core help"
        fi
        ;;
    esac
}