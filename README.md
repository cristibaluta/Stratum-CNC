![Stratum CNC](https://myimgs.org/storage/images/71390/stratum-banner-light2x.png)

A 100% native macOS app for designing toolpaths and control **Makera CNC** machines. 

- **Native and lightweight:** built in Swift for macOS, with no Electron or Java. Small download, instant launch.
- **Metal rendering:** smooth FPS even with massive G-code files.
- **Easy on resources:** near-zero CPU when idle and a memory footprint comparable to a browser tab.
- **Fusion 360 compatible:** import your existing Fusion 360 tool libraries.
- **Open formats:** no proprietary project files. Everything is stored in plain, inspectable files.
- **Gamepad control:** jog the machine with a PlayStation 4 controller.
- **SVG and DXF import:** create toolpaths straight from vector paths.
- **Gerber import:** create toolpaths for PCBs.

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
* **SwiftSTEP** for parsing STEP/STL files https://github.com/cristibaluta/SwiftSTEP
* **SwiftDXF** for parsing DXF files
* **PocketSVG** for parsing SVG files
* **zip** for unzipping Gerber archives
* **iShape** for merging geometries together, used for pcb traces

---

## License

Stratum CNC is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the [LICENSE](LICENSE) file for details.

You are free to use, study, modify and sell this software, but any version you
distribute, modified or not, must stay open source under the same license.
Closed-source redistribution is not permitted.

Copyright (C) 2026 Cristian Baluta
