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
# Scalable fallback — left as the native-aspect logomark SVG. Real apps
# use the rasterized PNGs above; the scalable dir is a fallback for unusual
# sizes and is rarely queried.
mkdir -p "$icon_dst/scalable/apps"
cp "$src/logos/posthog-logomark.svg" "$icon_dst/scalable/apps/posthogos.svg"

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
# Logo top-left of installer header
"$MAGICK" "$src/logos/posthog-logomark.svg" -background none -resize 200x \
    "$cal_dst/logo.png"
# Welcome screen banner image — use Vibecoding (hedgehog in a tractor),
# friendly first-screen vibe.
"$MAGICK" "$src/hoglife/Vibecoding.png" -resize 1280x \
    "$cal_dst/welcome.png"

log "Done. overlay-generated/ ready."
du -sh "$out" 2>/dev/null || true
