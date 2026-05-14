#!/usr/bin/env bash
# Generate the overlay-generated/ tree from branding/posthogos/ sources.
#
# Source of truth lives in branding/posthogos/. Everything produced here is
# derived (resampled wallpapers, fontconfig snippets, slideshow copies, etc.)
# and is .gitignore'd. Runs on the host before bin/build, OR inside the
# container at the start of in-container-build.sh.
#
# Requires ImageMagick (magick or convert).

set -euo pipefail

cd "$(dirname "$0")/.."
repo_root="$PWD"
src="$repo_root/branding/posthogos"
out="$repo_root/overlay-generated"

if ! command -v magick >/dev/null && ! command -v convert >/dev/null; then
    echo "ERROR: ImageMagick is required (install: brew install imagemagick / pacman -S imagemagick)" >&2
    exit 1
fi
MAGICK=$(command -v magick || command -v convert)

log() { printf '[build-assets] %s\n' "$*"; }

# --- Reset output tree ----------------------------------------------------
rm -rf "$out"
mkdir -p "$out"

# --- Plasma wallpaper packages -------------------------------------------
# Each themed wallpaper becomes a Plasma KPackage at
# /usr/share/wallpapers/<Name>/, with:
#   metadata.desktop  (committed to overlay/)
#   contents/images/<WIDTHxHEIGHT>.png      ← light variant, multiple sizes
#   contents/images_dark/<WIDTHxHEIGHT>.png ← dark variant, multiple sizes
build_wallpaper_pkg() {
    local theme="$1"          # human title, e.g. "Keyboard Garden"
    local pkg_name="$2"       # filesystem name, e.g. "PosthogosKeyboardGarden"
    local light_src dark_src
    light_src="$src/wallpapers/${theme} [light] [4K].png"
    dark_src="$src/wallpapers/${theme} [dark] [4K].png"

    [ -f "$light_src" ] || { echo "  missing: $light_src" >&2; return 1; }
    [ -f "$dark_src"  ] || { echo "  missing: $dark_src" >&2; return 1; }

    local pkg="$out/airootfs/usr/share/wallpapers/$pkg_name"
    mkdir -p "$pkg/contents/images" "$pkg/contents/images_dark"

    log "  $theme → $pkg_name"
    # Resample to FHD, QHD, 4K. Plasma picks the closest match per display.
    for res in 1920x1080 2560x1440 3840x2160; do
        # 4K source → smaller variants via Lanczos resample.
        # 3840x2160 is identity (cp), but going through magick is uniform.
        "$MAGICK" "$light_src" -filter Lanczos -resize "$res" \
            "$pkg/contents/images/${res}.png"
        "$MAGICK" "$dark_src" -filter Lanczos -resize "$res" \
            "$pkg/contents/images_dark/${res}.png"
    done

    # Preview thumbnail. Plasma 6's wallpaper KCM uses contents/screenshot.png
    # at ~400×250; without it every wallpaper shows a broken-image
    # placeholder in System Settings → Wallpaper. Previous .jpg form rendered
    # only on some entries (others showed blank tiles) — Plasma 6's KPackage
    # loader is .png-preferring per the KDE wallpaper-package docs. PNG also
    # gives sharper text on the brand wallpapers' typography.
    "$MAGICK" "$light_src" -filter Lanczos -resize 400x250^ \
        -gravity center -extent 400x250 \
        "$pkg/contents/screenshot.png"
}

log "Building wallpaper packages"
build_wallpaper_pkg "Keyboard Garden"  "PosthogosKeyboardGarden"
build_wallpaper_pkg "Office Party"     "PosthogosOfficeParty"
build_wallpaper_pkg "Hogzilla"         "PosthogosHogzilla"
build_wallpaper_pkg "Startup Monopoly" "PosthogosStartupMonopoly"

# --- Fonts -----------------------------------------------------------------
# Install Squeak (all weights) + Loud Noises into /usr/share/fonts/posthogos/.
# fontconfig will pick them up automatically after the chroot hook regen.
log "Copying fonts"
fonts_dst="$out/airootfs/usr/share/fonts/posthogos"
mkdir -p "$fonts_dst"
cp "$src/fonts/"*.otf "$src/fonts/"*.ttf "$fonts_dst/"

# --- Logos / system icon --------------------------------------------------
# Drop the logomark as a system icon under hicolor so /etc/os-release LOGO=posthogos
# can resolve, and apps using GIcon can pick it up.
#
# Hicolor icons must be SQUARE — file managers / launchers / docks all draw
# them at WxW. Source: posthog-logomark-square.png (pre-padded to 1:1 with
# transparent fill). Resampling down from a 1024×1024 master keeps edges
# crisp at all standard sizes.
log "Installing system logo (hicolor icon)"
icon_dst="$out/airootfs/usr/share/icons/hicolor"
square_src="$src/logos/posthog-logomark-square.png"
for size in 64 128 256 512; do
    dir="$icon_dst/${size}x${size}/apps"
    mkdir -p "$dir"
    "$MAGICK" "$square_src" -filter Lanczos -resize "${size}x${size}" \
        "$dir/posthogos.png"
done
# Welcome app icon — Professor Hog. Distinct identity from the system
# logomark so the Welcome window's title bar / taskbar entry / Kickoff
# favorite stands out. Padded to square (-extent) since the source image
# isn't perfectly 1:1 and hicolor expects square apps icons.
log "Installing welcome app icon (professor hog)"
hog_src="$src/hedgehogs/professor_hog.png"
if [ -f "$hog_src" ]; then
    for size in 64 128 256 512; do
        dir="$icon_dst/${size}x${size}/apps"
        mkdir -p "$dir"
        "$MAGICK" "$hog_src" -filter Lanczos \
            -resize "${size}x${size}" \
            -background none -gravity center -extent "${size}x${size}" \
            "$dir/posthogos-welcome.png"
    done
fi

# Scalable fallback — left as the native-aspect logomark SVG. Real apps
# use the rasterized PNGs above; the scalable dir is a fallback for unusual
# sizes and is rarely queried.
mkdir -p "$icon_dst/scalable/apps"
cp "$src/logos/posthog-logomark.svg" "$icon_dst/scalable/apps/posthogos.svg"

# --- PosthogOS icon theme -------------------------------------------------
# Derivative theme that overrides specific freedesktop icons with PostHog's
# product illustrations (the chunky pixel-art set from posthog.com — calculator,
# folder, doc, trash, etc.). Anything not overridden falls through Papirus-Light
# (declared via Inherits=) so Plasma stays visually coherent across the long
# tail of icons we don't have art for.
#
# Source variant is picked via POSTHOGOS_ICON_VARIANT (default: modern, the
# Mac OS 9 chiseled look that matches posthog.com's "Product OS" desktop).
# Override with POSTHOGOS_ICON_VARIANT=classic for the flatter style.
icon_variant="${POSTHOGOS_ICON_VARIANT:-modern}"
icon_src="$src/icons/$icon_variant"
[ -d "$icon_src" ] || { echo "ERROR: icon variant '$icon_variant' not found at $icon_src" >&2; exit 1; }

log "Building PosthogOS icon theme (variant: $icon_variant)"
icon_theme="$out/airootfs/usr/share/icons/PosthogOS"
icon_sizes=(32 48 64 128 256)
icon_contexts=(apps places mimetypes actions categories devices status)

# index.theme: declare the theme + inheritance + every <size>/<context> dir
# we ship. Plasma reads this to know which dirs to scan and what size to
# treat each as. Inherits chain falls through to Papirus-Light first, then
# hicolor as a final safety net.
mkdir -p "$icon_theme"
{
    printf '[Icon Theme]\n'
    printf 'Name=PosthogOS\n'
    printf 'Comment=PostHog product icons (%s variant), inheriting from Papirus-Light\n' "$icon_variant"
    printf 'Inherits=Papirus-Light,hicolor\n'
    printf 'Example=folder\n'
    printf 'DisplayDepth=32\n'
    printf 'Directories='
    first=1
    for size in "${icon_sizes[@]}"; do
        for ctx in "${icon_contexts[@]}"; do
            [ $first -eq 1 ] && first=0 || printf ','
            printf '%dx%d/%s' "$size" "$size" "$ctx"
        done
    done
    printf '\n'
    for size in "${icon_sizes[@]}"; do
        for ctx in "${icon_contexts[@]}"; do
            case "$ctx" in
                apps)       ctx_cap=Applications ;;
                places)     ctx_cap=Places ;;
                mimetypes)  ctx_cap=MimeTypes ;;
                actions)    ctx_cap=Actions ;;
                categories) ctx_cap=Categories ;;
                devices)    ctx_cap=Devices ;;
                status)     ctx_cap=Status ;;
            esac
            printf '\n[%dx%d/%s]\nSize=%d\nContext=%s\nType=Threshold\nThreshold=4\n' \
                "$size" "$size" "$ctx" "$size" "$ctx_cap"
        done
    done
} > "$icon_theme/index.theme"

# Mapping: source-name → freedesktop icon name(s) per context. Each row
# whitelisted by name maps one PostHog icon to one OR MORE target names
# (comma-separated) under a specific freedesktop context. This is the
# "translation layer" between PostHog's product taxonomy and XDG names.
#
# After this, ALL source icons also get copied to apps/<source-name>.png
# unconditionally — so .desktop files can reference them directly via their
# PostHog name (e.g. Icon=hedgehog-mode) regardless of mapping.
icon_install() {
    # $1=src-png $2=context-dir-name $3=target-basename
    local src_png="$1" ctx="$2" target="$3"
    for size in "${icon_sizes[@]}"; do
        local dir="$icon_theme/${size}x${size}/$ctx"
        mkdir -p "$dir"
        "$MAGICK" "$src_png" -filter Lanczos -resize "${size}x${size}" \
            -background none -gravity center -extent "${size}x${size}" \
            "$dir/$target.png"
    done
}

# context  source-name      target-names (comma-separated)
icon_map=$(cat <<'MAP'
places     folder           folder,inode-directory,folder-orange,folder-yellow,folder-red,folder-green,folder-blue,folder-teal,folder-violet,folder-magenta,user-home
places     trash            user-trash,user-trash-full
mimetypes  doc              text-x-generic,text-x-plain,application-x-generic,text-x-readme
mimetypes  page             text-html,text-x-markdown
mimetypes  pdf              application-pdf
mimetypes  pdf-locked       application-pgp-encrypted
mimetypes  video            video-x-generic
mimetypes  spreadsheet      x-office-spreadsheet,application-vnd.oasis.opendocument.spreadsheet
mimetypes  presentation     x-office-presentation
mimetypes  report           x-office-document
mimetypes  sql              application-sql,application-x-sqlite3
apps       notebook         accessories-text-editor,org.kde.kate,org.kde.kwrite
apps       contact          contact-new,x-office-address-book,org.kde.kaddressbook
apps       envelope         mail-message-new,internet-mail,org.kde.kmail2,thunderbird
apps       forums           internet-chat,network-chat
apps       games            applications-games
apps       handbook         accessories-dictionary,help-browser
apps       compass          applications-internet,internet-web-browser
apps       map              applications-geography
apps       bookmark         user-bookmarks,bookmark-new
apps       canvas           applications-graphics
apps       hogpaint         gimp,org.kde.krita
apps       photobooth       camera,camera-photo,org.kde.kamoso
apps       typewriter       org.kde.kate
apps       post-it          org.kde.knotes
apps       switch           system-shutdown,system-log-out
MAP
)

while IFS= read -r row; do
    [ -z "$row" ] && continue
    # shellcheck disable=SC2086
    set -- $row
    ctx="$1"; src_name="$2"; targets="$3"
    # Try chosen variant first; fall back to the other so we don't lose
    # coverage on icons that only ship in one style (e.g. `presentation`
    # and `hogpaint` are modern-only upstream).
    src_png="$icon_src/$src_name.png"
    if [ ! -f "$src_png" ]; then
        alt_variant=$([ "$icon_variant" = "classic" ] && echo modern || echo classic)
        src_png="$src/icons/$alt_variant/$src_name.png"
    fi
    if [ ! -f "$src_png" ]; then
        echo "  warning: no source for $src_name (tried both variants)" >&2
        continue
    fi
    IFS=',' read -ra target_list <<<"$targets"
    for target in "${target_list[@]}"; do
        icon_install "$src_png" "$ctx" "$target"
    done
done <<<"$icon_map"

# Pass 2: ship every source PNG as apps/<source-name>.png so .desktop files
# can reference them directly (Icon=hedgehog-mode, Icon=posthog, etc.) — useful
# for branded desktop shortcuts down the line. Skip names already produced by
# the mapping pass to avoid pointless re-encodes.
for src_png in "$icon_src"/*.png; do
    name=$(basename "$src_png" .png)
    for size in "${icon_sizes[@]}"; do
        dir="$icon_theme/${size}x${size}/apps"
        out_png="$dir/$name.png"
        if [ ! -f "$out_png" ]; then
            mkdir -p "$dir"
            "$MAGICK" "$src_png" -filter Lanczos -resize "${size}x${size}" \
                -background none -gravity center -extent "${size}x${size}" \
                "$out_png"
        fi
    done
done

log "  $(find "$icon_theme" -name '*.png' | wc -l | tr -d ' ') icons in $(find "$icon_theme" -mindepth 1 -type d | wc -l | tr -d ' ') dirs"

# --- Calamares slideshow images -------------------------------------------
# Hoglife illustrations, normalized to a consistent 1920×1080 16:9 canvas
# (centered, transparent background → solid brand BG fill, JPEGs and portraits
# get letterboxed cleanly).
log "Generating Calamares slideshow frames"
slideshow_dst="$out/airootfs/usr/share/calamares/branding/posthogos/slideshow"
mkdir -p "$slideshow_dst"
# Brand bg from handbook (#EEEFE9 light cream) — matches hoglife illustrations.
shopt -s nullglob
for f in "$src/hoglife/"*.png "$src/hoglife/"*.jpg "$src/hoglife/"*.jpeg; do
    base=$(basename "$f")
    # Slugify: lowercase, spaces → dashes, strip extension.
    name=$(echo "${base%.*}" | tr '[:upper:] ' '[:lower:]-')
    "$MAGICK" "$f" -resize 1920x1080 \
        -background '#EEEFE9' -gravity center -extent 1920x1080 \
        "$slideshow_dst/${name}.png"
done

# --- Boot menu splash (GRUB / syslinux) -----------------------------------
# 640x480 8-bit indexed PNG. Crop Hogzilla to 4:3 and downscale.
# Drop into grub/ and syslinux/ — rsync of overlay-generated/ onto archiso/
# overwrites upstream's splash.png at both paths.
log "Generating boot menu splash"
mkdir -p "$out/grub" "$out/syslinux"
"$MAGICK" "$src/wallpapers/Hogzilla [dark] [4K].png" \
    -gravity center -crop 4:3 +repage \
    -resize 640x480 \
    -colors 256 -depth 8 \
    PNG8:"$out/grub/splash.png"
cp "$out/grub/splash.png" "$out/syslinux/splash.png"

# Pre-rendered 1024×1024 logomark for surfaces that need a square logo
# (hicolor done above; SDDM + Plymouth below).
square_logo="$src/logos/posthog-logomark-square.png"

# --- SDDM theme assets ----------------------------------------------------
# Blurred 1920×1080 wallpaper as background, PostHog full lockup (white) as
# the in-card logo. Background is heavily blurred so the centered login
# card stays the focus.
#
# Source wallpaper picks via SDDM_BG env var (basename, no extension):
#   SDDM_BG="Hogzilla [dark] [4K]"             bin/build
#   SDDM_BG="Office Party [light] [4K]"        bin/build
# Default: "Keyboard Garden [dark] [4K]"
sddm_bg_name="${SDDM_BG:-Keyboard Garden [dark] [4K]}"
sddm_bg_src="$src/wallpapers/${sddm_bg_name}.png"
[ -f "$sddm_bg_src" ] || sddm_bg_src="$src/wallpapers/Keyboard Garden [dark] [4K].png"
log "Generating SDDM theme assets (background: $(basename "$sddm_bg_src"))"
sddm_dst="$out/airootfs/usr/share/sddm/themes/posthogos"
mkdir -p "$sddm_dst"
# blur 0=none, 18=heavy. Override with SDDM_BG_BLUR=N.
"$MAGICK" "$sddm_bg_src" \
    -resize 1920x1080 -blur "0x${SDDM_BG_BLUR:-18}" \
    "$sddm_dst/background.png"
# Square logo from the pre-padded 1024×1024 master, downscaled cleanly
# via Lanczos to 240px — matches Main.qml's Layout.preferredHeight: 72
# (Plasma renders at the available width then scales; square source keeps
# the in-card logo visually balanced).
"$MAGICK" "$square_logo" -filter Lanczos -resize 240x240 \
    "$sddm_dst/logo.png"

# --- Plymouth theme assets -----------------------------------------------
# Centered logomark @ 256×256, plus a small 16×16 dot for the loading
# indicator (white, low opacity by default, the script animates it).
log "Generating Plymouth theme assets"
ply_dst="$out/airootfs/usr/share/plymouth/themes/posthogos"
mkdir -p "$ply_dst"
# Square logo for Plymouth so the centering math in posthogos.script
# produces a visually balanced splash (logo.GetWidth() == logo.GetHeight()).
"$MAGICK" "$square_logo" -filter Lanczos -resize 256x256 \
    "$ply_dst/logo.png"
"$MAGICK" -size 16x16 xc:none \
    -fill '#EEEFE9' -draw 'circle 8,8 8,2' \
    "$ply_dst/dot.png"

# --- Calamares brand images ----------------------------------------------
log "Installing Calamares brand images"
cal_dst="$out/airootfs/usr/share/calamares/branding/posthogos"
mkdir -p "$cal_dst"
# Header/sidebar logo: SQUARE. calamares-sidebar.qml renders it at 30x30
# in the bottom step bar. Was previously native-aspect 200x — squashed
# horribly when Calamares fell back to the default vertical sidebar, and
# would also look off in the new qml,bottom layout. 96x96 = 30×3 for
# clean HiDPI scaling. Source is the pre-padded square logomark master.
"$MAGICK" "$square_logo" -filter Lanczos -resize 96x96 \
    "$cal_dst/logo.png"
# Window/title bar icon: must be square (WMs draw it as a square tile).
# 256×256 from the square master.
"$MAGICK" "$square_logo" -filter Lanczos -resize 256x256 \
    "$cal_dst/logo-icon.png"
# Welcome screen banner image — use Posthog 3000 for extra fun.
"$MAGICK" "$src/hoglife/Posthog 3000.png" \
    "$cal_dst/welcome.png"

# --- PostHog Code AppImage (optional) -------------------------------------
# Bundled when bin/build stages it via POSTHOG_CODE_APPIMAGE env var into
# .appimages/posthog-code.AppImage. Silent skip if absent so CI / fresh
# clones still build cleanly without the dev binary.
#
# Layout:
#   /opt/posthog-code/posthog-code.AppImage   the AppImage itself, +x
#   /usr/share/applications/posthog-code.desktop   launcher
#   /usr/share/icons/hicolor/<size>/apps/posthog-code.png   icon
#
# Runtime deps: AppImages need libfuse2 to self-mount. We add `fuse2` to
# the package list in scripts/pre-build.sh whenever this section bundles.
appimage_src="$repo_root/.appimages/posthog-code.AppImage"
if [ -f "$appimage_src" ]; then
    appimage_size=$(du -h "$appimage_src" | cut -f1)
    log "Bundling PostHog Code AppImage ($appimage_size)"
    appimage_dst="$out/airootfs/opt/posthog-code"
    mkdir -p "$appimage_dst" "$out/airootfs/usr/share/applications"
    cp "$appimage_src" "$appimage_dst/posthog-code.AppImage"
    chmod 755 "$appimage_dst/posthog-code.AppImage"

    # Desktop launcher. --no-sandbox because Electron's chromium sandbox
    # frequently fails in unusual contexts (live ISO, freshly-installed
    # systems without user namespaces fully wired), and PostHog Code is
    # Electron-based. %F lets file managers pass paths to "Open with".
    cat > "$out/airootfs/usr/share/applications/posthog-code.desktop" <<'DESKTOP_EOF'
[Desktop Entry]
Type=Application
Name=PostHog Code
GenericName=Code Editor
Comment=PostHog's AI-native code editor (dev build)
Exec=/opt/posthog-code/posthog-code.AppImage --no-sandbox %F
Icon=posthog-code
Terminal=false
Categories=Development;TextEditor;IDE;
MimeType=text/plain;inode/directory;application/x-yaml;application/json;text/x-python;text/x-c;text/x-c++;text/x-shellscript;
Keywords=editor;ide;posthog;code;
StartupWMClass=PostHog Code
DESKTOP_EOF

    # Icon: reuse the PostHog brand mark from branding/posthogos/icons/.
    # Prefer modern (matches POSTHOGOS_ICON_VARIANT default) but fall back
    # if classic was selected.
    code_icon_src="$src/icons/${POSTHOGOS_ICON_VARIANT:-modern}/posthog.png"
    [ -f "$code_icon_src" ] || code_icon_src="$src/icons/modern/posthog.png"
    [ -f "$code_icon_src" ] || code_icon_src="$src/icons/classic/posthog.png"
    if [ -f "$code_icon_src" ]; then
        for size in 64 128 256 512; do
            dir="$out/airootfs/usr/share/icons/hicolor/${size}x${size}/apps"
            mkdir -p "$dir"
            "$MAGICK" "$code_icon_src" -filter Lanczos -resize "${size}x${size}" \
                -background none -gravity center -extent "${size}x${size}" \
                "$dir/posthog-code.png"
        done
    fi
else
    log "PostHog Code AppImage absent (.appimages/posthog-code.AppImage) — skipping bundle"
fi

log "Done. overlay-generated/ ready."
du -sh "$out" 2>/dev/null || true
