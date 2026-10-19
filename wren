#!/usr/bin/env bash
set -euo pipefail

COLOR_RED=''
COLOR_GREEN=''
COLOR_WHITE=''

STYLE_DIM=''
STYLE_RESET=''

# Enable colors only when output is a terminal
if [[ -t 1 ]]; then
    COLOR_RED=$'\033[31m'
    COLOR_GREEN=$'\033[32m'
    COLOR_WHITE=$'\033[39m'

    STYLE_DIM=$'\033[2m'
    STYLE_RESET=$'\033[0m'
fi

log() {
    echo -e "${COLOR_WHITE}$*${STYLE_RESET}"
}

error() {
    echo -e "${COLOR_RED}error${STYLE_RESET}: $*" >&2
    exit 1
}

info() {
    echo -e "${STYLE_DIM}${COLOR_WHITE}$*${STYLE_RESET}"
}

success() {
    echo -e "${COLOR_GREEN}$*${STYLE_RESET}"
}

trap 'error "Interrupted"' INT TERM

if [[ -z ${HOME:-} || ! -d $HOME ]]; then
    error "HOME is not set"
fi

VERSION=0.1.0
INSTALL_URI=https://github.com/nasserkari/wren/raw/main/install
INSTALL_DIR=$HOME/.wren
CACHE_DIR=${XDG_CACHE_HOME:-$HOME/.cache}
DATA_DIR=${XDG_DATA_HOME:-$HOME/.local/share}

has() {
    command -v "$1" >/dev/null 2>&1
}

# a failing step must never stop the rest of the cleanup
run_quiet() {
    "$@" >/dev/null 2>&1 || true
}

require_sudo() {
    if [[ $EUID -eq 0 ]]; then
        return 0
    fi
    if ! has sudo; then
        error "sudo is required"
    fi
    if ! sudo -v; then
        error "sudo authentication failed"
    fi
}

# free space on / in KB, 0 if it cannot be read
free_kb() {
    local kb

    if kb=$(df -Pk / 2>/dev/null | awk 'NR == 2 {print $4}'); then
        case $kb in
        '' | *[!0-9]*) echo 0 ;;
        *) echo "$kb" ;;
        esac
    else
        echo 0
    fi
}

# empties a folder but keeps the folder itself
clean_dir() {
    local dir=$1

    # only ever touch paths inside the home folder
    case $dir in
    "$HOME"/*) ;;
    *) return 0 ;;
    esac

    # symlinks are skipped so nothing outside the folder is deleted
    if [[ -d $dir && ! -L $dir ]]; then
        run_quiet find "$dir" -mindepth 1 -delete
    fi
}

# a running browser is skipped because it is still using its cache
clean_browser() {
    local process=$1 dir
    shift

    if ! has pgrep; then
        return 0
    fi
    if pgrep -x "$process" >/dev/null 2>&1; then
        return 0
    fi

    for dir in "$@"; do
        clean_dir "$dir"
    done
}

clean() {
    local before after freed

    require_sudo
    before=$(free_kb)

    info "Cleaning cache"
    clean_dir "$CACHE_DIR/thumbnails"
    clean_browser firefox "$CACHE_DIR"/mozilla/firefox/*/cache2
    clean_browser chrome "$CACHE_DIR/google-chrome/Default/Cache"
    clean_browser chromium "$CACHE_DIR/chromium/Default/Cache"
    clean_browser brave "$CACHE_DIR/BraveSoftware/Brave-Browser/Default/Cache"
    if has npm; then
        run_quiet npm cache clean --force
    fi
    if has yarn; then
        run_quiet yarn cache clean
    fi
    if has pip3; then
        run_quiet pip3 cache purge
    elif has pip; then
        run_quiet pip cache purge
    fi

    info "Emptying trash"
    clean_dir "$DATA_DIR/Trash/files"
    clean_dir "$DATA_DIR/Trash/info"

    info "Cleaning logs"
    if has journalctl; then
        run_quiet as_root journalctl --vacuum-time=14d
    fi

    info "Cleaning packages"
    if has apt-get; then
        run_quiet as_root apt-get clean
        run_quiet as_root apt-get autoremove -y
    elif has dnf; then
        run_quiet as_root dnf clean all
        run_quiet as_root dnf autoremove -y
    elif has pacman; then
        run_quiet as_root pacman -Sc --noconfirm
    elif has zypper; then
        run_quiet as_root zypper --non-interactive clean --all
    elif has apk; then
        run_quiet as_root apk cache clean
    fi
    if has flatpak; then
        run_quiet flatpak uninstall --unused -y
    fi
    if has snap; then
        run_quiet remove_old_snaps
    fi

    info "Trimming disk"
    if has fstrim; then
        run_quiet as_root fstrim -av
    fi

    after=$(free_kb)
    freed=$(((after - before) / 1024))
    if ((freed < 0)); then
        freed=0
    fi

    success "Done! Freed $freed MB"
}

update() {
    local tmp first

    if ! has curl; then
        error "curl is required"
    fi
    if ! tmp=$(mktemp); then
        error "Update failed"
    fi

    if ! curl -fsSL --proto '=https' --tlsv1.2 "$INSTALL_URI" -o "$tmp"; then
        rm -f "$tmp"
        error "Update failed"
    fi

    # only run the download if it starts with a shebang, so an error page is never executed
    first=$(head -n 1 "$tmp")
    case $first in
    '#!'*) ;;
    *)
        rm -f "$tmp"
        error "Update failed"
        ;;
    esac

    if bash "$tmp"; then
        rm -f "$tmp"
        success "wren updated!"
    else
        rm -f "$tmp"
        error "Update failed"
    fi
}

# removes wren lines from a shell config and keeps a .wren.bak backup
remove_rc_entries() {
    local file=$1 tmp status

    if [[ ! -f $file || ! -w $file ]]; then
        return 0
    fi
    if ! grep -qF -e "# wren" -e "$INSTALL_DIR" "$file"; then
        return 0
    fi
    if ! cp -p "$file" "$file.wren.bak"; then
        return 1
    fi
    if ! tmp=$(mktemp); then
        return 1
    fi

    # grep returns 1 when no lines are left, which is fine, 2 or more is a real error
    if grep -vF -e "# wren" -e "$INSTALL_DIR" "$file" >"$tmp"; then
        status=0
    else
        status=$?
    fi

    if ((status > 1)); then
        rm -f "$tmp"
        return 1
    fi

    # cat keeps the original file permissions and symlinks intact
    if ! cat "$tmp" >"$file"; then
        rm -f "$tmp"
        return 1
    fi

    rm -f "$tmp"
}

uninstall() {
    local config

    # never remove an empty path, the root folder or the home folder
    case $INSTALL_DIR in
    '' | / | "$HOME") error "Unsafe install path" ;;
    esac

    for config in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish"; do
        if ! remove_rc_entries "$config"; then
            error "Failed to update $config"
        fi
    done

    if [[ -d $INSTALL_DIR ]]; then
        if ! rm -rf -- "$INSTALL_DIR"; then
            error "Failed to remove $INSTALL_DIR"
        fi
    fi

    success "Uninstalled"
}

version() {
    log "wren version $VERSION"
}

usage() {
    cat <<EOF
Usage: wren [options]

Options:
  -c, --clean      Clean
  -u, --update     Update wren
  -h, --help       Show this help message  
  -v, --version    Show version information
  -r, --uninstall  Clean temporary files

Note: This script is intended for use on Linux systems

Report bugs to https://github.com/nasserkari/wren/issues
EOF
}

main() {
    # Check if no arguments are provided
    if [ "$#" -eq 0 ]; then
        usage
        return 0
    fi

    # Check if more than one argument is provided
    if [ "$#" -gt 1 ]; then
        error "Too many arguments, try 'wren --help'"
    fi

    # Parse command-line arguments
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -u | --update)
            update
            ;;

        -c | --clean)
            clean
            ;;

        -r | --uninstall)
            uninstall
            ;;

        -h | --help)
            usage
            return 0
            ;;

        -v | --version)
            version
            return 0
            ;;

        *)
            error "Unknown option '$1', try 'wren --help'"
            ;;
        esac

        shift
    done
}

main "$@"
exit
