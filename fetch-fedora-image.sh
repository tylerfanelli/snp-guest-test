#!/bin/bash
set -euo pipefail

# Fedora Image Fetcher
# Downloads Fedora 41 Cloud Base x86_64 qcow2 image

FEDORA_VERSION="44"
IMAGE_TYPE="Cloud-Base"
ARCH="x86_64"
FORMAT="qcow2"
OUTPUT_DIR="./images"

# Base URL for Fedora cloud images
BASE_URL="https://download.fedoraproject.org/pub/fedora/linux/releases"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Construct the image filename and URL
IMAGE_NAME="Fedora-${IMAGE_TYPE}-${FEDORA_VERSION}-1.*.${ARCH}.${FORMAT}"
CHECKSUM_FILE="Fedora-${IMAGE_TYPE}-${FEDORA_VERSION}-1.*-CHECKSUM"

# Build the URL path
URL_PATH="${BASE_URL}/${FEDORA_VERSION}/Cloud/${ARCH}/images"

log_info "Fedora Image Fetcher"
log_info "===================="
log_info "Downloading Fedora ${FEDORA_VERSION} ${IMAGE_TYPE} ${ARCH} ${FORMAT}"
echo

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Fetch the image list to get exact filename
log_info "Fetching image list from ${URL_PATH}..."

# Get the directory listing
INDEX_HTML=$(mktemp)
trap 'rm -f ${INDEX_HTML}' EXIT

if ! curl -sL --max-time 30 "${URL_PATH}/" -o "${INDEX_HTML}"; then
    log_error "Failed to fetch image list from ${URL_PATH}"
    exit 1
fi

# Extract the actual image filename (Cloud images include "Generic" or "UEFI-UKI" in the name)
ACTUAL_IMAGE=$(grep -oP "Fedora-${IMAGE_TYPE}-Generic-${FEDORA_VERSION}-[0-9.]+\.${ARCH}\.${FORMAT}" "${INDEX_HTML}" | head -n 1)

if [[ -z "${ACTUAL_IMAGE}" ]]; then
    log_error "Could not find image matching pattern: ${IMAGE_NAME}"
    log_info "Available files at ${URL_PATH}:"
    grep -oP 'href="[^"]+\.(qcow2|raw|vmdk|iso)"' "${INDEX_HTML}" | cut -d'"' -f2 || true
    exit 1
fi

IMAGE_URL="${URL_PATH}/${ACTUAL_IMAGE}"
# Checksum file naming pattern (e.g., Fedora-Cloud-44-1.7-x86_64-CHECKSUM)
CHECKSUM_ACTUAL=$(grep -oP "Fedora-Cloud-${FEDORA_VERSION}-[0-9.]+-${ARCH}-CHECKSUM" "${INDEX_HTML}" | head -n 1)
CHECKSUM_URL="${URL_PATH}/${CHECKSUM_ACTUAL}"

log_info "Found image: ${ACTUAL_IMAGE}"

# Download checksum file
log_info "Downloading checksum file..."
CHECKSUM_PATH="${OUTPUT_DIR}/${CHECKSUM_ACTUAL}"
if ! curl -L --progress-bar --max-time 60 "${CHECKSUM_URL}" -o "${CHECKSUM_PATH}"; then
    log_error "Failed to download checksum file"
    exit 1
fi

# Download the image
IMAGE_PATH="${OUTPUT_DIR}/${ACTUAL_IMAGE}"

if [[ -f "${IMAGE_PATH}" ]]; then
    log_warn "Image already exists: ${IMAGE_PATH}"
    read -p "Do you want to re-download? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skipping download, verifying existing file..."
    else
        rm -f "${IMAGE_PATH}"
    fi
fi

if [[ ! -f "${IMAGE_PATH}" ]]; then
    log_info "Downloading image: ${ACTUAL_IMAGE}"
    log_info "This may take a while..."

    if ! curl -L --progress-bar --connect-timeout 30 "${IMAGE_URL}" -o "${IMAGE_PATH}"; then
        log_error "Failed to download image"
        rm -f "${IMAGE_PATH}"
        exit 1
    fi
fi

# Verify checksum
log_info "Verifying checksum..."
cd "${OUTPUT_DIR}"

# Extract the checksum for our specific file
EXPECTED_CHECKSUM=$(grep "${ACTUAL_IMAGE}" "${CHECKSUM_ACTUAL}" | grep "SHA256" | awk '{print $4}')

if [[ -z "${EXPECTED_CHECKSUM}" ]]; then
    log_warn "Could not find SHA256 checksum in checksum file"
else
    ACTUAL_CHECKSUM=$(sha256sum "${ACTUAL_IMAGE}" | awk '{print $1}')

    if [[ "${EXPECTED_CHECKSUM}" == "${ACTUAL_CHECKSUM}" ]]; then
        log_info "✓ Checksum verification passed"
    else
        log_error "✗ Checksum verification failed!"
        log_error "Expected: ${EXPECTED_CHECKSUM}"
        log_error "Got:      ${ACTUAL_CHECKSUM}"
        exit 1
    fi
fi

cd - > /dev/null

# Summary
echo
log_info "Download complete!"
log_info "Image location: ${IMAGE_PATH}"
log_info "Image size: $(du -h "${IMAGE_PATH}" | cut -f1)"

# Show usage hints
echo
log_info "Usage hints:"
echo "  # Use with QEMU/KVM:"
echo "  qemu-system-x86_64 -m 2048 -drive file=${IMAGE_PATH},format=qcow2"
echo
echo "  # Convert to other formats:"
echo "  qemu-img convert -f qcow2 -O raw ${IMAGE_PATH} output.raw"
