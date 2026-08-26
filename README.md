# Stratum CNC

A highly performant, 100% native macOS application engineered to design toolpaths and control **Makera CNC** machines. 

By bypassing heavy cross-platform frameworks, **Stratum CNC** leverages Apple Silicon and hardware-accelerated graphics to deliver a fluid, lag-free fabrication workflow.

<!--<p align="center">-->
<!--  <img src="" width="128" height="128" alt="Stratum CNC Icon">-->
<!--</p>-->

---

## Why Stratum CNC?

Most desktop CNC software is either locked to legacy Windows environments or wrapped in bloated web tech. Stratum CNC is built from the ground up specifically for macOS, treating your desktop mill like a first-class citizen.

* **Instant Load Times:** Zero Electron. Zero Java. Pure native execution.
* **Metal Rendering Engine:** Handles massive, multi-million line G-code files at a locked 60+ FPS.
* **Tactile Jogging:** Ditch the mouse—plug in any standard game joystick to steer your spindle physically.

---

## Core Features

### Machine Controller
* **Makera Ecosystem Integration:** Seamless connection and control optimized for Makera hardware profiles.
* **Joystick Support:** Full mapping for game controllers (Xbox, PlayStation, etc.) for smooth, intuitive manual jogging.
* **High-Performance G-Code Viewer:** Powered by AppKit NSTableView capable of streaming heavy code without UI stutter.

### 2D CAM (Computer-Aided Manufacturing)
* **Vector Vector Processing:** Import and process SVG paths directly inside the app.
* **Toolpath Generation:** Fast calculations for profiling, pocketing, and drilling cycles.

---

## The Tech Stack

Stratum CNC relies entirely on Apple’s modern native frameworks for elite system efficiency:

* **Language:** 100% Swift
* **Graphics Pipeline:** `MetalKit` & `Metal` API for GPU-accelerated G-code and toolpath visualization.
* **UI Foundation:** AppKit / Cocoa (`NSTableView` for data virtualization and high-frequency UI updates).

---

## Getting Started

### Prerequisites
* A Mac running macOS 13.0 (Ventura) or later.
* Apple Silicon (M1/M2/M3/M4 series) recommended for maximum Metal performance.
* A Makera CNC machine.

### Installation & Development
1. AppStore
2. Releases page
3. Compile locally

---

## Roadmap

- [ ] 3D mesh rendering & multi-axis CAM generation
- [ ] Automatic tool changer (ATC) macros for Makera

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
