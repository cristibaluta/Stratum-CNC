![Stratum CNC](https://myimgs.org/storage/images/71390/stratum-banner-light2x.png)

A 100% native macOS app for designing toolpaths and control **Makera CNC** machines. 

* **Instant Load Times:** Zero Electron or Java, small file size
* **Metal Rendering Engine:** Handles massive line G-code files at a locked 60+ FPS
* **CPU:** Zero CPU in idle
* **Compatibility:** Import Fusion360 tool libs
* **Open:** No proprietary project files, everything is open for you to inspect
* **Joystick Support:** Control the machine with game controllers (PlayStation 4).
* **Vector Processing:** Import and create toolpaths from SVG and DXF paths.

![Stratum CNC](https://myimgs.org/storage/images/72345/s1.png)
![Stratum CNC](https://myimgs.org/storage/images/72346/s2.png)
![Stratum CNC](https://myimgs.org/storage/images/72355/s3.png)

## Tech Stack
* **Language:** 100% Swift
* **Graphics:** `MetalKit` for GPU-accelerated G-code and toolpath visualization.
* **UI:** SwiftUI, and AppKit (`NSTableView` for G-code viewer).

## Dependencies
* **StratumCAM** the CAM toolpaths generator https://github.com/cristibaluta/Stratumcam
* **StratumLink** connects and communicates with the machine https://github.com/cristibaluta/Stratumlink
* **SwiftDXF** for parsing DXF files
* **PocketSVG** for parsing SVG files
* **zip** for unzipping Gerber archives
* **iShape** for merging geometries together, used for pcb traces

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
