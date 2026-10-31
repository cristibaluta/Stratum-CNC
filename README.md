![Stratum CNC](https://myimgs.org/storage/images/71390/stratum-banner-light2x.png)

A 100% native macOS app for designing toolpaths and control **Makera CNC** machines. 

<!--<p align="center">-->
<!--  <img src="" width="128" height="128" alt="Stratum CNC Icon">-->
<!--</p>-->

![Stratum CNC](https://www.dropbox.com/scl/fi/3jtwbh8cxa7sdnzieozah/s1.png?rlkey=567c2qx6tkz49y4yp3heb0att&st=dyak8gye&dl=0)
![Stratum CNC](https://www.dropbox.com/scl/fi/ly3ubq5uuv6ntuh0hv9pa/s2.png?rlkey=9bdtmgenbzhw7zvrsut7rnoue&st=s8mldiey&dl=0)
![Stratum CNC](https://www.dropbox.com/scl/fi/9nhl7a0mgz5vibja5p24w/s3.png?rlkey=ed4wv7i7zcvopm4sh6ilbkzkj&st=gphlepbm&dl=0)

* **Instant Load Times:** Zero Electron or Java, small file size
* **Metal Rendering Engine:** Handles massive line G-code files at a locked 60+ FPS
* **CPU:** Zero CPU in idle
* **Compatibility:** Import Fusion360 tool libs
* **Open:** No proprietary project files, everything is open for you to inspect
* **Joystick Support:** Control the machine with game controllers (PlayStation 4).
* **Vector Processing:** Import and create toolpaths from SVG and DXF paths.

---

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
