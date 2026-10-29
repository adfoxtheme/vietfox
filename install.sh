#!/usr/bin/env bash
# When downloaded with `curl .../install.sh | bash`, fetch the complete source
# bundle and continue from a real directory so relative assets are available.
INPUT_SCRIPT="${BASH_SOURCE[0]:-/dev/stdin}"
INPUT_DIR="$(cd "$(dirname "$INPUT_SCRIPT")" 2>/dev/null && pwd || true)"
if [[ ! -f "$INPUT_DIR/vietfox/__init__.py" ]]; then
    for tool in curl tar; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "Thiếu lệnh $tool. Hãy cài $tool rồi chạy lại." >&2
            exit 1
        fi
    done
    TEMP_SOURCE="$(mktemp -d)"
    ARCHIVE="$TEMP_SOURCE/vietfox-source.tar.gz"
    echo "Đang tải mã nguồn Vietfox từ GitHub…"
    if ! curl -fL --retry 3 \
        "https://github.com/adfoxtheme/vietfox/archive/refs/heads/main.tar.gz" \
        -o "$ARCHIVE"; then
        rm -rf "$TEMP_SOURCE"
        exit 1
    fi
    if ! tar -xzf "$ARCHIVE" --strip-components=1 -C "$TEMP_SOURCE"; then
        rm -rf "$TEMP_SOURCE"
        exit 1
    fi
    rm -f "$ARCHIVE"
    bash "$TEMP_SOURCE/install.sh" --with-engine "$@"
    STATUS=$?
    rm -rf "$TEMP_SOURCE"
    exit "$STATUS"
fi

# Cài Vietfox (ứng dụng Vietfox + engine Vietfox dựa trên lõi Ngó Sen).
#
#   ./install.sh                     chỉ cài giao diện vào ~/.local
#   ./install.sh --with-engine       cài thêm engine Vietfox vào /usr (cần sudo)
#   ./install.sh --with-engine --force-engine
#                                    bí danh tương thích cũ của --with-engine
#   sudo ./install.sh --system       cài giao diện vào /usr/local
#   ./install.sh --uninstall         gỡ giao diện (thêm --with-engine để gỡ engine)
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
WITH_ENGINE=0
UNINSTALL=0

usage() {
    cat <<'EOF'
Cài Vietfox (ứng dụng Vietfox + engine Vietfox dựa trên lõi Ngó Sen).

  ./install.sh                     chỉ cài giao diện vào ~/.local
  ./install.sh --with-engine       cài giao diện và engine vào máy (cần sudo)
  ./install.sh --system            cài giao diện vào /usr/local
  ./install.sh --uninstall         gỡ giao diện (thêm --with-engine để gỡ engine)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --system)
            PREFIX="/usr/local"
            ;;
        --with-engine)
            WITH_ENGINE=1
            ;;
        --force-engine)
            WITH_ENGINE=1
            ;;
        --uninstall)
            UNINSTALL=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Tham số không hợp lệ: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

DATA_DIR="$PREFIX/share/vietfox"
BIN_DIR="$PREFIX/bin"
APPS_DIR="$PREFIX/share/applications"
ICON_DIR="$PREFIX/share/icons/hicolor/scalable/apps"
DESKTOP="$APPS_DIR/io.github.vietfox.Vietfox.desktop"
ICON="$ICON_DIR/io.github.vietfox.Vietfox.svg"
SETTINGS_ICON="$ICON_DIR/io.github.vietfox.Settings.svg"
LAUNCHER="$BIN_DIR/vietfox"
DOC_DIR="$PREFIX/share/doc/vietfox"

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
    SUDO="sudo"
fi

USER_HOME="$HOME"
if [[ -n "${SUDO_USER:-}" ]]; then
    USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
fi

# The one-command Ubuntu installer fills in the app and engine runtime packages.
if [[ -r /etc/os-release ]]; then
    . /etc/os-release
fi
if [[ $WITH_ENGINE -eq 1 && $UNINSTALL -eq 0 ]]; then
    if [[ "${ID:-}" != "ubuntu" || "${VERSION_CODENAME:-}" != "resolute" ]] ||
       ! command -v dpkg >/dev/null 2>&1 || [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
        echo "Engine Vietfox hiện chỉ có cho Ubuntu 26.04 amd64; chưa cài đặt gì." >&2
        exit 1
    fi
    if [[ ! -f "$SRC_DIR/engine/variants/ubuntu/resolute/amd64/libvietfox.so" ||
          ! -f "$SRC_DIR/engine/variants/ubuntu/resolute/amd64/libvietfoxmigrate.so" ]]; then
        echo "Bản tải xuống thiếu engine Vietfox hoàn chỉnh; chưa cài đặt gì." >&2
        exit 1
    fi
    for legacy_file in \
        /usr/lib/x86_64-linux-gnu/fcitx5/libngosen.so \
        /usr/lib/x86_64-linux-gnu/fcitx5/libngosenmigrate.so \
        /usr/share/fcitx5/addon/ngosen.conf \
        /usr/share/fcitx5/addon/ngosenmigrate.conf \
        /usr/share/fcitx5/inputmethod/ngosen.conf; do
        if [[ -e "$legacy_file" ]] && dpkg-query -S "$legacy_file" >/dev/null 2>&1; then
            echo "$legacy_file thuộc gói Ubuntu. Hãy gỡ gói Ngó Sen bằng apt trước khi cài Vietfox:" >&2
            echo "  sudo apt remove fcitx5-ngosen" >&2
            exit 1
        fi
    done
fi
if [[ $UNINSTALL -eq 0 && "${ID:-}" == "ubuntu" ]] && command -v apt-get >/dev/null 2>&1; then
    APT_PACKAGES=(python3-gi gir1.2-gtk-4.0 gir1.2-adw-1)
    if [[ $WITH_ENGINE -eq 1 ]]; then
        # fcitx5 only recommends its app frontends on some Ubuntu setups. Name
        # them explicitly so reinstallations and systems with recommends off
        # still get GTK and Qt input-method support (including Chrome/Chromium).
        APT_PACKAGES+=(fcitx5 im-config fcitx5-frontend-gtk3 fcitx5-frontend-gtk4
            fcitx5-frontend-qt5 fcitx5-frontend-qt6)
    fi
    MISSING_PACKAGES=()
    for package in "${APT_PACKAGES[@]}"; do
        if ! dpkg-query -W -f='${db:Status-Status}' "$package" 2>/dev/null | grep -qx installed; then
            MISSING_PACKAGES+=("$package")
        fi
    done
    if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
        echo "Đang cài các gói Ubuntu cần thiết: ${MISSING_PACKAGES[*]}"
        $SUDO apt-get update
        $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "${MISSING_PACKAGES[@]}"
    fi
fi
FORWARD_KEYS_UUID="forward-keys@adfoxtheme.github.io"
FORWARD_KEYS_DIR="$USER_HOME/.local/share/gnome-shell/extensions/$FORWARD_KEYS_UUID"
LEGACY_FORWARD_KEYS_UUID="forward-keys@ngosen.github.io"
LEGACY_FORWARD_KEYS_DIR="$USER_HOME/.local/share/gnome-shell/extensions/$LEGACY_FORWARD_KEYS_UUID"

set_shell_extension_enabled() {
    local uuid="$1" action="$2" current updated
    command -v gsettings >/dev/null 2>&1 || return 2
    current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)" || return 2
    updated="$(python3 - "$current" "$uuid" "$action" <<'PY'
import ast
import sys

raw, uuid, action = sys.argv[1:]
if raw.startswith("@as "):
    raw = raw[4:]
try:
    extensions = ast.literal_eval(raw)
except (SyntaxError, ValueError):
    raise SystemExit(2)
if not isinstance(extensions, list) or not all(isinstance(item, str) for item in extensions):
    raise SystemExit(2)
if action == "enable" and uuid not in extensions:
    extensions.append(uuid)
elif action == "disable":
    extensions = [item for item in extensions if item != uuid]
print("[" + ", ".join(repr(item) for item in extensions) + "]")
PY
    )" || return 2
    [[ "$updated" != "$current" ]] || return 0
    gsettings set org.gnome.shell enabled-extensions "$updated" >/dev/null 2>&1 || return 2
    current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)" || return 2
    if [[ "$action" == enable ]] && grep -Fq "'$uuid'" <<< "$current"; then
        return 0
    elif [[ "$action" == disable ]] && ! grep -Fq "'$uuid'" <<< "$current"; then
        return 0
    fi
    return 2
}

configure_gnome_input_support() {
    [[ "${XDG_CURRENT_DESKTOP:-}" == *GNOME* ]] || return 0

    local config_dir="$USER_HOME/.config"
    local env_dir="$config_dir/environment.d"
    local env_file="$env_dir/90-vietfox.conf"
    local autostart_dir="$config_dir/autostart"
    local autostart_file="$autostart_dir/org.fcitx.Fcitx5.desktop"

    if [[ ! -f "$env_file" ]] && ! grep -qs '^GTK_IM_MODULE=' "$env_dir"/*.conf 2>/dev/null; then
        install -d "$env_dir"
        cat > "$env_file" <<'EOF'
# Managed by Vietfox installer
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
EOF
        echo "Đã cấu hình môi trường GNOME để ứng dụng dùng Fcitx5. Đăng xuất/đăng nhập để áp dụng."
    fi

    if [[ ! -e /etc/xdg/autostart/org.fcitx.Fcitx5.desktop &&
          ! -e "$autostart_file" &&
          -f /usr/share/applications/org.fcitx.Fcitx5.desktop ]]; then
        install -d "$autostart_dir"
        cp /usr/share/applications/org.fcitx.Fcitx5.desktop "$autostart_file"
        echo "Đã thêm Fcitx5 tự khởi chạy khi đăng nhập GNOME."
    fi
}

if [[ $UNINSTALL -eq 1 ]]; then
    if [[ -f "$FORWARD_KEYS_DIR/.vietfox-managed" ]]; then
        set_shell_extension_enabled "$FORWARD_KEYS_UUID" disable ||
            gnome-extensions disable "$FORWARD_KEYS_UUID" >/dev/null 2>&1 || true
        rm -rf "$FORWARD_KEYS_DIR"
    fi
    if [[ -f "$LEGACY_FORWARD_KEYS_DIR/.vietfox-managed" ]]; then
        set_shell_extension_enabled "$LEGACY_FORWARD_KEYS_UUID" disable ||
            gnome-extensions disable "$LEGACY_FORWARD_KEYS_UUID" >/dev/null 2>&1 || true
        rm -rf "$LEGACY_FORWARD_KEYS_DIR"
    fi
    ENV_FILE="$USER_HOME/.config/environment.d/90-vietfox.conf"
    if [[ -f "$ENV_FILE" ]] && cmp -s "$ENV_FILE" <(cat <<'EOF'
# Managed by Vietfox installer
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
EOF
    ); then
        rm -f "$ENV_FILE"
    fi
    USER_AUTOSTART="$USER_HOME/.config/autostart/org.fcitx.Fcitx5.desktop"
    if [[ -f "$USER_AUTOSTART" && -f /usr/share/applications/org.fcitx.Fcitx5.desktop ]] &&
       cmp -s /usr/share/applications/org.fcitx.Fcitx5.desktop "$USER_AUTOSTART"; then
        rm -f "$USER_AUTOSTART"
    fi
    SETTINGS_LAUNCHER="/usr/bin/fcitx5-ngosen-settings"
    $SUDO rm -f /usr/share/icons/hicolor/scalable/apps/io.github.vietfox.Settings.svg
    $SUDO rm -f /usr/share/icons/hicolor/scalable/apps/io.github.vietfox.Menu.*.svg
    $SUDO rm -f /usr/share/icons/hicolor/scalable/actions/vietfox-*.svg
    $SUDO gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    if [[ -f "$SETTINGS_LAUNCHER" ]] && grep -q '^# Managed by Vietfox installer$' "$SETTINGS_LAUNCHER"; then
        $SUDO rm -f "$SETTINGS_LAUNCHER"
        echo "Đã gỡ launcher Settings của Vietfox."
    fi
    if [[ $WITH_ENGINE -eq 1 ]]; then
        if [[ -f /usr/bin/vietfox ]] && grep -q '^# Managed by Vietfox installer$' /usr/bin/vietfox; then
            $SUDO rm -f /usr/bin/vietfox
        fi
        case "$(dpkg --print-architecture 2>/dev/null || true)" in
            amd64) ENGINE_TRIPLET="x86_64-linux-gnu" ;;
            arm64) ENGINE_TRIPLET="aarch64-linux-gnu" ;;
            *) ENGINE_TRIPLET="" ;;
        esac
        if [[ -n "$ENGINE_TRIPLET" ]]; then
            $SUDO rm -f "/usr/lib/$ENGINE_TRIPLET/fcitx5/libvietfox.so" \
                "/usr/lib/$ENGINE_TRIPLET/fcitx5/libvietfoxmigrate.so" \
                /usr/share/fcitx5/addon/vietfox.conf \
                /usr/share/fcitx5/addon/vietfoxmigrate.conf \
                /usr/share/fcitx5/inputmethod/vietfox.conf \
                /usr/share/locale/vi/LC_MESSAGES/fcitx5-vietfox.mo
        fi
        $SUDO rm -f /usr/share/icons/hicolor/scalable/apps/fcitx-vietfox*.svg \
            /usr/share/icons/hicolor/scalable/status/fcitx-vietfox*.svg
        $SUDO gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    fi
    rm -rf "$DATA_DIR"
    rm -f "$LAUNCHER" "$DESKTOP" "$ICON" "$SETTINGS_ICON"
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" || true
    if [[ $WITH_ENGINE -eq 1 ]]; then
        echo "Đã gỡ engine Vietfox. Cấu hình Fcitx5 và dữ liệu người dùng vẫn được giữ nguyên."
    fi
    echo "Đã gỡ Vietfox khỏi $PREFIX."
    echo "Cấu hình người dùng vẫn còn trong ~/.config/vietfox và fcitx5."
    exit 0
fi

if ! python3 - <<'PY'
import sys
try:
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Gtk, Adw
except Exception as error:
    print(f"Thiếu thư viện: {error}", file=sys.stderr)
    sys.exit(1)
PY
then
    echo "Cần PyGObject, GTK 4 và libadwaita 1."
    echo "Ubuntu/Debian: sudo apt install python3-gi gir1.2-gtk-4.0 gir1.2-adw-1"
    echo "Fedora:        sudo dnf install python3-gobject gtk4 libadwaita"
    echo "Arch:          sudo pacman -S python-gobject gtk4 libadwaita"
    exit 1
fi

# ---------------------------------------------------------------- giao diện
install -d "$DATA_DIR" "$BIN_DIR" "$APPS_DIR" "$ICON_DIR" "$DOC_DIR"
rm -rf "$DATA_DIR/vietfox" "$DATA_DIR/data"
cp -r "$SRC_DIR/vietfox" "$DATA_DIR/vietfox"
cp -r "$SRC_DIR/data" "$DATA_DIR/data"
find "$DATA_DIR" -name '__pycache__' -type d -prune -exec rm -rf {} +
cp "$SRC_DIR/data/io.github.vietfox.Vietfox.svg" "$ICON"
cp "$SRC_DIR/data/io.github.vietfox.Settings.svg" "$SETTINGS_ICON"
sed "s|^Exec=.*|Exec=$LAUNCHER|" \
    "$SRC_DIR/data/io.github.vietfox.Vietfox.desktop" > "$DESKTOP"

# Configure the GNOME session like the upstream Fcitx5 installer does, then
# register the bundled extension in GNOME's enabled-extensions setting. This
# setting takes effect at the next GNOME login.
if [[ $WITH_ENGINE -eq 1 ]] && command -v gnome-shell >/dev/null 2>&1; then
    configure_gnome_input_support
    GNOME_SHELL_VERSION="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -n 1 || true)"
    case "$GNOME_SHELL_VERSION" in
      50.0|50.1|50.2|50.3)
    if [[ -f "$LEGACY_FORWARD_KEYS_DIR/.vietfox-managed" ]]; then
        set_shell_extension_enabled "$LEGACY_FORWARD_KEYS_UUID" disable ||
            gnome-extensions disable "$LEGACY_FORWARD_KEYS_UUID" >/dev/null 2>&1 || true
        rm -rf "$LEGACY_FORWARD_KEYS_DIR"
    fi
    install -d "$FORWARD_KEYS_DIR"
    install -m 644 "$SRC_DIR/gnome-shell/$FORWARD_KEYS_UUID/extension.js" \
        "$FORWARD_KEYS_DIR/extension.js"
    install -m 644 "$SRC_DIR/gnome-shell/$FORWARD_KEYS_UUID/metadata.json" \
        "$FORWARD_KEYS_DIR/metadata.json"
    touch "$FORWARD_KEYS_DIR/.vietfox-managed"
    if set_shell_extension_enabled "$FORWARD_KEYS_UUID" enable; then
        echo "Đã bật extension sửa lỗi gõ Chrome cho GNOME $GNOME_SHELL_VERSION. Đăng xuất/đăng nhập để GNOME nạp extension."
    else
        echo "Đã cài extension sửa lỗi gõ Chrome. Sau khi đăng nhập lại, chạy: gnome-extensions enable $FORWARD_KEYS_UUID"
    fi
        ;;
      *)
    # GNOME 51 trở lên đã sửa lỗi chuyển phím; extension của GNOME 50 làm
    # nhân đôi ký tự nên phải gỡ khỏi phiên đã cài từ bản trước.
    if [[ -f "$LEGACY_FORWARD_KEYS_DIR/.vietfox-managed" ]]; then
        set_shell_extension_enabled "$LEGACY_FORWARD_KEYS_UUID" disable ||
            gnome-extensions disable "$LEGACY_FORWARD_KEYS_UUID" >/dev/null 2>&1 || true
        rm -rf "$LEGACY_FORWARD_KEYS_DIR"
    fi
    if [[ -f "$FORWARD_KEYS_DIR/.vietfox-managed" ]]; then
        set_shell_extension_enabled "$FORWARD_KEYS_UUID" disable ||
            gnome-extensions disable "$FORWARD_KEYS_UUID" >/dev/null 2>&1 || true
        rm -rf "$FORWARD_KEYS_DIR"
        echo "Đã gỡ extension forward-keys vì GNOME $GNOME_SHELL_VERSION không cần extension này. Đăng xuất/đăng nhập để áp dụng."
    fi
        ;;
    esac
fi

cat > "$LAUNCHER" <<EOF
#!/bin/sh
export PYTHONPATH="$DATA_DIR\${PYTHONPATH:+:\$PYTHONPATH}"
exec python3 -m vietfox "\$@"
EOF
chmod +x "$LAUNCHER"
cp "$SRC_DIR/LICENSE" "$DOC_DIR/LICENSE"
[[ -f "$SRC_DIR/engine/COPYRIGHT" ]] && cp "$SRC_DIR/engine/COPYRIGHT" "$DOC_DIR/engine-COPYRIGHT"

# ------------------------------------------------------------------- engine
install_settings_launcher() {
    local settings_launcher="/usr/bin/fcitx5-ngosen-settings"
    $SUDO install -D -m 644 "$SRC_DIR/data/io.github.vietfox.Settings.svg" \
        /usr/share/icons/hicolor/scalable/apps/io.github.vietfox.Settings.svg
    # Menu action icons use the desktop's symbolic theme icons so they follow
    # its foreground color in both light and dark appearances.
    $SUDO rm -f /usr/share/icons/hicolor/scalable/apps/io.github.vietfox.Menu.*.svg
    $SUDO rm -f /usr/share/icons/hicolor/scalable/actions/vietfox-*.svg
    $SUDO gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    if [[ -e "$settings_launcher" ]] && ! grep -q '^# Managed by Vietfox installer$' "$settings_launcher"; then
        echo "Giữ nguyên $settings_launcher hiện có; không ghi đè Settings của Ngó Sen."
        return 0
    fi

    local quoted_launcher launcher_script
    printf -v quoted_launcher '%q' "$LAUNCHER"
    launcher_script=$(mktemp)
    cat > "$launcher_script" <<EOF
#!/bin/sh
# Managed by Vietfox installer
user_launcher="\${HOME}/.local/bin/vietfox"
if [ -x "\$user_launcher" ]; then
    exec "\$user_launcher" "\$@"
fi
exec $quoted_launcher "\$@"
EOF
    $SUDO install -m 755 "$launcher_script" "$settings_launcher"
    rm -f "$launcher_script"
    echo "Đã nối Settings trên top bar với Vietfox."
}

install_engine() {
    local arch_triplet libdir sharedir distro_id codename package_arch variant_dir
    . /etc/os-release
    distro_id="${ID:-}"
    codename="${VERSION_CODENAME:-}"
    if [[ "$distro_id" != "ubuntu" ]]; then
        echo "Engine đóng gói hiện chỉ hỗ trợ Ubuntu." >&2
        return 1
    fi
    if ! command -v dpkg >/dev/null; then
        echo "Không xác định được kiến trúc gói Ubuntu." >&2
        return 1
    fi
    package_arch="$(dpkg --print-architecture)"
    case "$package_arch" in
        amd64) arch_triplet="x86_64-linux-gnu" ;;
        arm64) arch_triplet="aarch64-linux-gnu" ;;
        *)
            echo "Engine Ubuntu chưa được đóng gói cho kiến trúc $package_arch." >&2
            return 1
            ;;
    esac
    variant_dir="$SRC_DIR/engine/variants/ubuntu/$codename/$package_arch"
    if [[ ! -f "$variant_dir/libvietfox.so" ]]; then
        echo "Chưa có engine Vietfox đã build cho Ubuntu $codename ($package_arch)." >&2
        return 1
    fi
    libdir="/usr/lib/$arch_triplet/fcitx5"
    sharedir="/usr/share/fcitx5"

    echo "Cài engine Vietfox cho Ubuntu $codename ($package_arch) vào $libdir…"
    $SUDO install -d "$libdir" "$sharedir/addon" "$sharedir/inputmethod" "$sharedir/ngosen"
    $SUDO install -m 644 "$variant_dir/libvietfox.so" "$libdir/"
    if [[ ! -f "$variant_dir/libvietfoxmigrate.so" ]]; then
        echo "Thiếu module di trú cấu hình Vietfox: $variant_dir/libvietfoxmigrate.so" >&2
        return 1
    fi
    $SUDO install -m 644 "$variant_dir/libvietfoxmigrate.so" "$libdir/"
    $SUDO install -m 644 "$SRC_DIR/engine/share/fcitx5/addon/vietfox.conf" "$sharedir/addon/"
    $SUDO install -m 644 "$SRC_DIR/engine/share/fcitx5/addon/vietfoxmigrate.conf" "$sharedir/addon/"
    $SUDO install -m 644 "$SRC_DIR/engine/share/fcitx5/inputmethod/vietfox.conf" "$sharedir/inputmethod/"
    # Earlier Vietfox installs left the old, auto-enabled Ngó Sen addon in /usr.
    # Fcitx loads addons independently of the selected profile input method, so
    # that stale library can still start and crash even when profile selects Vietfox.
    $SUDO rm -f "$libdir/libngosen.so" "$libdir/libngosenmigrate.so" \
        "$sharedir/addon/ngosen.conf" "$sharedir/addon/ngosenmigrate.conf" \
        "$sharedir/inputmethod/ngosen.conf"
    $SUDO cp -a "$SRC_DIR/engine/share/icons/." /usr/share/icons/
    $SUDO rm -f /usr/share/icons/hicolor/scalable/actions/vietfox-*.svg
    $SUDO gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
    $SUDO install -D -m 644 "$SRC_DIR/engine/share/locale/vi/LC_MESSAGES/fcitx5-vietfox.mo" \
        /usr/share/locale/vi/LC_MESSAGES/fcitx5-vietfox.mo
    $SUDO install -m 644 "$SRC_DIR/engine/share/fcitx5/vietfox/vietnamese.cm.dict" "$sharedir/ngosen/"

    local engine_lib="$libdir/libvietfox.so"
    if ldd "$engine_lib" 2>/dev/null | grep -q "not found"; then
        echo "Cảnh báo: engine thiếu thư viện:" >&2
        ldd "$engine_lib" | grep "not found" >&2
    fi

    # The bundled engine starts a fixed path for its top-bar Settings action.
    # Preserve any upstream launcher already installed at that path.
    local launcher_script quoted_launcher
    printf -v quoted_launcher '%q' "$LAUNCHER"
    launcher_script=$(mktemp)
    cat > "$launcher_script" <<EOF
#!/bin/sh
# Managed by Vietfox installer
user_launcher="\${HOME}/.local/bin/vietfox"
if [ -x "\$user_launcher" ]; then
    exec "\$user_launcher" "\$@"
fi
exec $quoted_launcher "\$@"
EOF
    $SUDO install -m 755 "$launcher_script" /usr/bin/vietfox
    rm -f "$launcher_script"

    # Select Fcitx5 for the next desktop login; the current session may still use IBus.
    if command -v im-config >/dev/null 2>&1; then
        if [[ -n "${SUDO_USER:-}" ]]; then
            sudo -u "$SUDO_USER" im-config -n fcitx5
        else
            im-config -n fcitx5
        fi
        echo "Đã chọn Fcitx5 làm phương thức nhập. Đăng xuất rồi đăng nhập lại để kích hoạt."
    fi
}

if [[ $WITH_ENGINE -eq 1 ]]; then
    install_engine
elif dpkg -s fcitx5-ngosen >/dev/null 2>&1 || [[ -f "/usr/lib/$(uname -m)-linux-gnu/fcitx5/libngosen.so" ]]; then
    install_settings_launcher
else
    echo
    echo "Lưu ý: chưa có engine Vietfox. Muốn cài kèm, chạy lại với --with-engine."
fi

# ------------------------------------------------- thêm vào nhóm gõ fcitx5
enable_input_method() {
    local profile="$USER_HOME/.config/fcitx5/profile"
    local input_method="${1:-ngosen}"
    if [[ ! -f "$profile" ]]; then
        mkdir -p "$(dirname "$profile")"
        cat > "$profile" <<EOF
[Groups/0]
Name="Mặc định"
Default Layout=us
DefaultIM=$input_method

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=$input_method
Layout=

[GroupOrder]
0="Mặc định"
EOF
        echo "Đã tạo cấu hình Fcitx5 mới và chọn Vietfox làm bộ gõ mặc định."
        return 0
    fi
    python3 - "$profile" "$input_method" <<'PY'
import re
import sys

path = sys.argv[1]
input_method = sys.argv[2]
text = open(path, encoding="utf-8").read()
lines = text.splitlines()
start = next((i for i, line in enumerate(lines) if line.strip() == "[Groups/0]"), None)
if start is None:
    print("Không thấy nhóm [Groups/0]; hãy thêm Vietfox bằng fcitx5-configtool.", file=sys.stderr)
    raise SystemExit(1)

in_group = False
has_method = False
has_default = False
indices = []
for index, line in enumerate(lines):
    if line.startswith("["):
        in_group = line == "[Groups/0]" or line.startswith("[Groups/0/Items/")
        match = re.fullmatch(r"\[Groups/0/Items/(\d+)\]", line)
        if match:
            indices.append(int(match.group(1)))
    if not in_group:
        continue
    if line.startswith("DefaultIM="):
        has_default = True
        if input_method == "vietfox" and line != "DefaultIM=vietfox":
            lines[index] = "DefaultIM=vietfox"
    if line == f"Name={input_method}":
        has_method = True
    elif input_method == "vietfox" and line == "Name=ngosen":
        lines[index] = "Name=vietfox"
        has_method = True

if not has_method:
    new_index = max(indices, default=-1) + 1
    insert_at = next((i for i, line in enumerate(lines) if line == "[GroupOrder]"), len(lines))
    if insert_at > 0 and lines[insert_at - 1] != "":
        lines.insert(insert_at, "")
        insert_at += 1
    lines[insert_at:insert_at] = [f"[Groups/0/Items/{new_index}]", f"Name={input_method}", "Layout="]

if not has_default:
    group_end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    lines.insert(group_end, f"DefaultIM={input_method}")

open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print(f"Đã chọn Vietfox trong nhóm gõ của fcitx5 ({input_method}).")
PY
}

PROFILE="$USER_HOME/.config/fcitx5/profile"
INPUT_METHOD_ID="ngosen"
if [[ -f "/usr/share/fcitx5/inputmethod/vietfox.conf" ]]; then
    INPUT_METHOD_ID="vietfox"
fi
if command -v fcitx5 >/dev/null && [[ -f "/usr/share/fcitx5/inputmethod/$INPUT_METHOD_ID.conf" ]]; then
    FCITX5_WAS_RUNNING=0
    if pgrep -x fcitx5 >/dev/null 2>&1; then
        FCITX5_WAS_RUNNING=1
        fcitx5-remote -e >/dev/null 2>&1 || true
        for _ in {1..10}; do
            pgrep -x fcitx5 >/dev/null 2>&1 || break
            sleep 0.5
        done
    fi
    enable_input_method "$INPUT_METHOD_ID"
    FCITX5_CONFIG="$USER_HOME/.config/fcitx5/config"
    if ! grep -qs '^\[Hotkey/TriggerKeys\]$' "$FCITX5_CONFIG"; then
        install -d "$(dirname "$FCITX5_CONFIG")"
        cat >> "$FCITX5_CONFIG" <<'EOF'

[Hotkey/TriggerKeys]
0=Control+Shift_L
1=Control+Shift_R
2=Shift+Control_L
3=Shift+Control_R
EOF
    fi
    if [[ $FCITX5_WAS_RUNNING -eq 1 ]]; then
        fcitx5 -d >/dev/null 2>&1 || true
    fi
fi

# ------------------------------------------------------------------- duong dan
if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$APPS_DIR" || true
fi
if command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache -f -t "$PREFIX/share/icons/hicolor" >/dev/null 2>&1 || true
fi

echo "Đã cài Vietfox vào $PREFIX."
echo "Chạy: $LAUNCHER"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo "Thêm $BIN_DIR vào PATH để gõ 'vietfox' từ terminal."
fi
