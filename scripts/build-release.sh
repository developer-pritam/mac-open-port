#!/bin/bash
# build-release.sh — clean release build + optional GitHub publish for PortBar
#
# Usage:
#   ./scripts/build-release.sh                          # build only
#   ./scripts/build-release.sh --version 1.0.1          # explicit version (also written to VERSION)
#   ./scripts/build-release.sh --publish                # build + publish to GitHub Releases
#   ./scripts/build-release.sh --version 1.0.1 --publish
#   ./scripts/build-release.sh --publish --draft        # publish as draft (review before going live)
#
# Requires: Xcode command line tools, gh (GitHub CLI) for --publish — brew install gh
# Output:   dist/PortBar-<version>.zip and dist/PortBar.zip (stable download name)

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

step()  { echo -e "\n${BLUE}${BOLD}▶ $1${RESET}"; }
ok()    { echo -e "${GREEN}${BOLD}✓ $1${RESET}"; }
warn()  { echo -e "${YELLOW}⚠ $1${RESET}"; }
fail()  { echo -e "${RED}${BOLD}✗ $1${RESET}"; exit 1; }

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="PortBar"
DIST_DIR="$PROJECT_ROOT/dist"
APP_PATH="$PROJECT_ROOT/build/${APP_NAME}.app"

# ── Parse arguments ───────────────────────────────────────────────────────────
VERSION=""
PUBLISH=false
DRAFT=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --publish) PUBLISH=true; shift ;;
        --draft)   DRAFT=true;   shift ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

cd "$PROJECT_ROOT"
if [[ -n "$VERSION" ]]; then
    echo "$VERSION" > VERSION
else
    VERSION=$(cat VERSION)
fi

ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo -e "\n${BOLD}Building ${APP_NAME} v${VERSION}${RESET}"
echo "────────────────────────────────────────"

# ── Step 1: Clean build ───────────────────────────────────────────────────────
step "Cleaning previous build"
rm -rf .build/apple build
mkdir -p "$DIST_DIR"
ok "Clean complete"

step "Building universal release (arm64 + x86_64)"
VERSION="$VERSION" ./build.sh > /dev/null || fail "Build failed — run ./build.sh to see the errors"
[[ -d "$APP_PATH" ]] || fail ".app not found at $APP_PATH"
ok "App bundle: build/${APP_NAME}.app ($(du -sh "$APP_PATH" | cut -f1), $(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME"))"

# ── Step 2: Package ───────────────────────────────────────────────────────────
step "Packaging"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Also create a generic PortBar.zip — stable download URL that never changes.
GENERIC_ZIP_PATH="$DIST_DIR/${APP_NAME}.zip"
cp "$ZIP_PATH" "$GENERIC_ZIP_PATH"
ok "Zip created: dist/$ZIP_NAME ($(du -sh "$ZIP_PATH" | cut -f1))"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────────────"
echo -e "${GREEN}${BOLD}✅ Release ready${RESET}"
echo -e "   File:    ${BOLD}dist/$ZIP_NAME${RESET}"
echo -e "   Version: $VERSION"
echo ""

# ── Step 3: Publish ───────────────────────────────────────────────────────────
if [[ "$PUBLISH" == true ]]; then
    step "Publishing to GitHub Releases"

    command -v gh &>/dev/null || fail "GitHub CLI (gh) not found. Install with: brew install gh"
    gh auth status &>/dev/null || fail "Not logged in to GitHub CLI. Run: gh auth login"

    TAG="v${VERSION}"
    RELEASE_NOTES="## What's new in ${VERSION}

<!-- TODO: describe what changed in this release -->

---

### Installation
1. Download \`${APP_NAME}.zip\` below
2. Unzip and move **PortBar.app** to \`/Applications\`
3. Open it — if macOS blocks it, go to **System Settings → Privacy & Security** and click **Open Anyway**
4. Click the terminal icon in your menu bar

### Requirements
- macOS 14 Sonoma or later
- Apple Silicon or Intel

---

Built with ♥ by [Pritam](https://developerpritam.in) · [Website](https://portbar.developerpritam.in)"

    GH_FLAGS=(release create "$TAG" "$ZIP_PATH" "$GENERIC_ZIP_PATH" --title "${APP_NAME} ${VERSION}" --notes "$RELEASE_NOTES")
    [[ "$DRAFT" == true ]] && GH_FLAGS+=(--draft) && warn "Publishing as DRAFT"

    gh "${GH_FLAGS[@]}"

    echo ""
    if [[ "$DRAFT" == true ]]; then
        echo -e "${YELLOW}${BOLD}📋 Draft release created${RESET} — open GitHub Releases to publish"
    else
        echo -e "${GREEN}${BOLD}🚀 Published!${RESET}"
        REPO_URL=$(gh repo view --json url -q .url 2>/dev/null || echo "your GitHub repo")
        echo -e "   Release: ${REPO_URL}/releases/tag/${TAG}"
    fi
    echo ""
fi
