#!/bin/bash
set -e

# SEV-SNP Guest Launch Script
# Launches a Fedora VM with SEV-SNP protection

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_DIR="${SCRIPT_DIR}/images"
QCOW2_IMAGE="${IMAGE_DIR}/fedora.qcow2"

# VM Configuration
VCPUS=2
MEMORY=2048  # 2 GB in MB

# Check if image exists
if [ ! -f "${QCOW2_IMAGE}" ]; then
    echo "Error: Fedora image not found at ${QCOW2_IMAGE}"
    echo "Please run ./fetch-fedora-image.sh first"
    exit 1
fi

# Check if QEMU is available
if ! command -v qemu-system-x86_64 &> /dev/null; then
    echo "Error: qemu-system-x86_64 not found"
    echo "Please install QEMU with SEV-SNP support"
    exit 1
fi

# Check for SEV-SNP support
if [ ! -e /dev/sev ]; then
    echo "Warning: /dev/sev not found. SEV-SNP may not be available on this system."
fi

echo "Starting SEV-SNP guest VM..."
echo "  vCPUs: ${VCPUS}"
echo "  Memory: ${MEMORY} MB"
echo "  Image: ${QCOW2_IMAGE}"
echo ""

# Launch QEMU with SEV-SNP
exec qemu-system-x86_64 \
    -machine q35,confidential-guest-support=sev0,memory-backend=ram1 \
    -cpu EPYC-v4 \
    -smp ${VCPUS},maxcpus=${VCPUS} \
    -m ${MEMORY} \
    -object memory-backend-memfd,id=ram1,size=${MEMORY}M,share=true,prealloc=false \
    -object sev-snp-guest,id=sev0,cbitpos=51,reduced-phys-bits=1 \
    -drive file="${QCOW2_IMAGE}",if=virtio,format=qcow2 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0,disable-legacy=on,iommu_platform=true \
    -nographic \
    -serial mon:stdio \
    -enable-kvm
