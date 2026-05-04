#!/bin/bash
# CVE-2026-31431 Kernel Checker + Smart Recommendations
# For AlmaLinux / CloudLinux

echo "=== CVE-2026-31431 Kernel Checker + Boot Status ==="
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

# Version comparison
version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1 | grep -q "^$2$"
    return $?
}

# Checks
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
echo "=== Recommendations ==="

if [ "$RUNNING_OK" = true ] && version_ge "$DEFAULT_VERSION" "$MIN_KERNEL"; then
    echo "🎉 Your system is fully protected!"
    echo "   No reboot needed."
    echo
    echo "Optional cleanup (remove old vulnerable kernels):"
    echo "   sudo dnf remove \$(rpm -qa kernel | grep -E '4.18.0-553\.(83|89)')"
else
    if [ "$RUNNING_OK" = false ]; then
        echo "• Update kernel:"
        echo "  sudo dnf update kernel --enablerepo=*-testing"
        echo "  or for CloudLinux:"
        echo "  sudo dnf update 'kernel-lts*' --enablerepo=cloudlinux-updates-testing"
    fi

    if ! version_ge "$DEFAULT_VERSION" "$MIN_KERNEL"; then
        echo "• Set newest kernel as default:"
        echo "  sudo grubby --set-default=/boot/vmlinuz-\$(rpm -qa kernel --qf '%{VERSION}-%{RELEASE}' | sort -V | tail -1)"
    fi

    echo "• Reboot the server"
    echo "• Run this script again after reboot to confirm"
fi

echo
echo "Note: You can keep old kernels for fallback, or remove them for cleanup."
