#!/bin/bash
# CVE-2026-31431 Kernel Checker + Boot Safety Features
# Includes /boot usage and initramfs validation

echo "=== CVE-2026-31431 Kernel Checker + Boot Safety ==="
echo "Current time: $(date)"
echo

RUNNING_KERNEL=$(uname -r)
echo "Running kernel     : $RUNNING_KERNEL"

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

echo "Detected OS        : $NAME $VERSION_ID"
echo "Required minimum   : $MIN_KERNEL"
echo

# Version comparison function
version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1 | grep -q "^$2$"
    return $?
}

RUNNING_OK=$(version_ge "$RUNNING_KERNEL" "$MIN_KERNEL" && echo true || echo false)

echo "=== Status ==="
if [ "$RUNNING_OK" = true ]; then
    echo "✅ Running kernel is PATCHED"
else
    echo "❌ Running kernel is VULNERABLE"
fi

echo
echo "=== Installed Kernels ==="
rpm -qa kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | while read -r k; do
    if version_ge "$k" "$MIN_KERNEL"; then
        echo "   ✅ $k"
    else
        echo "   ❌ $k  (vulnerable)"
    fi
done

echo
echo "=== /boot Disk Usage (Critical for Kernel Updates) ==="
if mountpoint -q /boot; then
    BOOT_USAGE=$(df -h /boot | awk 'NR==2 {print $5}' | sed 's/%//')
    BOOT_AVAIL=$(df -h /boot | awk 'NR==2 {print $4}')
    BOOT_TOTAL=$(df -h /boot | awk 'NR==2 {print $2}')
    echo "Usage : ${BOOT_USAGE}%   |   Available: ${BOOT_AVAIL} / ${BOOT_TOTAL}"
    
    if [ "$BOOT_USAGE" -ge 85 ]; then
        echo "❌ CRITICAL: /boot is almost full! Risk of kernel panic."
    elif [ "$BOOT_USAGE" -ge 70 ]; then
        echo "⚠️  Warning: /boot usage is high."
    else
        echo "✅ /boot has enough space."
    fi
else
    echo "⚠️  /boot is not a separate mountpoint (checking /)"
    df -h /
fi

echo
echo "=== Default Boot Kernel ==="
if command -v grubby >/dev/null 2>&1; then
    DEFAULT_KERNEL=$(grubby --default-kernel 2>/dev/null)
    if [ -n "$DEFAULT_KERNEL" ]; then
        DEFAULT_VERSION=$(basename "$DEFAULT_KERNEL" | sed 's/vmlinuz-//')
        echo "Default kernel     : $DEFAULT_VERSION"
        
        if version_ge "$DEFAULT_VERSION" "$MIN_KERNEL"; then
            echo "✅ Default boot kernel is PATCHED ✓"
        else
            echo "❌ Default boot kernel is VULNERABLE!"
        fi
    fi
fi

echo
echo "=== Initramfs Check for Newest Kernel ==="
NEWEST_KERNEL=$(rpm -qa kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -1)
if [ -n "$NEWEST_KERNEL" ]; then
    echo "Newest installed   : $NEWEST_KERNEL"
    if ls /boot/initramfs-${NEWEST_KERNEL}.img >/dev/null 2>&1; then
        INITRAMFS_SIZE=$(ls -sh /boot/initramfs-${NEWEST_KERNEL}.img 2>/dev/null | awk '{print $1}')
        echo "✅ Initramfs exists (${INITRAMFS_SIZE})"
    else
        echo "❌ Initramfs missing for newest kernel!"
        echo "   Run: sudo dracut -f /boot/initramfs-${NEWEST_KERNEL}.img ${NEWEST_KERNEL}"
    fi
fi

echo
echo "=== Recommendations ==="

if [ "$RUNNING_OK" = true ] && version_ge "$DEFAULT_VERSION" "$MIN_KERNEL"; then
    echo "🎉 Your system is fully protected!"
    echo "   No reboot needed at this moment."
else
    echo "• Update kernel:"
    echo "  sudo dnf update kernel --enablerepo=*-testing"
    echo "  CloudLinux LTS: sudo dnf update 'kernel-lts*' --enablerepo=cloudlinux-updates-testing"
fi

if [ -n "$DEFAULT_VERSION" ] && ! version_ge "$DEFAULT_VERSION" "$MIN_KERNEL"; then
    echo "• Set newest kernel as default:"
    echo "  sudo grubby --set-default=/boot/vmlinuz-\$(rpm -qa kernel --qf '%{VERSION}-%{RELEASE}' | sort -V | tail -1)"
fi

# Space warning
if [ "$BOOT_USAGE" -ge 70 ]; then
    echo "• ⚠️  Clean /boot before updating:"
    echo "  sudo package-cleanup --oldkernels --count=2"
    echo "  or manually remove old kernels"
fi

if [ "$RUNNING_OK" = false ] || ! version_ge "$DEFAULT_VERSION" "$MIN_KERNEL"; then
    echo "• Reboot after making changes"
    echo "• Run this script again after reboot"
fi

echo
echo "Tip: Keep at least 200-300MB free in /boot to avoid kernel panic."
