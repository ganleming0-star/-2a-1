#!/bin/bash

# log-master.sh - 用于分析Apache访问日志的Bash脚本

# 函数：显示用法
usage() {
    echo "Usage: ./log-master.sh [OPTIONS] <sub-command> [arguments...]" >&2  #将这条信息重定向到stderr标准错误输出 正常情况下是在stdout标准输出（1）中， 0代表标准输入
    echo "Global Options (must appear before the sub-command):" >&2
    echo "  -f, --file <logfile>: Specifies the path to the log file to be analyzed." >&2
    exit 1
}

# 解析全局选项
logfile="" #初始化文件路径
while [[ $# -gt 0 ]]; do  # $#的意思是参数的数量，-gt是greater than
    case "$1" in
        -f|--file)
            if [[ -z "$2" ]]; then   #-z判断字符串$2是否为空 $2代表着第二个参数 为空则执行if的代码
                echo "Error: Option -f requires an argument." >&2 #没有文件路径 报错
                exit 1
            fi
            logfile="$2"
            shift 2  #去除前两个参数  意味着$3之后用$1表示，同时$#的大小-2 和前面的while循环的条件有关系（shift王磊好像还没教，不知道他下周教不教，不交的话后面再改）
            ;;
        -*)#匹配其他以 - 开头的未知选项，打印错误并调用 usage 函数。
            echo "Error: Unknown option '$1'." >&2
            usage
            ;;
        *)#匹配非选项参数，break 跳出循环。
            break
            ;;
    esac #结束case语句 esac即case反着写
done #结束while循环

# 检查是否指定了日志文件
if [[ -z "$logfile" ]]; then #-z意思同上
    echo "Error: Log file not specified. Use -f <logfile>." >&2
    exit 1
fi

# 检查日志文件是否存在且可读
if [[ ! -f "$logfile" || ! -r "$logfile" ]]; then  #-f即file检查文件是否存在，-r即read检查文件是否可读 两者有一个错误则提示error
    echo "Error: File not found or is not readable: $logfile." >&2
    exit 1
fi

# 获取子命令
subcommand="$1" #将第一个剩余的参数传给subcommand  例如输入的参数为 -f ./sample_access.log ip:top 5 之前（23行）已经去掉两个，则剩下的第一个参数就是ip:top
shift #同上 参数减一

# 函数：验证正整数
validate_positive_int() {
    local n="$1"  #local 意味着本地变量 即n是特指在这个方法中的变量 如果方法外面也有n 则local可以将他们区分开  如果要调用方法外面的n 则用global
    if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -le 0 ]]; then #[[ "$n" =~ ^[0-9]+$ ]]是正则表达式（也没学）[[.....]]是Bash 的扩展测试命令用于测试判断的表达式 =~：正则表达式匹配运算符 ^：匹配字符串的开始 [0-9]：匹配任意数字（0 到 9）+：表示前面的元素（[0-9]）出现一次或多次。 $：匹配字符串的结束。 
        #这行的意思是n如果不是纯数字或-le（less than）小于等于0 就执行if
        echo "Error: Invalid count '$n'. Must be a positive integer." >&2
        exit 1
    fi
}

# 子命令函数

ip_top() {
    local N="${1:-10}"
    validate_positive_int "$N"
    echo "COUNT   IP_ADDRESS"
    
    
    cut -d ' ' -f 1 "$logfile" | \
    sort | \
    uniq -c | \
    sort -nr | \
    head -n "$N" | \
    while read -r count ip; do
        # 使用 printf 格式化输出，代替第二个 awk
        echo "$count       $ip"
    done
    #|是管道符 看ppt 
    #cut -d 指定字段的分隔符 指定为" " -f 指定显示的字段 即显示第1个字段
    #sort 从小到大排序 并传给uniq
    #uniq -c   uniq是去重 需要排序后才有用 所以之前要sort  -c是在前面加上重复出现的次数。
    #sort -nr 对上一步的输出（计数 + 值）进行数字降序排序，按计数从大到小 -n：按数字排序，而不是字符串（这样 10 > 2）  -r：逆序（reverse），从大到小 循环读入每一行 读入的字符串赋值给变量ip
    #head -n "$N"  从上一步的排序输出中取出前 N 行   %-10d：格式化第一个字段（$1，计数）%d 表示整数，- 表示左对齐，10 表示宽度为 10（不足用空格补齐）。
    #while read -r count ip 循环读入每一行 读入的字符串赋值给变量ip
    
}

status_codes() {
    echo "STATUS_CODE     COUNT"
    cut -d ' ' -f 9 "$logfile" | sort | uniq -c | sort -k2n | \
    while read -r count sc; do
        echo "$count               $sc"
    done  
     #和上面差不多 9是对第9个字段操作  -k2n：指定按第二字段（key=2）数值排序      
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
        echo "$status "$method $url $protocol""
    fi
done < "$logfile" | sort | uniq -c | sort -nr | head -n "$N" | while read -r count sc re; do
        echo "$count         $sc             $re"
    done  
    
}

requests_top() {
    local N="${1:-10}"
    validate_positive_int "$N"
    echo "COUNT      URL"
    cut -d ' ' -f 7 "$logfile" | sort | uniq -c | sort -nr | head -n "$N" | \
    while read -r count u; do
        echo "$count               $u"
    done    #和前面差不多
}

events_hourly() {
    echo "HOUR  REQUEST_COUNT"

    # 生成临时文件，统计每小时访问次数
    cut -d' ' -f4 "$logfile" | tr -d '[' | cut -d: -f2 | \
    sort | uniq -c > /tmp/hour_count

    # 用纯 Bash 循环输出 00~23
    for ((h=0; h<24; h++)); do
        len=${#h}

    if [ $len -eq 1 ]; then
            hh="0$h"  # 1位数字补0（如5→05）
    else
            hh="$h"   # 2位数字直接使用（如12→12）
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
        ip_top "$@"  #调用ip_top方法 "$@"是剩余所有的参数
        ;;
    status:codes)
        
        if [[ $# -ne 0 ]]; then  #如果剩余没有参数了 报错  否则status_codes执行
            echo "Error: status:codes takes no arguments." >&2
            exit 1
        fi
        status_codes
        ;;
    status:errors)
        status_errors "$@"  #同理
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
    *)  #不匹配的话
        if [[ -z "$subcommand" ]]; then  #如果subcommand为空
            usage
        else  #如果不为空
            echo "Error: Unknown command '$subcommand'." >&2
            exit 1
        fi
        ;;
esac