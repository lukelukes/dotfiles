#!/usr/bin/env bash
#
# Dotfiles Bootstrap Script
# Usage: curl -sSL https://raw.githubusercontent.com/USER/dotfiles/main/install.sh | bash -s -- <profile>
#
# Environment variables:
#   DOTFILES_REPO     - GitHub repo (default: USER/dotfiles)
#   DOTFILES_DIR      - Local clone directory (default: ~/.dotfiles)
#   BOOSTER_VERSION   - Version to download (default: 0.1.0)
#   SKIP_CHECKSUM     - Set to "1" to skip checksum validation (NOT recommended)
#
# Compatibility: Bash 3.2+ (macOS default bash is supported)
#

# Verify we're running in bash (not sh, dash, zsh, etc.)
# shellcheck disable=SC2292  # Intentional: [ ] works in sh/dash, [[ ]] doesn't
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: This script requires bash. Run with: bash $0" >&2
    exit 1
fi

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

DOTFILES_REPO="${DOTFILES_REPO:-lukelukes/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
BOOSTER_REPO="${BOOSTER_REPO:-lukelukes/booster}"
BOOSTER_VERSION="${BOOSTER_VERSION:-0.3.0}"

# SHA256 checksums for booster binaries
# Update these when releasing new versions of booster
# Generate with: sha256sum booster_*.tar.gz
get_checksum() {
    local platform="$1"
    case "$platform" in
        linux_amd64)  echo "cf886fc773cc977a615b21b30e31c954a1e1581c88b622ff7d933fe2b98ea871" ;;
        darwin_arm64) echo "eb18b3e76bf61223efe0a75a85de969f8ae76d3110995f3505cc3071aa258cb5" ;;
        *)            echo "" ;;
    esac
}

# =============================================================================
# Output Helpers
# =============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

info()    { printf '%b\n' "${BLUE}==> $*${NC}" >&2; }
success() { printf '%b\n' "${GREEN}✓ $*${NC}" >&2; }
warn()    { printf '%b\n' "${YELLOW}! $*${NC}" >&2; }
error()   { printf '%b\n' "${RED}✗ $*${NC}" >&2; }

die() {
    error "$@"
    exit 1
}

# =============================================================================
# Platform Detection
# =============================================================================

detect_os() {
    local os
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"

    case "$os" in
        linux)  echo "linux" ;;
        darwin) echo "darwin" ;;
        *)      die "Unsupported OS: $os (only linux and darwin are supported)" ;;
    esac
}

detect_arch() {
    local arch
    arch="$(uname -m)"

    case "$arch" in
        x86_64)          echo "amd64" ;;
        amd64)           echo "amd64" ;;
        aarch64|arm64)   echo "arm64" ;;
        *)               die "Unsupported architecture: $arch" ;;
    esac
}

# =============================================================================
# Checksum Validation
# =============================================================================

compute_sha256() {
    local file="$1"

    if command -v sha256sum &>/dev/null; then
        sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$file" | cut -d' ' -f1
    else
        die "No SHA256 tool available (need sha256sum or shasum)"
    fi
}

validate_checksum() {
    local file="$1"
    local expected="$2"

    if [[ "${SKIP_CHECKSUM:-}" == "1" ]]; then
        warn "Skipping checksum validation (SKIP_CHECKSUM=1)"
        return 0
    fi

    info "Validating checksum..."

    local actual
    actual="$(compute_sha256 "$file")"

    if [[ "$actual" != "$expected" ]]; then
        error "Checksum verification failed!"
        error "  Expected: $expected"
        error "  Got:      $actual"
        die "Binary may be corrupted or tampered with. Aborting."
    fi

    success "Checksum verified"
}

# =============================================================================
# Download
# =============================================================================

download() {
    local url="$1"
    local dest="$2"

    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget &>/dev/null; then
        wget -q "$url" -O "$dest"
    else
        die "No download tool available (need curl or wget)"
    fi
}

# =============================================================================
# Clone Dotfiles
# =============================================================================

clone_dotfiles() {
    info "Setting up dotfiles repository..."

    if ! command -v git &>/dev/null; then
        die "git is required but not installed"
    fi

    if [[ -d "$DOTFILES_DIR" ]]; then
        warn "Dotfiles directory already exists at $DOTFILES_DIR"
        info "Pulling latest changes..."

        if ! git -C "$DOTFILES_DIR" pull --ff-only 2>/dev/null; then
            warn "Could not pull (may have local changes), continuing with existing files"
        fi
    else
        info "Cloning https://github.com/$DOTFILES_REPO.git..."

        if ! git clone "https://github.com/$DOTFILES_REPO.git" "$DOTFILES_DIR"; then
            die "Failed to clone dotfiles repository"
        fi
    fi

    success "Dotfiles ready at $DOTFILES_DIR"
}

# =============================================================================
# Install Booster
# =============================================================================

install_booster() {
    local os="$1"
    local arch="$2"
    local platform="${os}_${arch}"

    info "Installing booster v${BOOSTER_VERSION} (${os}/${arch})..."

    # Get expected checksum
    local expected_checksum
    expected_checksum="$(get_checksum "$platform")"
    if [[ -z "$expected_checksum" ]]; then
        die "No checksum defined for platform: $platform"
    fi

    # Create temp directory with cleanup trap for error cases
    # Note: trap is removed on success path (see end of function)
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    # shellcheck disable=SC2064  # Intentional: capture $tmp_dir value now, not at signal time
    trap "rm -rf \"$tmp_dir\"" EXIT

    # Construct download URL
    # Assumes release artifacts are named: booster_VERSION_OS_ARCH.tar.gz
    local archive_name="booster_${BOOSTER_VERSION}_${platform}.tar.gz"
    local download_url="https://github.com/${BOOSTER_REPO}/releases/download/v${BOOSTER_VERSION}/${archive_name}"
    local archive_path="${tmp_dir}/${archive_name}"

    info "Downloading from GitHub releases..."
    # shellcheck disable=SC2310  # Intentional: we handle failure explicitly below
    if ! download "$download_url" "$archive_path"; then
        error "Failed to download booster"
        error "URL: $download_url"
        die "Check that version v${BOOSTER_VERSION} exists and has ${platform} binary"
    fi

    # Validate checksum BEFORE extracting
    validate_checksum "$archive_path" "$expected_checksum"

    # Extract
    info "Extracting..."
    if ! tar -xzf "$archive_path" -C "$tmp_dir"; then
        die "Failed to extract archive"
    fi

    # Find and install binary
    local binary_path="${tmp_dir}/booster"
    if [[ ! -f "$binary_path" ]]; then
        die "Binary not found in archive"
    fi

    chmod +x "$binary_path"

    # Install to dotfiles .bin directory
    local install_dir="${DOTFILES_DIR}/.bin"
    local install_path="${install_dir}/booster"

    mkdir -p "$install_dir"
    mv "$binary_path" "$install_path"

    # Clean up temp directory and remove trap (trap was for error cases)
    rm -rf "$tmp_dir"
    trap - EXIT

    success "Booster installed to $install_path"
    echo "$install_path"
}

# =============================================================================
# Run Bootstrap
# =============================================================================

run_booster() {
    local booster="$1"
    local profile="$2"
    local config="${DOTFILES_DIR}/bootstrap.yaml"

    if [[ ! -f "$config" ]]; then
        die "Bootstrap config not found: $config"
    fi

    info "Running booster with profile '$profile'..."
    echo ""

    # Execute booster
    "$booster" --config="$config" --profile="$profile"
}

# =============================================================================
# Usage
# =============================================================================

usage() {
    cat <<EOF
Dotfiles Bootstrap Script

Usage:
    curl -sSL <url>/install.sh | bash -s -- <profile>

Arguments:
    profile    The bootstrap profile to use (e.g., minimal, desktop, server)

Environment Variables:
    DOTFILES_REPO     GitHub repo for dotfiles (default: USER/dotfiles)
    DOTFILES_DIR      Local directory for dotfiles (default: ~/.dotfiles)
    BOOSTER_VERSION   Booster version to use (default: ${BOOSTER_VERSION})
    SKIP_CHECKSUM     Set to "1" to skip checksum validation

Examples:
    # Basic usage
    curl -sSL https://example.com/install.sh | bash -s -- desktop

    # With custom dotfiles repo
    DOTFILES_REPO=myuser/mydots curl -sSL https://example.com/install.sh | bash -s -- minimal

    # Download script first to inspect it (recommended)
    curl -sSL https://example.com/install.sh > install.sh
    less install.sh
    bash install.sh desktop

EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local profile="${1:-}"

    # Show usage if no profile provided
    if [[ -z "$profile" ]] || [[ "$profile" == "-h" ]] || [[ "$profile" == "--help" ]]; then
        usage
        [[ -z "$profile" ]] && exit 1
        exit 0
    fi

    echo ""
    echo "╔═══════════════════════════════════════╗"
    echo "║      Dotfiles Bootstrap               ║"
    echo "╚═══════════════════════════════════════╝"
    echo ""

    # Detect platform
    local os arch
    os="$(detect_os)"
    arch="$(detect_arch)"
    info "Detected platform: ${os}/${arch}"
    echo ""

    # Step 1: Clone dotfiles
    clone_dotfiles
    echo ""

    # Step 2: Download and install booster (with checksum validation)
    local booster_path
    booster_path="$(install_booster "$os" "$arch")"
    echo ""

    # Step 3: Run booster with the specified profile
    run_booster "$booster_path" "$profile"

    echo ""
    success "Bootstrap complete!"
    echo ""
}

main "$@"
