# Stratum CNC

A 100% native macOS app for designing toolpaths and control **Makera Z1 CNC** machines. 

<!--<p align="center">-->
<!--  <img src="" width="128" height="128" alt="Stratum CNC Icon">-->
<!--</p>-->

---

## Why Stratum CNC?

Most CNC software is either locked to legacy Windows or wrapped in bloated web tech. Mac is always an afterthought. Stratum CNC is built from the ground up specifically for macOS.

* **Instant Load Times:** Zero Electron. Zero Java.
* **Metal Rendering Engine:** Handles massive line G-code files at a locked 60+ FPS.
* **CPU:** Zero CPU in idle.

---

## Core Features

### Machine Controller
* **Makera Ecosystem Integration:** Seamless connection and control optimized for Makera hardware.
* **Joystick Support:** Full mapping for game controllers (Xbox, PlayStation, etc.) for smooth, intuitive manual jogging.
* **High-Performance G-Code Viewer:** Powered by AppKit NSTableView capable of streaming heavy code without UI stutter.

### 2D CAM (Computer-Aided Manufacturing)
* **Vector Processing:** Import and create toolpaths from SVG and DXF paths.

---

## The Tech Stack

Stratum CNC relies entirely on Apple’s modern native frameworks:

* **Language:** 100% Swift
* **Graphics:** `MetalKit` for GPU-accelerated G-code and toolpath visualization.
* **UI:** AppKit (`NSTableView` for data virtualization and high-frequency UI updates); SwiftUI for everything else.

---

## Getting Started

### Prerequisites
* A Mac running macOS 15.0 or later.
* Apple Silicon (M1/M2/M3/M4 series) recommended for maximum Metal performance.
* A Makera CNC machine, but it can be used also without if you want just the CAM and G-code

* NOTE: To compile from sources you need to also download StratumCAM. This is temporary till development is getting more stable and will be imported

---

## Dependencies
* **StratumCAM** the CAM toolpaths generator. It was split from the project for better testing and separation. It uses SwiftDXF model internally
* **SwiftDXF** for parsing DXF files. The internal dxf model is used also inside the app, all the shapes are stored as DXF.Entity from import to toolpath generation
* **PocketSVG** for parsing SVG files.
* **OCCTSwift** for parsing 3d STEP files
* **zip** for unzipping gerber archives. The lib is already a dependency of OCCTSwift
* **iShape** for merging geometries together, used for pcb traces

---

## Roadmap

- [ ] 3D objects support
- [ ] Support for features Z1 doesn't have, like automatic tool change
- [ ] Support for other CNCs if possible

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
