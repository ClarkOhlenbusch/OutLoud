#!/usr/bin/env bash
set -euo pipefail

# Scripts/version.sh: Automated version management and pre-flight validation
# for OutLoud iOS application.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_YML="$ROOT_DIR/project.yml"
PBXPROJ="$ROOT_DIR/OutLoud.xcodeproj/project.pbxproj"
READY_TO_SUBMIT="$ROOT_DIR/AppStore/READY_TO_SUBMIT.md"
METADATA="$ROOT_DIR/AppStore/metadata.md"

# Known closed version trains on App Store Connect (cannot be reused)
CLOSED_TRAINS=("1.0.0")

get_marketing_version() {
    grep "MARKETING_VERSION:" "$PROJECT_YML" | head -n 1 | awk '{print $2}' | tr -d '"'
}

get_build_number() {
    grep "CURRENT_PROJECT_VERSION:" "$PROJECT_YML" | head -n 1 | awk '{print $2}' | tr -d '"'
}

cmd_get() {
    local m_ver b_num
    m_ver="$(get_marketing_version)"
    b_num="$(get_build_number)"
    echo "MARKETING_VERSION=$m_ver"
    echo "CURRENT_PROJECT_VERSION=$b_num"
    echo "FULL_VERSION=$m_ver ($b_num)"
}

cmd_verify() {
    local yml_m yml_b pbx_m pbx_b
    yml_m="$(get_marketing_version)"
    yml_b="$(get_build_number)"
    pbx_m="$(grep "MARKETING_VERSION =" "$PBXPROJ" | head -n 1 | sed -E 's/.*= (.*);/\1/' | tr -d ' "')"
    pbx_b="$(grep "CURRENT_PROJECT_VERSION =" "$PBXPROJ" | head -n 1 | sed -E 's/.*= (.*);/\1/' | tr -d ' "')"

    echo "Verifying version configuration..."
    echo "  project.yml:          $yml_m ($yml_b)"
    echo "  project.pbxproj:      $pbx_m ($pbx_b)"

    if [[ "$yml_m" != "$pbx_m" ]]; then
        echo "ERROR: Marketing version mismatch: project.yml ($yml_m) != pbxproj ($pbx_m)" >&2
        exit 1
    fi
    if [[ "$yml_b" != "$pbx_b" ]]; then
        echo "ERROR: Build number mismatch: project.yml ($yml_b) != pbxproj ($pbx_b)" >&2
        exit 1
    fi

    # Check closed pre-release trains
    for closed in "${CLOSED_TRAINS[@]}"; do
        if [[ "$yml_m" == "$closed" ]]; then
            echo "ERROR: Version train '$yml_m' is closed on App Store Connect." >&2
            echo "       App Store rejection 90062 / 90186: CFBundleShortVersionString must be higher than approved version ($closed)." >&2
            echo "       Run: ./Scripts/version.sh bump patch (or minor) to prepare next release." >&2
            exit 1
        fi
    done

    echo "OK: Version $yml_m ($yml_b) is consistent and eligible for App Store submission."
}

cmd_set() {
    local new_m="$1"
    local new_b="$2"

    for closed in "${CLOSED_TRAINS[@]}"; do
        if [[ "$new_m" == "$closed" ]]; then
            echo "ERROR: Cannot set version to '$new_m'. That version train is closed." >&2
            exit 1
        fi
    done

    echo "Setting version to $new_m (Build $new_b)..."

    # 1. Update project.yml
    sed -i '' -E "s/(MARKETING_VERSION: ).*/\1$new_m/" "$PROJECT_YML"
    sed -i '' -E "s/(CURRENT_PROJECT_VERSION: ).*/\1$new_b/" "$PROJECT_YML"

    # 2. Update project.pbxproj
    sed -i '' -E "s/(MARKETING_VERSION = ).*;/MARKETING_VERSION = $new_m;/" "$PBXPROJ"
    sed -i '' -E "s/(CURRENT_PROJECT_VERSION = ).*;/CURRENT_PROJECT_VERSION = $new_b;/" "$PBXPROJ"

    # 3. Update AppStore/metadata.md if exists
    if [[ -f "$METADATA" ]]; then
        sed -i '' -E "s/(- Version: ).*/\1\`$new_m\`/" "$METADATA"
    fi

    # 4. Update AppStore/READY_TO_SUBMIT.md if exists
    if [[ -f "$READY_TO_SUBMIT" ]]; then
        sed -i '' -E "s/(\\| Version \\| ).*/\1\`$new_m\` |/" "$READY_TO_SUBMIT"
        sed -i '' -E "s/(Next build to upload: ).*/\1\`$new_m ($new_b)\`/" "$READY_TO_SUBMIT"
    fi

    echo "Successfully updated version to $new_m ($new_b)."
}

cmd_bump() {
    local component="${1:-patch}"
    local explicit_build="${2:-}"

    local curr_m curr_b
    curr_m="$(get_marketing_version)"
    curr_b="$(get_build_number)"

    IFS='.' read -r major minor patch <<< "$curr_m"
    major="${major:-1}"
    minor="${minor:-0}"
    patch="${patch:-0}"

    case "$component" in
        patch)
            patch=$((patch + 1))
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        *)
            echo "ERROR: Unknown component '$component'. Choose patch, minor, or major." >&2
            exit 1
            ;;
    esac

    local next_m="$major.$minor.$patch"
    local next_b
    if [[ -n "$explicit_build" ]]; then
        next_b="$explicit_build"
    else
        next_b=$((curr_b + 1))
    fi

    cmd_set "$next_m" "$next_b"
}

usage() {
    cat <<EOF
Usage: Scripts/version.sh <command> [args]

Commands:
  get                         Print current marketing version and build number
  verify                      Check version consistency and ensure train is not closed
  bump [patch|minor|major]    Increment marketing version and build number (default: patch)
  set <version> <build>       Set explicit marketing version (e.g. 1.0.1) and build (e.g. 5)

Examples:
  ./Scripts/version.sh get
  ./Scripts/version.sh verify
  ./Scripts/version.sh bump patch
  ./Scripts/version.sh set 1.0.1 5
EOF
}

case "${1:-}" in
    get)
        cmd_get
        ;;
    verify)
        cmd_verify
        ;;
    bump)
        cmd_bump "${2:-patch}" "${3:-}"
        ;;
    set)
        if [[ $# -lt 3 ]]; then
            echo "ERROR: 'set' requires <version> and <build>" >&2
            exit 1
        fi
        cmd_set "$2" "$3"
        ;;
    *)
        usage
        exit 1
        ;;
esac
