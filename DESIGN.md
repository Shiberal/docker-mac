# Design — NativeStack GUI (OrbStack register)

Visual system for the React Native macOS GUI. Reference: **OrbStack** native SwiftUI app — light macOS chrome, sidebar navigation, three-column shell.

## Scene

Developer at a desk on macOS, ambient office light, glancing between IDE and container manager. UI should read like a first-party Mac utility, not a cross-platform web panel.

## Color strategy

**Restrained** — tinted neutrals + system blue accent ≤10% of surface. Green for running state only.

| Token | Value | Use |
|-------|-------|-----|
| `window` | `#ffffff` | Main content background |
| `sidebar` | `#ececec` | Left navigation |
| `inspector` | `#f5f5f7` | Right detail panel |
| `toolbar` | `#f6f6f6` | Top bar |
| `elevated` | `#ffffff` | Inputs on gray fields |
| `field` | `#e8e8ed` | Search / text field fill |
| `border` | `#d1d1d6` | Dividers |
| `borderSubtle` | `rgba(0,0,0,0.06)` | Row separators |
| `ink` | `#1d1d1f` | Primary text |
| `inkSecondary` | `#6e6e73` | Labels, metadata |
| `inkTertiary` | `#aeaeb2` | Placeholders |
| `accent` | `#007aff` | Primary actions, active nav |
| `accentTint` | `rgba(0,122,255,0.12)` | Selected rows |
| `success` | `#34c759` | Running indicator |
| `danger` | `#ff3b30` | Destructive actions |
| `dangerTint` | `rgba(255,59,48,0.12)` | Danger button bg |
| `mono` | Menlo | IDs, logs, references |

## Typography

- **UI**: system font (SF Pro on macOS) — weights 400 / 500 / 600 / 700
- **Scale**: 11 caption, 12 label, 13 body, 15 toolbar, 18 panel title
- **Logs**: 12px Menlo, line-height 18

## Layout

- Shell: sidebar 220px | flexible list | inspector 340px
- Spacing rhythm: 4, 8, 12, 16, 20
- Radius: 6 controls, 8 inputs, 10 sidebar items

## Components

- **Sidebar item**: icon + label; active = `accentTint` bg + `accent` label
- **Segmented control**: `field` track, white active pill, 1px `border`
- **Table row**: 44px min height; selected `accentTint`; hover not available in RN — rely on selection
- **Status dot**: 8px circle, green/gray/red by state
- **Buttons**: secondary = white + border; primary = `accent`; danger = `dangerTint` + `danger` text

## Motion

150ms ease-out on press opacity only. No page-load choreography.
