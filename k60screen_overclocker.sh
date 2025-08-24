#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PURE='\033[0;35m'
NC='\033[0m'

# 定义工作区路径
WORKSPACE="workspace"
IMG_DIR="$WORKSPACE/img"
TOOLS_DIR="$WORKSPACE/tools"
EXTRACTED_DTBO_DIR="$WORKSPACE/extracted_dtbo"
OUTPUT_DTBO_DIR="$WORKSPACE/output_dtbo"
BACKUP_DIR="$WORKSPACE/backup"
LOG_DIR="$WORKSPACE/logs"

# --- 日志和输出函数定义 ---

log_to_file() {
    local message="$1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $(echo -e "$message" | sed 's/\x1b\[[0-9;]*m//g')" >> "$LOG_FILE"
}

print_error() {
    local full_msg_with_color="${RED}错误: $1${NC}"
    log_to_file "$full_msg_with_color"
    echo -e "$full_msg_with_color"
}

print_success() {
    local full_msg_with_color="${GREEN}成功: $1${NC}"
    log_to_file "$full_msg_with_color"
    echo -e "$full_msg_with_color" 
}

print_info() {
    local full_msg_with_color="${PURE}信息: $1${NC}"
    log_to_file "$full_msg_with_color"
    echo -e "$full_msg_with_color"
}

print_warning() {
    local full_msg_with_color="${YELLOW}警告: $1${NC}"
    log_to_file "$full_msg_with_color"
    echo -e "$full_msg_with_color"
}

# 清理旧日志文件，只保留最新的5份
cleanup_old_logs() {
    local num_to_keep=5
    local old_logs=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | tail -n +$((num_to_keep + 1)))
    if [ -n "$old_logs" ]; then
        echo "$old_logs" | xargs rm -f
    fi
}


# --- 脚本核心功能函数 ---

# 检查是否为Root环境
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请以Root权限运行此脚本！"
        exit 1
    fi
}


# 获取手机代号和屏幕型号
get_phone_info() {
    PHONE_CODENAME=$(getprop ro.product.name)
    if [ -z "$PHONE_CODENAME" ]; then
        print_warning "未能获取到手机代号 (ro.product.name)，请手动确认。"
        PHONE_CODENAME="未知手机"
    fi

    # 提取屏幕型号，使用更兼容的grep和cut
    # 从 msm_drm.dsi_display0= 到下一个空格或冒号之间的内容
    SCREEN_MODEL=$(cat /proc/cmdline | grep -o 'msm_drm.dsi_display0=[^ ]*' | head -n 1 | cut -d'=' -f2 | cut -d':' -f1)
    if [ -z "$SCREEN_MODEL" ]; then
        print_error "未能从 /proc/cmdline 中提取到屏幕型号。请手动检查 /proc/cmdline 中 'msm_drm.dsi_display0=' 后面的屏幕信息。"
        SCREEN_MODEL="未知屏幕"
    fi

    print_info "手机代号: ${GREEN}$PHONE_CODENAME${NC}"
    print_info "屏幕型号: ${GREEN}$SCREEN_MODEL${NC}"
}

# 创建工作区目录
setup_workspace() {
    mkdir -p "$IMG_DIR" "$TOOLS_DIR" "$EXTRACTED_DTBO_DIR" "$OUTPUT_DTBO_DIR" "$BACKUP_DIR" "$LOG_DIR"
}

# AB判断
detect_ab() {
    local suffix=$(getprop ro.boot.slot_suffix)
    
    if [[ ! "$suffix" ]]; then
        print_warning "无AB分区！"
    else
        print_info "当前活动的AB分区: ${GREEN}$suffix${NC}"
        dtbo_partition="/dev/block/by-name/dtbo$suffix"
    fi
}

# 检查工具
check_tools() {
    for t in dtc mkdtimg; do
        [ -f "$TOOLS_DIR/$t" ] && continue
        print_warning "$t 缺失！"
        curl -sSfL ""$url_online"/workspace/tools/$t" -o "$TOOLS_DIR/$t" && \
            chmod +x "$TOOLS_DIR/$t" && print_success "$t 下载成功" || \
            { print_error "$t 下载失败"; return 1; }
    done
    
    chmod 777 "$TOOLS_DIR/dtc" "$TOOLS_DIR/mkdtimg"
    print_info "dtc 和 mkdtimg 工具已就绪。"
}



# 重启
rebooot() {
    read -p "刷入成功，是否立即重启设备？(y/n): " reboot_confirm
    if [ "$reboot_confirm" = "y" ] || [ "$reboot_confirm" = "Y" ]; then
        print_info "三秒后重启设备..." && sleep 3
        reboot
    fi
}

# 提示
tips() {
    clear

    print_warning "正在联网获取提示...."
    local online
    online=$(curl -fsSL ""$url_online"/tips" 2>/dev/null)

    if [[ -n $online ]]; then
        print_info "$online"
    else
        print_error "获取失败"
    fi
}

# 备份DTBO
backup_dtbo() {
    local timestamp=$(date +'%Y%m%d_%H%M%S')
    local backup_file="$BACKUP_DIR/dtbo_backup_${timestamp}.img"

    dd if="$dtbo_partition" of="$backup_file" bs=4M 2>> "$LOG_FILE" # 将dd的错误输出重定向到日志
    if [ $? -ne 0 ]; then
        print_error "DTBO备份失败！请检查分区路径或权限。"
        return 1
    fi

    # 对比上一份备份的SHA256
    local previous_backup_file=$(ls -t "$BACKUP_DIR"/dtbo_backup_*.img 2>/dev/null | grep -v "$backup_file" | head -n 1)

    if [ -f "$previous_backup_file" ]; then
        current_sha=$(sha256sum "$backup_file" | awk '{print $1}')
        previous_sha=$(sha256sum "$previous_backup_file" | awk '{print $1}')

        if [ "$current_sha" = "$previous_sha" ]; then
            print_warning "已删除重复的备份！"
            rm "$backup_file"
        else
            print_success "DTBO已备份到: $backup_file"
        fi
    fi
    return 0
}

# 还原DTBO
recovery_dtbo() {
    clear
    local backup_file="$BACKUP_DIR/dtbo_backup_${timestamp}.img"
    print_info "正在恢复DTBO"
    local previous_backup_file=$(ls -t "$BACKUP_DIR"/dtbo_backup_*.img | grep -v "$backup_file" | head -n 1)
    echo $previous_backup_file
    if [ -f "$previous_backup_file" ]; then
        flash_dtbo "$previous_backup_file"
    else
        print_error "恢复文件不存在！"
    fi
}

# 刷入DTBO
flash_dtbo() {
    local dtbo_img=$1

    if [ ! -f "$dtbo_img" ]; then
        print_error "要刷入的DTBO文件不存在: $dtbo_img"
        return 1
    fi
    
    read -p "确定要刷入此DTBO文件吗？(y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        print_info "正在刷入DTBO文件: ${GREEN}$dtbo_img${NC} 到分区: ${GREEN}$dtbo_partition${NC}"
        
    dd if="$dtbo_img" of="$dtbo_partition" bs=4M 2>> "$LOG_FILE" # 将dd的错误输出重定向到日志
    
        if [ $? -ne 0 ]; then
            print_error "DTBO刷入失败！"
            print_warning "请尝试关闭防格机模块，或在TWRP中进行备份、恢复和刷入操作。"
            return 1
        fi
        
        print_success "DTBO刷入成功！"
        rebooot
        return 0
    
    else
        print_info "已取消刷入操作。"
    fi
    
}

# DTBO解包
extract_dtbo() {
    local dtbo_file=$1
    print_info "正在解包DTBO文件: $dtbo_file"
    rm -rf "$EXTRACTED_DTBO_DIR"/* # 清理旧文件
    mkdir -p "$EXTRACTED_DTBO_DIR"

    # 将 mkdtimg dump 的输出重定向到日志文件，屏幕上不显示
    "$TOOLS_DIR/mkdtimg" dump "$dtbo_file" -b "$EXTRACTED_DTBO_DIR/dtb" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        print_error "解包失败！请查看日志获取详细信息。"
        return 1
    fi
    print_success "DTBO已解包到: $EXTRACTED_DTBO_DIR"
    return 0
}

# DTB反编译为DTS
decompile_dtb() {
    print_info "正在反编译DTB文件为DTS..."
    local dtb_files=$(find "$EXTRACTED_DTBO_DIR" -maxdepth 1 -name "dtb.*")
    if [ -z "$dtb_files" ]; then
        print_error "未找到任何dtb文件进行反编译！"
        return 1
    fi

    for i in $dtb_files; do
        local dts_output="${i}.dts"
        "$TOOLS_DIR/dtc" -I dtb -O dts -@ "$i" -o "$dts_output" >> "$LOG_FILE" 2>&1 # 输出到日志
        if [ $? -ne 0 ]; then
            print_error "dtc 反编译 $(basename "$i") 失败！"
            return 1
        fi
        rm "$i" # 删除原始dtb文件
    done
    print_success "DTB文件已反编译为DTS并删除原始DTB文件。"
    return 0
}

# DTS重新编译为DTB
recompile_dtb() {
    print_info "正在重新编译DTS文件为DTB..."
    local dts_files=$(find "$EXTRACTED_DTBO_DIR" -maxdepth 1 -name "*.dts")
    if [ -z "$dts_files" ]; then
        print_error "未找到任何dts文件进行重新编译！"
        return 1
    fi

    for i in $dts_files; do
        local dtb_output="${i%.dts}"
        "$TOOLS_DIR/dtc" -I dts -O dtb -@ -o "$dtb_output" "$i" >> "$LOG_FILE" 2>&1 # 输出到日志
        if [ $? -ne 0 ]; then
            print_error "dtc 重新编译 $(basename "$i") 失败！"
            return 1
        fi
        rm "$i" # 删除原始dts文件
    done
    print_success "DTS文件已重新编译为DTB并删除原始DTS文件。"
    return 0
}

# 重新打包DTBO
pack_dtbo() {
    local output_filename=$1
    print_info "正在打包DTB文件为新的DTBO镜像: $output_filename"
    local dtb_files_to_pack=$(find "$EXTRACTED_DTBO_DIR" -maxdepth 1 -name "dtb.*")
    if [ -z "$dtb_files_to_pack" ]; then
        print_error "未找到任何DTB文件进行打包！"
        return 1
    fi

    "$TOOLS_DIR/mkdtimg" create "$output_filename" $dtb_files_to_pack >> "$LOG_FILE" 2>&1 # 输出到日志
    if [ $? -ne 0 ]; then
        print_error "打包失败！"
        return 1
    fi
    print_success "新的DTBO镜像已生成: $output_filename"
    return 0
}

# --- 主菜单 ---
main_menu() {
#    while true; do  # 防止循环刷日志，卡设备
        echo -e "${YELLOW}---------------------------------------${NC}"
        echo -e "${YELLOW}           主菜单                      ${NC}"
        echo -e "${YELLOW}---------------------------------------${NC}"
        echo -e "${GREEN}1. 刷入预制DTBO文件${NC}"
        echo -e "${GREEN}2. 刷入自定义DTBO文件${NC}"
        echo -e "${GREEN}3. 制作自定义DTBO (超频)${NC}"
        echo -e "${GREEN}4. 强开全局DC调光${NC}"
        echo -e "${GREEN}5. 还原上一次备份${NC}"
        echo -e "${GREEN}6. 获取提示${NC}"
        echo -e "${RED}0. 退出${NC}"
        echo -e "${YELLOW}---------------------------------------${NC}"
        read -p "请选择一个选项: " choice

        case "$choice" in
            1) flash_premade_dtbo ;;
            2) flash_custom_dtbo ;;
            3) create_custom_dtbo ;;
            4) print_info "看看就行了，懒得整鸽掉" ;;
            5) recovery_dtbo ;;
            6) tips ;;
            0) print_info "退出脚本。再见！" && exit 0 ;;
            *) print_error "无效的选项，请重新输入。" ;;
        esac
        echo ""
        read -p "按回车键继续..." 
#    done
}

# 选项一：刷入预制DTBO文件
flash_premade_dtbo() {
    clear
    local dtbo_files=($(find "$IMG_DIR" -maxdepth 3 -name "dtbo*.img"))

    if [ ${#dtbo_files[@]} -eq 0 ]; then
        print_warning "${IMG_DIR} 下暂无预制 DTBO"
        read -p "是否联网下载预制包？(y/N): " dl
        [[ "$dl" =~ ^[Yy]$ ]] || return

        local zip=/data/local/tmp/img.zip
        curl -sSfL "$url_online"/img.zip \
             -o "$zip" && {
            unzip -q "$zip" -d "$WORKSPACE" 2>/dev/null || unzip -q "$zip" -d "$WORKSPACE"
            rm -f "$zip"
            dtbo_files=($(find "$IMG_DIR" -maxdepth 3 -name "dtbo*.img"))
        } || { print_error "下载/解压失败"; return; }
    fi

    [ ${#dtbo_files[@]} -eq 0 ] && { print_error "仍无可用 DTBO"; return; }

    echo -e "${PURE}可用的预制 DTBO:${NC}"
    local count=1
    for file in "${dtbo_files[@]}"; do
        echo -e "${GREEN}$((count++)). $(basename "$file")${NC}"
    done

    read -p "请输入序号: " file_choice
    [[ "$file_choice" =~ ^[0-9]+$ ]] && [ "$file_choice" -gt 0 ] && \
        [ "$file_choice" -le ${#dtbo_files[@]} ] || { print_error "无效序号"; return; }

    flash_dtbo "${dtbo_files[$((file_choice-1))]}"
}


# 选项二：刷入自定义DTBO文件
flash_custom_dtbo() {
    clear 

    local dtbo_files=()
    # 使用 mapfile 更高效地将 find 结果读取到数组中 (Bash 4+)
    # 如果是旧版 Bash，需要保留原有的 while read 循环
    mapfile -d '' dtbo_files < <(find "$OUTPUT_DTBO_DIR" -maxdepth 1 -type f -name "dtbo*.img" -print0)

    local count=1
    if [ ${#dtbo_files[@]} -eq 0 ]; then
        print_warning "在 ${OUTPUT_DTBO_DIR} 目录下未找到任何以 'dtbo' 开头 '.img' 结尾的自定义DTBO文件。"
    else
        echo -e "${PURE}可用的自定义DTBO文件:${NC}"
        for file in "${dtbo_files[@]}"; do
            echo -e "${GREEN}$((count++)). $(basename "$file")${NC}"
        done
    fi

    # 将手动输入选项放在列出的文件之后，并给予下一个序号
    echo "-----------------------------"
    echo -e "${GREEN}$((count)). 手动输入 DTBO 文件路径${NC}"
    echo "-----------------------------"

    read -p "请输入要刷入的文件的序号: " file_choice

    local selected_file=""
    local num_dtbo_files=${#dtbo_files[@]}

    if [[ "$file_choice" =~ ^[0-9]+$ ]]; then
        if [ "$file_choice" -ge 1 ] && [ "$file_choice" -le "$num_dtbo_files" ]; then
            selected_file="${dtbo_files[$((file_choice-1))]}"
        elif [ "$file_choice" -eq $((num_dtbo_files + 1)) ]; then # 对应手动输入的序号
            read -p "请输入要刷入的DTBO文件的完整路径: " selected_file
            # 进一步验证手动输入的路径是否存在
            if [[ ! -f "$selected_file" ]]; then
                print_error "错误：手动输入的路径 '$selected_file' 不是一个有效的文件。"
                return 1
            fi
        fi
    fi

    if [ -z "$selected_file" ]; then
        print_error "无效的序号或未选择任何文件。"
        return 1
    fi

    print_info "您选择了: $(basename "$selected_file")"

    flash_dtbo "$selected_file"
    return 0
}



# 选项三：制作自定义DTBO
create_custom_dtbo() {
    clear # 清屏
    local source_dtbo_file=""
        source_dtbo_file="$dtbo_partition"
        print_info "将提取本机DTBO分区: $source_dtbo_file"
    
    if [ ! -b "$source_dtbo_file" ] && [ ! -f "$source_dtbo_file" ]; then
        print_error "DTBO源文件/分区不存在或不可读: $source_dtbo_file"
        return
    fi

    extract_dtbo "$source_dtbo_file"
    if [ $? -ne 0 ]; then return; fi

    decompile_dtb
    if [ $? -ne 0 ]; then return; fi

    # --- 精确定位目标DTS文件 ---
    print_info "正在根据手机代号 [${PHONE_CODENAME}] 查找相关的DTS文件..."
    local relevant_dts_files=$(grep -l -r -i "$PHONE_CODENAME" "$EXTRACTED_DTBO_DIR")
    
    if [ -z "$relevant_dts_files" ]; then
        print_warning "未能通过手机代号找到DTS文件，尝试使用屏幕型号 [${SCREEN_MODEL}] 作为备用方案..."
        relevant_dts_files=$(grep -l -r -i "$SCREEN_MODEL" "$EXTRACTED_DTBO_DIR")
        if [ -z "$relevant_dts_files" ]; then
            print_error "使用手机代号和屏幕型号均未能找到相关的DTS文件。"
            return
        fi
    fi

    local target_file=""
    local file_count=$(echo "$relevant_dts_files" | wc -l)

    if [ "$file_count" -eq 1 ]; then
        target_file="$relevant_dts_files"
        print_success "已精确定位到目标DTS文件: $(basename "$target_file")"
    else
        print_warning "找到了多个相关的DTS文件。请选择一个进行操作："
        local i=1
        # 使用临时文件来安全处理文件名列表
        echo "$relevant_dts_files" > /data/local/tmp/dts_files.tmp
        while read -r file; do
            echo -e "${GREEN}${i}. $(basename "$file")${NC}"
            i=$((i+1))
        done < /data/local/tmp/dts_files.tmp

        read -p "请输入文件序号: " file_choice
        if ! [[ "$file_choice" =~ ^[0-9]+$ ]] || [ "$file_choice" -le 0 ] || [ "$file_choice" -ge "$i" ]; then
            print_error "无效的序号。"
            rm /data/local/tmp/dts_files.tmp
            return
        fi
        target_file=$(sed -n "${file_choice}p" /data/local/tmp/dts_files.tmp)
        rm /data/local/tmp/dts_files.tmp
        print_success "您已选择: $(basename "$target_file")"
    fi
    # --- 文件定位结束 ---


    print_info "自动检测Panel节点..."
    # 查找 Panel 节点名称，例如 qcom,mdss_dsi_m11a_42_02_0a_dsc_cmd
    local PANEL_NODE_NAME=$(grep -o '[^ ]*'"$SCREEN_MODEL"'[^ ]* {' "$target_file" | sed 's/ {//' | head -n 1)

    if [ -z "$PANEL_NODE_NAME" ]; then
        print_error "未能在DTS文件中自动检测到与屏幕型号 [${SCREEN_MODEL}] 相关的Panel节点。"
        return
    fi
    print_success "自动检测到 Panel 节点: ${PANEL_NODE_NAME}"

    print_info "自动检测Fragment ID..."
    # 修正后的Fragment ID检测逻辑：查找包含 PANEL_NODE_NAME 的 fragment@NN
    local FRAGID=$(awk -v panel_name_to_find="$PANEL_NODE_NAME" '
        /fragment@[0-9]+ \{/ {
            # 匹配 fragment@NN { 并提取 NN
            if (match($0, /fragment@([0-9]+)/, arr)) {
                current_fragment_id = arr[1];
            } else {
                current_fragment_id = ""; # 重置
            }
            in_fragment_block = 1;
            fragment_depth = 0; # 重置深度
        }
        in_fragment_block {
            # 如果在当前fragment块中找到panel_name_to_find
            if ($0 ~ panel_name_to_find && current_fragment_id != "") {
                print current_fragment_id; # 打印找到的数字ID
                exit; # 找到后退出awk
            }

            # 更新深度
            fragment_depth += gsub(/{/, "&") - gsub(/}/, "&");

            # 如果fragment块结束且未找到panel_name_to_find
            if (fragment_depth == 0) {
                in_fragment_block = 0; # 退出当前fragment块
                current_fragment_id = ""; # 清除ID
            }
        }
    ' "$target_file")

    if [ -z "$FRAGID" ]; then
        print_error "未能找到包含 ${PANEL_NODE_NAME} 的 fragment@NN 定义。"
        return
    fi
    print_success "自动检测到 Fragment ID: ${FRAGID}"
    
    local GEAR_LINES_INFO=""
    print_info "正在扫描 fragment@${FRAGID} 以查找档位..."
    GEAR_LINES_INFO=$(awk -v FRAG_ID_NUM="$FRAGID" '
        BEGIN { in_target_fragment=0; frag_depth=0; }
        {
            # 匹配 fragment@<FRAG_ID_NUM> {
            if (match($0, "^[ \t]*fragment@" FRAG_ID_NUM "[ \t]*\\{")) {
                in_target_fragment=1;
                frag_depth=0; # 重置深度
            }

            if (in_target_fragment) {
                # 提取 framerate
                if (match($0, /qcom,mdss-dsi-panel-framerate = <0x([0-9a-fA-F]+)>;/, arr)) {
                    printf("%d,%s,%s\n", NR, "framerate", arr[1]);
                }
                # 提取 clockrate
                if (match($0, /qcom,mdss-dsi-panel-clockrate = <0x([0-9a-fA-F]+)>;/, arr)) {
                    printf("%d,%s,%s\n", NR, "clockrate", arr[1]);
                }

                # 更新深度
                frag_depth += gsub(/{/, "&") - gsub(/}/, "&");

                # 如果当前fragment块结束
                if (frag_depth == 0) {
                    in_target_fragment=0;
                }
            }
        }
    ' "$target_file")

    if [ -z "$GEAR_LINES_INFO" ]; then
        print_error "在 fragment@${FRAGID} 中未能检测到任何刷新率或时钟频率参数。"
        return
    fi
    
    echo -e "${YELLOW}---------------------------------------${NC}"
    print_info "在 fragment@${FRAGID} 中检测到以下参数："
    local gear_count=0
    for line in $GEAR_LINES_INFO; do
        gear_count=$((gear_count + 1))
        local line_num=$(echo "$line" | cut -d',' -f1)
        local param_name=$(echo "$line" | cut -d',' -f2)
        local param_hex=$(echo "$line" | cut -d',' -f3)
        local param_dec=$(printf "%d" "0x$param_hex")
        
        echo -e "${PURE}参数 ${gear_count} (行 ${line_num}, ${param_name}):${NC}"
        if [ "$param_name" = "framerate" ]; then
            echo -e "  - ${GREEN}当前值: ${param_dec} Hz${NC} (0x$param_hex)"
        else
            echo -e "  - ${GREEN}当前值: ${param_dec}${NC} (0x$param_hex)"
        fi
    done
    echo -e "${YELLOW}---------------------------------------${NC}"

    echo -e "${YELLOW}请选择修改模式:${NC}"
    echo -e "${GREEN}1. 逐一修改每个参数${NC}"
    echo -e "${GREEN}2. 统一修改 (将所有同类参数修改为同一个值)${NC}"
    read -p "请选择: " modify_mode

    local patched_count=0
    if [ "$modify_mode" = "1" ]; then
        # 档位制修改
        local gear_index=0
        for line in $GEAR_LINES_INFO; do
            gear_index=$((gear_index + 1))
            local line_num=$(echo "$line" | cut -d',' -f1)
            local param_name=$(echo "$line" | cut -d',' -f2)
            local old_hex=$(echo "$line" | cut -d',' -f3)
            local old_dec=$(printf "%d" "0x$old_hex")

            echo -e "${YELLOW}--- 正在修改参数 ${gear_index} (行 ${line_num}, ${param_name}) [当前: ${old_dec}] ---${NC}"
            read -p "是否修改此参数? (y/n, 默认 n): " confirm_modify
            if [ "$confirm_modify" != "y" ] && [ "$confirm_modify" != "Y" ]; then
                print_info "已跳过参数 ${gear_index}。"
                continue
            fi

            read -p "请输入新的十进制值: " new_dec
            if ! [[ "$new_dec" =~ ^[0-9]+$ ]]; then print_error "无效输入"; continue; fi
            local new_hex=$(printf "%x" "$new_dec")

            print_info "正在将行 ${line_num} 的值修改为 ${new_dec} (0x${new_hex})..."
            # 使用 sed 精确替换指定行中的旧十六进制值
            sed -i "${line_num}s/<0x${old_hex}>/<0x${new_hex}>/" "$target_file"
            print_success "行 ${line_num} 修改完成。"
            patched_count=$((patched_count + 1))
        done

    elif [ "$modify_mode" = "2" ]; then
        # 统一修改
        read -p "请输入统一的新刷新率 (十进制): " new_fr_dec
        if ! [[ "$new_fr_dec" =~ ^[0-9]+$ ]]; then print_error "无效输入"; return; fi
        local new_fr_hex=$(printf "%x" "$new_fr_dec")

        read -p "请输入统一的新时钟频率 (十进制): " new_cr_dec
        if ! [[ "$new_cr_dec" =~ ^[0-9]+$ ]]; then print_error "无效输入"; return; fi
        local new_cr_hex=$(printf "%x" "$new_cr_dec")

        print_info "正在统一修改所有检测到的参数..."
        for line in $GEAR_LINES_INFO; do
            local line_num=$(echo "$line" | cut -d',' -f1)
            local param_name=$(echo "$line" | cut -d',' -f2)
            local old_hex=$(echo "$line" | cut -d',' -f3)

            if [ "$param_name" = "framerate" ]; then
                # 使用 sed 精确替换指定行中的旧十六进制值
                sed -i "${line_num}s/<0x${old_hex}>/<0x${new_fr_hex}>/" "$target_file"
                print_success "行 ${line_num} (framerate) 已修改。"
            else
                # 使用 sed 精确替换指定行中的旧十六进制值
                sed -i "${line_num}s/<0x${old_hex}>/<0x${new_cr_hex}>/" "$target_file"
                print_success "行 ${line_num} (clockrate) 已修改。"
            fi
        done
        patched_count=1 # 只要执行了就认为有修改
    else
        print_error "无效的模式选择。"
        return
    fi

    if [ "$patched_count" -eq 0 ]; then
        print_warning "未进行任何修改。"
        return
    else
        print_success "DTS文件修改完成。"
    fi

    recompile_dtb
    if [ $? -ne 0 ]; then return; fi

    local new_dtbo_filename="dtbo_modified_$(date +'%Y%m%d_%H%M%S').img"
    local output_path="$OUTPUT_DTBO_DIR/$new_dtbo_filename"
    pack_dtbo "$output_path"
    if [ $? -ne 0 ]; then return; fi

    print_success "新的DTBO文件已生成并保存到: $output_path"
    flash_dtbo "$output_path"
}

# --- 脚本执行流程 ---
check_root
setup_workspace

url_online="https://raw.githubusercontent.com/ptcry/k60screen_overclocker/refs/heads/main"
LOG_FILE="$LOG_DIR/$(date +'%Y%m%d_%H%M%S').log"
touch "$LOG_FILE"

clear

print_info "======================================="
print_info "            K60 屏幕超频工具  "
print_info "======================================="
print_info ""
print_info "所有输出将保存到日志文件: $LOG_FILE"
print_info ""

check_tools
get_phone_info
detect_ab

backup_dtbo
cleanup_old_logs

main_menu

