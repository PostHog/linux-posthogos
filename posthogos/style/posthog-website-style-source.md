# PostHog website style source for PostHogOS

Status: v0.1, awaiting Will review.

This document translates the local `posthog.com` source into a native Linux desktop style target. It is intentionally source-backed: every major rule below maps to concrete website code, so the OS theme work does not drift back into screenshot guessing.

## Goal

PostHogOS should use PostHog website theming as a native OS skin: KDE panels, app launcher, windows, titlebars, menus, buttons, dialogs, desktop icons, wallpaper, and login or installer-adjacent screens.

The desktop should not recreate the website homepage chrome. Native OS controls should stay native in structure, with PostHog colours, typography, spacing, borders, textures, icon treatment, and pressed-button behavior applied to them.

## Source map

| Area | Website source | What it tells us |
| --- | --- | --- |
| Theme model | `/Users/will/github/posthog.com/agents/styling.md:48` | PostHog.com has colour mode, skin, and desktop background layers. |
| Scheme tokens | `/Users/will/github/posthog.com/src/styles/global.css:133` | Primary, secondary, and tertiary light schemes define the core palette. |
| Body defaults | `/Users/will/github/posthog.com/src/styles/global.css:481` | IBM Plex Sans is the global UI font. Light mode body background is `#eeefe9`. |
| Tailwind tokens | `/Users/will/github/posthog.com/tailwind.config.js:122` | Named light scale, accent colours, button colours, radius, spacing, and font families. |
| Top taskbar | `/Users/will/github/posthog.com/src/components/TaskBarMenu/index.tsx:274` | Full-width top bar, accent background, bottom border, compact menu buttons, right-side actions. |
| Menus | `/Users/will/github/posthog.com/src/components/RadixUI/MenuBar.tsx:36` | 13px menu text, 25px rows, small radius, primary surface, subtle shadow, `data-scheme` nesting. |
| Buttons | `/Users/will/github/posthog.com/src/components/OSButton/index.tsx:86` | Small rounded buttons, 1 to 1.5px borders, primary orange dimensional button with hover/active movement. |
| Windows | `/Users/will/github/posthog.com/src/components/AppWindow/index.tsx:607` | Rounded bordered windows, focused shadow, tertiary titlebar, primary content surface. |
| Desktop wallpaper | `/Users/will/github/posthog.com/src/components/Desktop/index.tsx:527` and `/Users/will/github/posthog.com/src/hooks/useTheme.tsx:24` | Keyboard garden texture repeats at 100px over `#E1D7C2`, large garden image sits bottom/right. |
| Desktop icons | `/Users/will/github/posthog.com/src/components/Desktop/DraggableDesktopIcon.tsx:72` | Icons live in a fixed 112px lane, centered, draggable, with small hover/drag animation. |
| Brand assets | `/Users/will/github/posthog.com/static/brand/posthog-logo.svg` | Use real PostHog logo assets from the repo where available. |

## Colour system

PostHog.com uses two modes and three nested schemes. For PostHogOS, default to light mode and use the schemes as OS roles.

### Light primary scheme

Primary is the foreground/page surface scheme. Use it for main windows and content panels.

| Token | RGB | Hex | OS target |
| --- | --- | --- | --- |
| `--bg` | `253 253 248` | `#fdfdf8` | Window/content background |
| `--accent` | `229 231 224` | `#e5e7e0` | Top panel fill, hover states, light controls |
| `--border` | `191 193 183` | `#bfc1b7` | Main borders and titlebar separators |
| `--input-bg` | `238 239 233` | `#eeefe9` | Inputs and inactive wells |
| `--input-border` | `210 211 204` | `#d2d3cc` | Input and subtle divider borders |
| `--text-primary` | `77 79 70` | `#4d4f46` | Normal foreground text and icons |
| `--text-secondary` | `101 103 94` | `#65675e` | Secondary text |
| `--text-muted` | `158 160 150` | `#9ea096` | Disabled text and faint icons |

Source: `/Users/will/github/posthog.com/src/styles/global.css:133`.

### Light secondary scheme

Secondary is used for sidebars and supporting UI. Use it for launcher/sidebar surfaces and inactive panels.

| Token | RGB | Hex | OS target |
| --- | --- | --- | --- |
| `--bg` | `238 239 233` | `#eeefe9` | Launcher/sidebar base |
| `--accent` | `210 211 204` | `#d2d3cc` | Sidebar hover |
| `--border` | `182 183 175` | `#b6b7af` | Sidebar or popover border |
| `--input-bg` | `253 253 248` | `#fdfdf8` | Search fields inside launcher/sidebar |
| `--input-border` | `191 193 183` | `#bfc1b7` | Search/input border |
| `--text-primary` | `35 37 29` | `#23251d` | Strong text on secondary surfaces |
| `--text-muted` | `158 160 150` | `#9ea096` | Muted labels |

Source: `/Users/will/github/posthog.com/src/styles/global.css:208`.

### Light tertiary scheme

Tertiary is mostly chrome. Use it for window titlebars, menu/title strips, and resize affordances.

| Token | RGB | Hex | OS target |
| --- | --- | --- | --- |
| `--bg` | `229 231 224` | `#e5e7e0` | Window titlebar base |
| `--accent` | `200 202 193` | `#c8cac1` | Titlebar hover/pressed state |
| `--border` | `158 160 150` | `#9ea096` | Stronger chrome border |
| `--input-bg` | `238 239 233` | `#eeefe9` | Compact titlebar controls |
| `--input-border` | `191 193 183` | `#bfc1b7` | Titlebar control border |
| `--text-primary` | `35 37 29` | `#23251d` | Title text |
| `--text-secondary` | `77 79 70` | `#4d4f46` | Secondary chrome icons |
| `--text-muted` | `115 117 107` | `#73756b` | Muted chrome icons |

Source: `/Users/will/github/posthog.com/src/styles/global.css:247`.

### Dark schemes

The demo ISO should default to light mode unless Will says otherwise. If dark mode ships, mirror the same three-role structure instead of falling back to CachyOS/KDE dark defaults.

| Scheme | `--bg` | `--accent` | `--border` | `--input-bg` | `--input-border` | Primary text | Secondary text | Muted text |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Primary | `#1e1f23` | `#2d2e37` | `#3e424f` | `#25262b` | `#32343f` | `#eaecf6` | `#aeb3c2` | `#626674` |
| Secondary | `#25262b` | `#32343f` | `#4a4e5c` | `#1e1f24` | `#3e424f` | `#edeef4` | `#b0b4c4` | `#6e7281` |
| Tertiary | `#2d2e37` | `#383a47` | `#626674` | `#1e1f23` | `#4b4e58` | `#edeef4` | `#b0b4c4` | `#6e7281` |

Source:

- `/Users/will/github/posthog.com/src/styles/global.css:287`
- `/Users/will/github/posthog.com/src/styles/global.css:324`
- `/Users/will/github/posthog.com/src/styles/global.css:359`

### Accent and state colours

| Token | Hex | OS target |
| --- | --- | --- |
| `orange` | `#eb9d2a` | Primary call-to-action fill, active affordance sparingly |
| `button-shadow` | `#cd8407` | Dimensional primary button lower face |
| `button-border` | `#b17816` | Primary/secondary button border |
| `blue` | `#2f80fa` | Selected/snap/focus outline when a blue state is needed |
| `red` | `#f54e00` | Error/destructive or PostHog red accent. General selection should use blue or restrained orange. |
| `green` | `#6aa84f` | Success state |
| `yellow` | `#f7a501` | Warning or highlight state |

Source: `/Users/will/github/posthog.com/tailwind.config.js:139`.

## Typography

The OS should use IBM Plex Sans as the default UI font. The website body stack starts with `IBM Plex Sans Variable`, then `IBM Plex Sans`, then system fonts. The Tailwind `sans`, `nav`, and `button` stacks repeat the IBM Plex Sans preference.

Use Source Code Pro for terminal, code labels, and monospace UI where practical. The website code stack is `Source Code Pro`, Menlo, Consolas, monaco, monospace.

Source:

- `/Users/will/github/posthog.com/src/styles/global.css:481`
- `/Users/will/github/posthog.com/tailwind.config.js:227`

OS targets:

- KDE general font: IBM Plex Sans, 10 or 11pt depending on CachyOS default density.
- KDE menu font: IBM Plex Sans, 10pt, medium-ish weight where supported.
- Terminal monospace: Source Code Pro if packaged, otherwise a good monospace fallback.
- Avoid oversized text. Website menus and chrome mostly sit around 13px.

## Desktop background

Use the keyboard garden system as the background. Avoid plain grids and rebuilt website screenshots.

Source implementation:

- Light repeated texture: `https://res.cloudinary.com/dmukukwp6/image/upload/keyboard_garden_bg_light_03a349af5c.png`
- Light garden illustration: `https://res.cloudinary.com/dmukukwp6/image/upload/keyboard_garden_light_opt_compressed_5094746caf.png`
- Light base colour: `#E1D7C2`.
- Texture repeats at `100px 100px`.
- Garden image is placed bottom/right and reaches about `700px` on desktop-sized viewports.

Source:

- `/Users/will/github/posthog.com/src/components/Desktop/index.tsx:527`
- `/Users/will/github/posthog.com/src/hooks/useTheme.tsx:24`

OS targets:

- Vendor the source-referenced Cloudinary assets into the ISO tree during build.
- Set desktop base to `#E1D7C2`, then apply the repeated texture.
- Tile the light texture at 100px.
- Place the garden illustration bottom/right with enough empty space left for windows and launchers.
- Do not draw a generic grid, do not blur it, and do not replace the garden art with a custom approximation.

## Top panel

The website taskbar maps well to a native KDE top panel, but the menu labels should remain OS labels rather than PostHog website nav items.

Source behavior:

- Full width, top aligned.
- `data-scheme="primary"`.
- Background `bg-accent/75`, meaning primary scheme accent `#e5e7e0` at 75 percent. The captured homepage top bar and hard-coded OS-style surfaces also use the nearby warmer `#e4e3d8`.
- Backdrop blur.
- Bottom border using primary border `#bfc1b7`.
- Compact horizontal menu buttons on the left.
- Utility/actions on the right.

Source: `/Users/will/github/posthog.com/src/components/TaskBarMenu/index.tsx:274`.

OS targets:

- KDE panel location: top.
- KDE panel width: full screen.
- KDE panel height: compact, but give the clock/date enough vertical padding. The current target is 44px.
- Panel colour: `#e4e3d8`, with opacity only if KDE compositing makes it crisp. Prefer solid material over washed transparency.
- Bottom border: `#bfc1b7`.
- Text/icons: `#4d4f46` default, `#23251d` for active/strong.
- Active task indicator: restrained orange or border treatment. Avoid saturated Plasma blue slabs.
- Do not include website nav labels like Product OS, Pricing, Docs, Community, Company, More.

## Menus and launcher

Website menus are compact, quiet, and rectangular with small radii.

Source behavior:

- Root menu layout: flex, 1px-ish gaps, `py-0.5`, full height.
- Menu trigger: `text-[13px]`, `rounded`, `px-1.5`, `py-0.5`, hover/open background accent.
- Menu item: 25px height, 13px text, rounded, primary background, accent hover.
- Menu popover: primary background, 180 to 220px min width, `rounded-md`, 5px padding, soft dual shadow.
- Separators: 1px `bg-border`, with 5px margin.

Source: `/Users/will/github/posthog.com/src/components/RadixUI/MenuBar.tsx:36`.

OS targets:

- Application launcher background: `#fdfdf8` or `#eeefe9` depending on nesting.
- Launcher search input: `#fdfdf8` on secondary surfaces, border `#bfc1b7`.
- Menu rows: 25 to 28px if KDE allows.
- Hover/open state: `#e5e7e0` or `#d2d3cc`.
- Separator: `#bfc1b7`, 1px.
- Popup corners: 4 to 6px radius. Avoid big pill corners.
- Popup shadow: soft and functional, without heavy blur.

## Buttons and controls

The website’s most recognizable control is the primary orange dimensional button. Use it for intentional primary actions in welcome dialogs, install/start actions, and selected toolbar actions. Do not overuse it for every active state in the OS.

Source behavior:

- Base buttons are relative, rounded, bordered, text-primary, transition-coloured.
- Parent borders are 1px to 1.5px, radii 5 or 6px.
- Primary parent: `button-shadow` background, `button` border.
- Primary child: orange fill, black text, bold, 1.5px border, slight upward translate, hover lifts 1px, active presses down.
- Secondary parent: orange frame with white child.

Source: `/Users/will/github/posthog.com/src/components/OSButton/index.tsx:86`.

OS targets:

- Default buttons: `#fdfdf8` fill, `#bfc1b7` border, `#4d4f46` text.
- Hover buttons: `#e5e7e0` fill.
- Primary buttons: fill `#eb9d2a`, border `#b17816`, lower/shadow face `#cd8407`, black text, bold.
- Radius: 5 to 6px.
- Pressed state: darker/lower effect where feasible in KDE SVG/theme files.
- Disabled state: muted text `#9ea096`, reduced contrast.

## Windows and titlebars

PostHog windows are native desktop-like windows with light surfaces, compact controls, subtle borders, and a focused shadow.

Source behavior:

- Window container uses `data-scheme="tertiary"`.
- Focused windows use `shadow-2xl border-primary`.
- Unfocused windows use `shadow-lg border-input`.
- Normal windows get `border rounded`.
- Titlebar uses tertiary scheme, `bg-primary/50`, heavy backdrop blur, `border-b border-input`.
- Titlebar grid: left menu, centered title, right window controls.
- Window content uses light background in chrome mode.

Source:

- `/Users/will/github/posthog.com/src/components/AppWindow/index.tsx:607`
- `/Users/will/github/posthog.com/src/components/AppWindow/index.tsx:726`

OS targets:

- Window body: `#fdfdf8`.
- Titlebar: `#e4e3d8` or `#fdfdf8` at partial visual weight, separated by `#bfc1b7`.
- Focused border: `#bfc1b7` or `#9ea096`, depending on contrast.
- Unfocused border: `#d2d3cc`.
- Corner radius: 4 to 6px.
- Window control buttons: compact icon buttons using the default button system. Use coloured traffic lights only if the local KDE theme makes that cheaper and still PostHog-ish.
- Shadows: keep them visible enough to separate stacked windows, but avoid the dark default Plasma look.

## Desktop icons

The website desktop icons are spaced and centered, with lightweight motion. For PostHogOS, use native launcher icons but make their treatment PostHog-flavoured.

Source behavior:

- Each icon occupies a `w-28` lane, about 112px.
- Icons are centered.
- Drag state scales to 1.1 and rotates 2 degrees.
- Desktop apps are arranged in left and right columns in the website desktop.

Source:

- `/Users/will/github/posthog.com/src/components/Desktop/DraggableDesktopIcon.tsx:72`
- `/Users/will/github/posthog.com/src/components/Desktop/index.tsx:641`

OS targets:

- Desktop icon labels should use IBM Plex Sans.
- Icon label text should be dark `#4d4f46`, with subtle text shadow only if readability needs it.
- Icon grid spacing should feel loose enough for the wallpaper, but not like the literal website layout.
- Prefer real app icons where they exist, PostHog brand assets for PostHog-specific launchers, and simple file/app metaphors for OS-specific launchers.

## Logo and brand assets

Use source assets from the local PostHog website repo when available.

Known local assets:

- `/Users/will/github/posthog.com/static/brand/posthog-logo.svg`
- `/Users/will/github/posthog.com/static/brand/posthog-logomark.svg`
- `/Users/will/github/posthog.com/static/brand/posthog-logo-black.svg`
- `/Users/will/github/posthog.com/static/brand/posthog-logo-white.svg`
- `/Users/will/github/posthog.com/src/images/posthog-logo-150x29.svg`
- `/Users/will/github/posthog.com/src/images/posthog-hog-transparent.svg`

OS targets:

- Top panel logo: use the logomark or compact logo, sized to fit the panel height. The previous failure mode was a cropped logo.
- Welcome screen: full logo is fine.
- App launchers: use logomark for PostHog-specific apps.
- Avoid recreating the logo with custom SVG unless the source file cannot be used directly.

## Motion

The website uses small UI motions: button lift/press, window open/close scale, hover highlights, and draggable icon motion. Do not make the OS feel animated for animation’s sake.

Source examples:

- OS buttons translate by 1 to 4px on hover/active: `/Users/will/github/posthog.com/src/components/OSButton/index.tsx:97`.
- Windows open with scale and 0.2s transition: `/Users/will/github/posthog.com/src/components/AppWindow/index.tsx:632`.
- Desktop icons scale and rotate slightly while dragging: `/Users/will/github/posthog.com/src/components/Desktop/DraggableDesktopIcon.tsx:89`.
- Tailwind defines small `wiggle`, `grow`, `grow-sm`, and `flash` keyframes: `/Users/will/github/posthog.com/tailwind.config.js:300`.

OS targets:

- Keep native KDE animations short and subtle.
- Use button press states where the theme format allows it.
- Avoid bouncy panel/menu animations.

## Implementation boundaries

- Keep native OS structure. Style KDE, SDDM, installer-adjacent screens, panel, launcher, window decorations, wallpaper, icons, and welcome flow.
- Do not paste the website navbar into the OS panel.
- Do not create a wallpaper screenshot of the website.
- Do not use hand-drawn approximations for assets when the local `posthog.com` source has either a local asset or a source-referenced asset URL.
- Do not continue making visual changes from vibes. Changes should map back to this doc or the distro GUI context doc.

## Open review questions

1. Is the palette mapping detailed enough for the next implementation pass?
2. Should PostHogOS ship light mode only for the demo ISO, or should the dark scheme be mapped too?
3. For desktop icons, should we stay closer to the website document/app icon language, or keep app-native icons with only PostHog spacing/labels?
4. Should the top panel include a small PostHogOS wordmark, or just the logomark plus normal OS menu/task widgets?
