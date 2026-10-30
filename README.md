![Stratum CNC](https://myimgs.org/storage/images/71390/stratum-banner-light2x.png)

A 100% native macOS app for designing toolpaths and control **Makera CNC** machines. 

<!--<p align="center">-->
<!--  <img src="" width="128" height="128" alt="Stratum CNC Icon">-->
<!--</p>-->

---

## Goal

Most CNC software is either for Windows, either bloated electron and web crossplatform tech, mac is always an afterthought. Stratum CNC is built from the groud up specifically for macOS, following the macOS design guidelines. Between its advantages:

* **Instant Load Times:** Zero Electron or Java, small file size
* **Metal Rendering Engine:** Handles massive line G-code files at a locked 60+ FPS
* **CPU:** Zero CPU in idle
* **Compatibility:** Compatible with Fusion360 tool lib imports
* **Transparency:** No proprietary project files, everything is open for you to inspect

---

## Core Features

### Machine Controller
* **Makera Ecosystem Integration:** Connection and control for Makera hardware.
* **Joystick Support:** Full mapping for game controllers (PlayStation 4) for manual jogging.
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

## Dependencies
* **StratumCAM** the CAM toolpaths generator
* **StratumLink** the part that connects to the machine
* **SwiftDXF** for parsing DXF files. The internal dxf model is used also inside the app, all the shapes are stored as DXF.Entity from import to toolpath generation
* **PocketSVG** for parsing SVG files
* **OCCTSwift** for parsing 3d STEP files
* **zip** for unzipping gerber archives. The lib is already a dependency of OCCTSwift
* **iShape** for merging geometries together, used for pcb traces

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
