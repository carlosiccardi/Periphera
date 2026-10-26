<div align="center">
  <img src="docs/app-icon-v3.png" width="88" height="88" alt="Periphera Icon" />
  <h1>Periphera</h1>
  <p><strong>Independent scroll direction for Trackpad & Mouse + External Display brightness control on macOS.</strong></p>

  <p>
    <a href="https://github.com/carlosiccardi/Periphera/releases/latest/download/Periphera.dmg">
      <img src="https://img.shields.io/badge/Download-Periphera.dmg-white?style=for-the-badge&logo=apple&logoColor=black" alt="Download DMG" />
    </a>
  </p>
</div>

---

## Preview

<div align="center">
  <table>
    <tr>
      <td align="center"><strong>Minimal View & Header Controls</strong></td>
      <td align="center"><strong>Interactive <code>(i)</code> Simulator</strong></td>
    </tr>
    <tr>
      <td valign="top"><img src="docs/preview-minimal-v5.png" width="340" alt="Periphera Minimal UI with Caffeine and Capture" /></td>
      <td valign="top"><img src="docs/preview-simulator-v5.png" width="340" alt="Periphera Interactive Simulator" /></td>
    </tr>
    <tr>
      <td align="center" colspan="2"><strong>Draggable Floating Capture Palette (<code>⌘⇧6</code> / <code>⌘⇧P</code>)</strong></td>
    </tr>
    <tr>
      <td align="center" colspan="2"><img src="docs/preview-capture-bar-v5.png" width="620" alt="Floating Capture Bar" /></td>
    </tr>
    <tr>
      <td align="center" colspan="2"><strong>CleanShot X-Style Quick Access Overlay & Drag & Drop</strong></td>
    </tr>
    <tr>
      <td align="center" colspan="2"><img src="docs/preview-quick-access-v5.png" width="280" alt="Quick Access Overlay" /></td>
    </tr>
  </table>
</div>

---

## Overview

Even in 2026, macOS still forces a single global toggle for "Natural Scrolling" across both your Trackpad and external Mouse, and offers no built-in brightness slider for third-party external monitors. **Periphera** is an ultra-lightweight, native macOS menu bar utility that solves both in one minimal popover.

## Features

- **Independent Scroll Directions**: Set **Natural** or **Standard** independently for your Trackpad and external Mouse.
- **Caffè / Anti-Sleep Mode**: Keep your Mac and display awake (`caffeinate` / `IOPMAssertion`) with customizable duration presets (Indefinite, 15m, 30m, 1h, 2h) and live menu bar indicator.
- **Draggable Floating Capture Bar (`⌘⇧6` or `⌘⇧P`)**: Clean on-screen palette with keyboard shortcuts that can be dragged anywhere.
- **Scrolling Screenshot (CleanShot X-Style)**: Live multi-band stitching engine with real-time HUD preview, sticky header rejection, and interactive pass-through scrolling.
- **Quick Access Overlay**: Floating preview panel with instant Copy, Finder reveal, and native Drag & Drop directly into Slack, Discord, Mail, Telegram, or Finder.
- **Screen Video Recording (Registrazione Schermo)**: One-click video recording with a floating timer HUD and automatic save to Desktop.
- **Instant Area & Fullscreen Screenshots**: Interactive region selection with direct copy to clipboard and Quick Access Overlay.
- **External Display Brightness Control**: Smoothly adjust the brightness of any connected external monitor (`10%` – `100%`) using hybrid hardware DDC/CI (`IOAVService`) and CoreGraphics LUT scaling.
- **Zero-Latency Native Engine**: Built on CoreGraphics (`CGEventTap`) in Swift 6; preserves native macOS trackpad inertia, rubber-banding, and swipe gestures.
- **Pure Menu Bar Agent**: Runs silently in the background (`LSUIElement`) with zero Dock clutter and optional Launch at Login.
- **Interactive Visual Simulator**: Built-in minimal `(i)` animated preview showing finger/wheel gesture vs. page movement.
- **Mouse Wheel Calibration**: Optional wheel speed multiplier (`0.5x` – `2.5x`) and horizontal scroll inversion.
- **Multi-Language (`EN` / `IT`)**: Automatically adapts to system language with an instant in-app toggle.

---

## Installation

1. [**Download `Periphera.dmg`**](https://github.com/carlosiccardi/Periphera/releases/latest/download/Periphera.dmg) from the [Releases](https://github.com/carlosiccardi/Periphera/releases) page.
2. Drag **Periphera.app** into your `/Applications` folder and launch it.
3. Grant **Accessibility** permission when prompted (*System Settings → Privacy & Security → Accessibility*).

## Build from Source

```bash
chmod +x create_dmg.sh
./create_dmg.sh
```

## License

Released under the [MIT License](LICENSE). Copyright © 2026 Carlo Siccardi.

