# Product

## Register

product

## Users

Apple Silicon Mac developers who run containers via Apple's native `container` CLI. They work in IDEs and terminals, expect macOS-native affordances, and compare NativeStack directly to OrbStack and Docker Desktop.

## Product Purpose

NativeStack is a lightweight OrbStack-style container manager: list containers and images, inspect logs, start/stop the engine, and pull images — without leaving a polished macOS GUI.

## Brand Personality

Native, fast, trustworthy. Three words: **macOS-native**, **capable**, **unobtrusive**.

## Anti-references

- Generic dark "dev tool" chrome (Electron Docker Desktop, purple-gradient SaaS dashboards)
- Emoji sidebar icons and heavy blue selection blocks
- Busy card grids and decorative motion

## Design Principles

1. **Feel at home on macOS** — sidebar, inspector, and toolbar follow system conventions OrbStack users already know.
2. **Task-first density** — tables and inspectors show what matters; chrome stays quiet.
3. **State you can scan** — running/stopped/engine status readable at a glance (dots, color, label).
4. **Consistency over novelty** — same button, tab, and row vocabulary everywhere.

## Accessibility & Inclusion

WCAG AA contrast on text and controls. Respect `prefers-reduced-motion` for any transitions. Status must not rely on color alone (label + dot).
