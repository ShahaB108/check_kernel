#!/bin/bash
# CVE-2026-31431 Kernel Checker + Boot Safety (Stable Version)

# Colors
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
CYAN='\e[36m'
RESET='\e[0m'

echo -e "${CYAN}=== CVE-2026-31431 Kernel Checker + Boot Safety ===${RESET}"
echo -e "Current time : $(date)"
echo

# === Safe Uptime Check ===
UPTIME=$(uptime -p)
# Safe uptime days calculation
UPTIME_DAYS=$(awk '{print int($1 / 86400)}' /proc/uptime)

echo -e "${CYAN}Uptime           :${RESET} $UPTIME (${UPTIME_DAYS} days)"
if [ "$UPTIME_DAYS" -ge 1 ]; then
    echo -e "${YELLOW}⚠️  Server has been running for more than 1 day.${RESET}"
fi
echo

RUNNING_KERNEL=$(uname -r)
echo -e "${CYAN}Running kernel   :${RESET} $RUNNING_KERNEL"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_VERSION=${VERSION_ID%%.*}
fi

# Minimum patched version
case $OS_VERSION in
    8)  MIN_KERNEL="4.18.0-553.121.1.el8_10" ;;
    9)  MIN_KERNEL="5.14.0-611.49.2.el9_7" ;;
    10) MIN_KERNEL="6.12.0-124.52.2.el10_1" ;;
    *)  MIN_KERNEL="0" ;;
esac

echo -e "${CYAN}Detected OS      :${RESET} $NAME $VERSION_ID"
echo -e "${CYAN}Required minimum :${RESET} $MIN_KERNEL"
echo

# Version comparison
version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1 | grep -q "^$2$"
    return $?
}

RUNNING_OK=$(version_ge "$RUNNING_KERNEL" "$MIN_KERNEL" && echo true || echo false)

echo -e "${CYAN}=== Status ===${RESET}"
if [ "$RUNNING_OK" = true ]; then
    echo -e "${GREEN}✅ Running kernel is PATCHED${RESET}"
else
    echo -e "${RED}❌ Running kernel is VULNERABLE${RESET}"
fi

echo
echo -e "${CYAN}=== Installed Kernels ===${RESET}"
rpm -qa kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | while read -r k; do
    if version_ge "$k" "$MIN_KERNEL"; then
        echo -e "   ${GREEN}✅ $k${RESET}"
    else
        echo -e "   ${RED}❌ $k  (vulnerable)${RESET}"
    fi
done

echo
echo -e "${CYAN}=== /boot Disk Usage ===${RESET}"
if mountpoint -q /boot 2>/dev/null; then
    BOOT_USAGE=$(df /boot | awk 'NR==2 {gsub("%","",$5); print $5}')
    BOOT_AVAIL=$(df -h /boot | awk 'NR==2 {print $4}')
    BOOT_TOTAL=$(df -h /boot | awk 'NR==2 {print $2}')
    echo "Usage     : ${BOOT_USAGE}%   |   Free: ${BOOT_AVAIL} / ${BOOT_TOTAL}"
    
    if [ "$BOOT_USAGE" -ge 85 ]; then
        echo -e "${RED}❌ CRITICAL: /boot is almost full!${RESET}"
    elif [ "$BOOT_USAGE" -ge 70 ]; then
        echo -e "${YELLOW}⚠️  Warning: /boot usage is high${RESET}"
    else
        echo -e "${GREEN}✅ /boot has enough space${RESET}"
    fi
else
    echo -e "${YELLOW}⚠️  /boot is not a separate mountpoint (using root /)${RESET}"
    df -h /
fi

echo
echo -e "${CYAN}=== Default Boot Kernel ===${RESET}"
if command -v grubby >/dev/null 2>&1; then
    DEFAULT_KERNEL=$(grubby --default-kernel 2>/dev/null)
    if [ -n "$DEFAULT_KERNEL" ]; then
        DEFAULT_VERSION=$(basename "$DEFAULT_KERNEL" | sed 's/vmlinuz-//')
        echo "Default   : $DEFAULT_VERSION"
        
        if version_ge "$DEFAULT_VERSION" "$MIN_KERNEL"; then
            echo -e "${GREEN}✅ Default boot kernel is PATCHED ✓${RESET}"
        else
            echo -e "${RED}❌ Default boot kernel is VULNERABLE!${RESET}"
        fi
    fi
fi

echo
echo -e "${CYAN}=== Initramfs Check ===${RESET}"
NEWEST_KERNEL=$(rpm -qa kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -1)
if [ -n "$NEWEST_KERNEL" ]; then
    echo "Newest kernel : $NEWEST_KERNEL"
    if [ -f "/boot/initramfs-${NEWEST_KERNEL}.img" ]; then
        SIZE=$(ls -sh "/boot/initramfs-${NEWEST_KERNEL}.img" 2>/dev/null | awk '{print $1}')
        echo -e "${GREEN}✅ Initramfs exists (${SIZE})${RESET}"
    else
        echo -e "${RED}❌ Initramfs missing!${RESET}"
        echo "   Fix: sudo dracut -f /boot/initramfs-${NEWEST_KERNEL}.img ${NEWEST_KERNEL}"
    fi
fi

echo
echo -e "${CYAN}=== Recommendations ===${RESET}"

if [ "$RUNNING_OK" = true ] && version_ge "$DEFAULT_VERSION" "$MIN_KERNEL"; then
    echo -e "${GREEN}🎉 System is fully protected!${RESET}"
    echo "   No reboot needed right now."
else
    if [ "$RUNNING_OK" = false ]; then
        echo -e "${YELLOW}• Update kernel:${RESET}"
        echo "  dnf update kernel --enablerepo=*-testing"
    fi

    if [ -n "$DEFAULT_VERSION" ] && ! version_ge "$DEFAULT_VERSION" "$MIN_KERNEL"; then
        echo -e "${YELLOW}• Set newest kernel as default:${RESET}"
        echo "  sudo grubby --set-default=/boot/vmlinuz-\$(rpm -qa kernel --qf '%{VERSION}-%{RELEASE}' | sort -V | tail -1)"
    fi

    echo -e "${YELLOW}• Reboot after changes${RESET}"
fi

echo
echo -e "${CYAN}Tip:${RESET} Keep at least 100MB free in /boot to avoid kernel panic."
