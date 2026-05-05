#!/bin/bash
# =============================================
# AlmaLinux CVE-2026-31431 Kernel Update + Safety Checker
# Uses IranServer mirrors - Supports AlmaLinux 8 & 9
# =============================================

set -euo pipefail

echo "=== AlmaLinux CVE-2026-31431 Kernel Update & Checker ==="
echo "Uptime       : $(uptime -p)"

# Detect version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
else
    echo "ERROR: Cannot detect AlmaLinux version"
    exit 1
fi

echo "Detected OS   : $PRETTY_NAME"
echo "Running kernel: $(uname -r)"
echo ""

# ====================== REPO SETUP ======================
echo "=== Setting up IranServer repositories ==="

cat > /etc/yum.repos.d/iranserver-almalinux.repo << 'EOF'
[baseos_iranserver]
name=AlmaLinux $releasever - BaseOS
baseurl=https://mirror.iranserver.com/almalinux/$releasever/BaseOS/$basearch/os/
enabled=1
gpgcheck=1
countme=1
gpgkey=https://mirror.iranserver.com/almalinux/RPM-GPG-KEY-AlmaLinux

[appstream_iranserver]
name=AlmaLinux $releasever - AppStream
baseurl=https://mirror.iranserver.com/almalinux/$releasever/AppStream/$basearch/os/
enabled=1
gpgcheck=1
countme=1
gpgkey=https://mirror.iranserver.com/almalinux/RPM-GPG-KEY-AlmaLinux

[extras_iranserver]
name=AlmaLinux $releasever - Extras
baseurl=https://mirror.iranserver.com/almalinux/$releasever/extras/$basearch/os/
enabled=1
gpgcheck=1
countme=1
gpgkey=https://mirror.iranserver.com/almalinux/RPM-GPG-KEY-AlmaLinux

[epel_iranserver]
name=Extra Packages for Enterprise Linux $releasever - $basearch
baseurl=https://mirror.iranserver.com/epel/$releasever/Everything/$basearch
enabled=1
gpgcheck=1
gpgkey=https://mirror.iranserver.com/epel/RPM-GPG-KEY-EPEL-$releasever
EOF

# Enable needed repos
if [ "$MAJOR_VERSION" -eq 8 ]; then
    dnf config-manager --set-enabled powertools_iranserver 2>/dev/null || true
elif [ "$MAJOR_VERSION" -eq 9 ]; then
    dnf config-manager --set-enabled crb 2>/dev/null || true
fi

dnf clean all --enablerepo=* >/dev/null 2>&1

# ====================== UPDATE KERNEL ======================
echo "=== Updating system and installing latest kernel ==="

dnf update -y --refresh --disablerepo=* --enablerepo=*_iranserver
dnf install -y kernel kernel-core kernel-modules --disablerepo=* --enablerepo=*_iranserver

echo "=== Update completed ==="

# ====================== CVE CHECKER ======================
echo ""
echo "=== CVE-2026-31431 Kernel Checker ==="

if [ "$MAJOR_VERSION" -eq 8 ]; then
    MIN_VERSION="4.18.0-553.121.1"
    PATCHED_SUFFIX="el8_10"
elif [ "$MAJOR_VERSION" -eq 9 ]; then
    MIN_VERSION="5.14.0-611.49.2"
    PATCHED_SUFFIX="el9_7"
else
    echo "Unsupported version"
    exit 1
fi

CURRENT=$(uname -r)
CURRENT_BASE=${CURRENT%%.el*}

echo "Required minimum : ${MIN_VERSION}.${PATCHED_SUFFIX}"
echo ""

# Check installed kernels
echo "=== Installed Kernels ==="
rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | while read -r k; do
    if [[ "$k" == *"$MIN_VERSION"* || "${k%%.el*}" > "$MIN_VERSION" ]]; then
        echo "   ✅ $k (patched)"
    else
        echo "   ❌ $k (vulnerable)"
    fi
done

# Boot kernel check
DEFAULT_KERNEL=$(grubby --default-kernel 2>/dev/null | xargs -I {} basename {} .x86_64 || echo "unknown")
echo ""
echo "=== Default Boot Kernel ==="
if [[ "$DEFAULT_KERNEL" == *"$MIN_VERSION"* || "${DEFAULT_KERNEL%%.el*}" > "$MIN_VERSION" ]]; then
    echo "   ✅ $DEFAULT_KERNEL (PATCHED)"
else
    echo "   ❌ $DEFAULT_KERNEL (VULNERABLE)"
fi

# /boot space
echo ""
echo "=== /boot Disk Usage ==="
df -h /boot

echo ""
if [[ "$CURRENT_BASE" > "$MIN_VERSION" || "$CURRENT_BASE" == "$MIN_VERSION" ]]; then
    echo "✅ Running kernel is PATCHED"
else
    echo "❌ Running kernel is VULNERABLE"
fi

echo ""
echo "After reboot run: "curl -fsSL https://raw.githubusercontent.com/ShahaB108/CVE-2026-31431_Kernel_Checker/main/kernel_check.sh | bash""
echo ""
