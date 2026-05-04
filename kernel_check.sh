#!/bin/bash
# CVE-2026-31431 (Copy Fail) Kernel Checker + Default Boot Check
# For AlmaLinux / CloudLinux

echo "=== CVE-2026-31431 Kernel Checker + Boot Status ==="
echo "Current time: $(date)"
echo

# Get running kernel
RUNNING_KERNEL=$(uname -r)
echo "Running kernel     : $RUNNING_KERNEL"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=${NAME,,}
    OS_VERSION=${VERSION_ID%%.*}
else
    echo "❌ Cannot detect OS"
    exit 1
fi

echo "Detected OS        : $NAME $VERSION_ID"
echo

# Minimum patched kernels
case $OS_VERSION in
    8)  MIN_KERNEL="4.18.0-553.121.1.el8_10" ;;
    9)  MIN_KERNEL="5.14.0-611.49.2.el9_7" ;;
    10) MIN_KERNEL="6.12.0-124.52.2.el10_1" ;;
    *)  echo "⚠️ Unsupported version: $OS_VERSION"; exit 1 ;;
esac

echo "Required minimum   : $MIN_KERNEL"
echo

# Version comparison function
version_ge() {
    printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1 | grep -q "^$2$"
    return $?
}

# === Check Running Kernel ===
if version_ge "$RUNNING_KERNEL" "$MIN_KERNEL"; then
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
echo "=== Default Boot Kernel (what will boot after reboot) ==="

if command -v grubby >/dev/null 2>&1; then
    DEFAULT_KERNEL=$(grubby --default-kernel 2>/dev/null)
    if [ -n "$DEFAULT_KERNEL" ]; then
        DEFAULT_VERSION=$(basename "$DEFAULT_KERNEL" | sed 's/vmlinuz-//')
        echo "Default kernel     : $DEFAULT_VERSION"
        
        if version_ge "$DEFAULT_VERSION" "$MIN_KERNEL"; then
            echo "✅ Default boot kernel is PATCHED ✓"
        else
            echo "❌ Default boot kernel is VULNERABLE!"
            echo "   You need to set the new kernel as default."
        fi
    else
        echo "⚠️ Could not detect default kernel via grubby"
    fi
else
    echo "⚠️ grubby command not found"
fi

echo
echo "=== Recommendations ==="
if ! version_ge "$RUNNING_KERNEL" "$MIN_KERNEL"; then
    echo "• Update kernel first:"
    echo "  dnf update kernel --enablerepo=*-testing"
    echo "  or for CloudLinux LTS:"
    echo "  dnf update 'kernel-lts*' --enablerepo=cloudlinux-updates-testing"
fi

if [ -n "$DEFAULT_KERNEL" ] && ! version_ge "$DEFAULT_VERSION" "$MIN_KERNEL"; then
    echo "• Set newest patched kernel as default:"
    echo "  grubby --set-default=/boot/vmlinuz-\$(rpm -qa kernel --qf '%{VERSION}-%{RELEASE}' | sort -V | tail -1)"
fi

echo "• Then reboot"
echo "• After reboot run this script again to verify"
