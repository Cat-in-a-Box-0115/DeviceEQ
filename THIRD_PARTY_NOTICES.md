# Attribution

DeviceEQ's Swift editor, Core Audio bridge, DSP implementation and flat response-curve app/menu icon are original project code/assets, covered by LICENSE. No eqMac source, paid code, binary, driver or artwork is distributed.

- Filter formulas follow Robert Bristow-Johnson's public Audio EQ Cookbook: https://www.w3.org/TR/audio-eq-cookbook/ . This implementation computes the formulas independently.
- Imported text follows Equalizer APO's documented parameter conventions: https://sourceforge.net/p/equalizerapo/wiki/Configuration%20reference/ . No Equalizer APO code is bundled.
- Some interface symbols use Apple's SF Symbols through the system framework. Apple's frameworks and symbols remain governed by Apple's terms; they are not relicensed under MIT. The standalone app icon is original geometry, not a redistributed SF Symbol.
- Squiglink/AutoEq are supported external export formats, not bundled code or datasets. Users supply their own presets. Test import data is synthetic and is not a headphone recommendation.

The release has no Python runtime, external package dependency, downloaded measurement database or vendored AutoEq implementation. Apple system frameworks are required at runtime.
