#!/bin/bash

# log-master.sh - 用于分析Apache访问日志的Bash脚本

# 函数：显示用法
usage() {
    echo "Usage: ./log-master.sh [OPTIONS] <sub-command> [arguments...]" >&2
    echo "Global Options (must appear before the sub-command):" >&2
    echo "  -f, --file <logfile>: Specifies the path to the log file to be analyzed." >&2
    echo "  --start <datetime>: Filter logs starting from this datetime (format: YYYY/MM/DD:HH:MM:SS)." >&2
    echo "  --end <datetime>: Filter logs up to this datetime (format: YYYY/MM/DD:HH:MM:SS)." >&2
    exit 1
}

# 解析全局选项
logfile=""
start_time=""
end_time=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--file)
            if [[ -z "$2" ]]; then
                echo "Error: Option -f requires an argument." >&2
                exit 1
            fi
            logfile="$2"
            shift 2
            ;;
        --start)
            if [[ -z "$2" ]]; then
                echo "Error: Option --start requires an argument." >&2
                exit 1
            fi
            start_time="$2"
            shift 2
            ;;
        --end)
            if [[ -z "$2" ]]; then
                echo "Error: Option --end requires an argument." >&2
                exit 1
            fi
            end_time="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option '$1'." >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

# 检查是否指定了日志文件
if [[ -z "$logfile" ]]; then
    echo "Error: Log file not specified. Use -f <logfile>." >&2
    exit 1
fi

# 检查日志文件是否存在且可读
if [[ ! -f "$logfile" || ! -r "$logfile" ]]; then
    echo "Error: File not found or is not readable: $logfile." >&2
    exit 1
fi

# 获取子命令
subcommand="$1"
shift

# 函数：验证正整数
validate_positive_int() {
    local n="$1"
    if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -le 0 ]]; then
        echo "Error: Invalid count '$n'. Must be a positive integer." >&2
        exit 1
    fi
}

# 函数：验证时间格式（简单检查 YYYY/MM/DD:HH:MM:SS）
validate_datetime() {
    local dt="$1"
    if ! [[ "$dt" =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        echo "Error: Invalid datetime format '$dt'. Must be YYYY/MM/DD:HH:MM:SS." >&2
        exit 1
    fi
}

# 如果提供了 start/end，验证格式
if [[ -n "$start_time" ]]; then
    validate_datetime "$start_time"
fi
if [[ -n "$end_time" ]]; then
    validate_datetime "$end_time"
fi

# 函数：获取过滤后的日志（process substitution）
filtered_log() {
    while read -r line; do
        if [[ -z "$line" ]]; then continue; fi
        timestamp=$(echo "$line" | cut -d' ' -f4 | tr -d '[')  # 提取 YYYY/MM/DD:HH:MM:SS
        if [[ -n "$start_time" && "$timestamp" < "$start_time" ]]; then continue; fi
        if [[ -n "$end_time" && "$timestamp" > "$end_time" ]]; then continue; fi
        echo "$line"
    done < "$logfile"
}

# 子命令函数（每个函数使用 <(filtered_log) 作为输入）

ip_top() {
    local N="${1:-10}"
    validate_positive_int "$N"
    echo "COUNT   IP_ADDRESS"
    
    cut -d ' ' -f 1 <(filtered_log) | \
    sort | \
    uniq -c | \
    sort -nr | \
    head -n "$N" | \
    while read -r count ip; do
        echo "$count       $ip"
    done
}

status_codes() {
    echo "STATUS_CODE     COUNT"
    cut -d ' ' -f 9 <(filtered_log) | sort | uniq -c | sort -k2n | \
    while read -r count sc; do
        echo "$count               $sc"
    done  
}

status_errors() {
    local N="${1:-10}"
    validate_positive_int "$N"
    echo "COUNT     STATUS_CODE     REQUEST"
    while read -r line; do
        status=$(echo "$line" | cut -d' ' -f9)
        if [[ "$status" =~ ^[45] ]]; then
            method=$(echo "$line" | cut -d' ' -f6)
            url=$(echo "$line" | cut -d' ' -f7)
            protocol=$(echo "$line" | cut -d' ' -f8)
            echo "$status \"$method $url $protocol\""
        fi
    done < <(filtered_log) | sort | uniq -c | sort -nr | head -n "$N" | while read -r count sc re; do
        echo "$count         $sc             $re"
    done  
}

requests_top() {
    local N="${1:-10}"
    validate_positive_int "$N"
    echo "COUNT      URL"
    cut -d ' ' -f 7 <(filtered_log) | sort | uniq -c | sort -nr | head -n "$N" | \
    while read -r count u; do
        echo "$count               $u"
    done
}

events_hourly() {
    echo "HOUR  REQUEST_COUNT"

    # 生成临时文件，统计每小时访问次数
    cut -d' ' -f4 <(filtered_log) | tr -d '[' | cut -d: -f2 | \
    sort | uniq -c > /tmp/hour_count

    # 用纯 Bash 循环输出 00~23
    for ((h=0; h<24; h++)); do
        len=${#h}
        if [ $len -eq 1 ]; then
            hh="0$h"
        else
            hh="$h"
        fi
        count=$(grep -w "$hh" /tmp/hour_count | cut -c1-8 | tr -d ' ')
        count=${count:-0}
        echo -e "$hh           $count"
    done

    rm -f /tmp/hour_count
}

# 执行子命令
case "$subcommand" in
    ip:top)
        ip_top "$@"
        ;;
    status:codes)
        if [[ $# -ne 0 ]]; then
            echo "Error: status:codes takes no arguments." >&2
            exit 1
        fi
        status_codes
        ;;
    status:errors)
        status_errors "$@"
        ;;
    requests:top)
        requests_top "$@"
        ;;
    events:hourly)
        if [[ $# -ne 0 ]]; then
            echo "Error: events:hourly takes no arguments." >&2
            exit 1
        fi
        events_hourly
        ;;
    *)
        if [[ -z "$subcommand" ]]; then
            usage
        else
            echo "Error: Unknown command '$subcommand'." >&2
            exit 1
        fi
        ;;
esac