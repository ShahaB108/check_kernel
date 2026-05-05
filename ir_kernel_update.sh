#!/usr/bin/env bash
# =============================================
# AlmaLinux CVE-2026-31431 Kernel Update + Checker (Fixed)
# Uses IranServer mirrors
# By sh.rahimpour , TechSupp
# =============================================

set -euo pipefail

echo "=== AlmaLinux CVE-2026-31431 Kernel Update & Checker ==="
echo "Uptime       : $(uptime -p)"
echo "Running kernel: $(uname -r)"
echo ""

# Detect version
. /etc/os-release
MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)

echo "Detected OS   : $PRETTY_NAME"

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

dnf clean all --enablerepo=* >/dev/null 2>&1

# ====================== FIX CONFLICTS ======================
echo "=== Removing old kernel devel/tools packages to avoid conflicts ==="

dnf remove -y --noautoremove kernel-devel kernel-headers \
    kernel-tools kernel-tools-libs kernel-tools-libs-devel 2>/dev/null || true

# ====================== UPDATE KERNEL ======================
echo "=== Updating system and installing latest kernel ==="

dnf update -y --refresh --disablerepo=* --enablerepo=baseos_iranserver --enablerepo=epel_iranserver

dnf install -y kernel kernel-core kernel-modules \
    --disablerepo=* --enablerepo=baseos_iranserver

echo "=== Update completed ==="

# ====================== CVE CHECKER ======================
echo ""
echo "=== CVE-2026-31431 Kernel Checker ==="

if [ "$MAJOR_VERSION" -eq 8 ]; then
    MIN_VERSION="4.18.0-553.121.1"
elif [ "$MAJOR_VERSION" -eq 9 ]; then
    MIN_VERSION="5.14.0-611.49.2"
else
    echo "Unsupported version"
    exit 1
fi

echo "Required minimum : $MIN_VERSION"
echo ""

# Installed kernels
echo "=== Installed Kernels ==="
rpm -qa kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | while read -r k; do
    if [[ "$k" == *"$MIN_VERSION"* ]]; then
        echo "   ✅ $k (patched)"
    else
        echo "   ❌ $k (vulnerable)"
    fi
done

# Default boot kernel
DEFAULT_KERNEL=$(grubby --default-kernel 2>/dev/null | sed 's|.*/||' | sed 's|\.x86_64||' || echo "unknown")
echo ""
echo "=== Default Boot Kernel ==="
if [[ "$DEFAULT_KERNEL" == *"$MIN_VERSION"* ]]; then
    echo "   ✅ $DEFAULT_KERNEL (PATCHED ✓)"
else
    echo "   ❌ $DEFAULT_KERNEL (VULNERABLE)"
fi

echo ""
df -h /boot
echo ""

CURRENT_BASE=$(uname -r | cut -d. -f1-4)
if [[ "$CURRENT_BASE" > "$MIN_VERSION" || "$CURRENT_BASE" == "$MIN_VERSION" ]]; then
    echo "✅ Running kernel is PATCHED"
else
    echo "❌ Running kernel is VULNERABLE"
fi

echo ""
echo "After reboot, check with:"
echo "curl -fsSL https://raw.githubusercontent.com/ShahaB108/CVE-2026-31431_Kernel_Checker/main/kernel_check.sh | bash"
echo ""
