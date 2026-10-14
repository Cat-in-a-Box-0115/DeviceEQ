DSP validation
==============

Build from the DeviceEQ directory:

```
clang++ -std=c++17 -O2 -Wall -Wextra -pedantic Sources/DSP/DSP.cpp Tests/DSP/DSPTests.cpp -o Tests/DSP/dsp-tests
Tests/DSP/dsp-tests
```

The numerical/rendered tests validate center gain, shelf endpoints, Butterworth cutoff gain, deep notch, combined-response headroom, independent channels, sustained sine gain, bypass, limiter ceiling, invalid configuration rejection, and SPSC publication with concurrent audio processing. An AddressSanitizer/UndefinedBehaviorSanitizer run also passed.

Filter convention: RBJ cookbook coefficients, Q for pass/notch/peak and Q for shelves. A shelf slope S is a distinct parameter and must be converted by the importer. Pass filters are second order (12 dB/octave), not arbitrary-order cascades.

Limits: headroom is a dense numerical estimate, not an analytic maximum; the optional hard limiter guarantees the sample ceiling but can distort when driven. A 20ms coefficient ramp suppresses abrupt parameter discontinuities but cannot guarantee inaudible transitions for every pathological filter, signal, or input change. Sustained EQ boosts can exceed digital full scale with automatic headroom and limiter both disabled, intentionally preserving the explicit preset.

Audio processing supports mono/stereo interleaved float samples. Keep one engine per processing route/device. Create/destroy and calculate/enqueue configurations outside the audio callback; only DEQProcessInterleaved belongs in the callback. Configuration producers must be serialized. The sample-rate field must match the actual stream; the engine does not resample.

Additional validation
---------------------

`StabilityTests.cpp` directly checks the Jury pole-stability inequalities for 270 extreme filter configurations (all six types, 1Hz–23999Hz, Q 0.05–100, gain ±48dB) and every pairwise 960-sample interpolation: 72,900 ramps. Passed. Stable poles establish filter stability, not inaudible transitions or a bound on transient amplification.

`APOTests.swift` validates standard AutoEq text, center shelf Q, shelf dB-slope conversion, corner-to-center conversion, independent channels, disabled filters, export/reimport, and explicit line-specific rejection of unsupported directives and parameters. Compile with:

```
swiftc Sources/App/APO.swift Tests/DSP/APOTests.swift -o Tests/DSP/apo-tests
Tests/DSP/apo-tests
clang++ -std=c++17 -O2 Tests/DSP/StabilityTests.cpp -o Tests/DSP/stability-tests
Tests/DSP/stability-tests
```

APO conventions verified against the official configuration reference:
https://sourceforge.net/p/equalizerapo/wiki/Configuration%20reference/

Equivalent source behavior was inspected in the project's BiQuadFilterFactory.cpp, BiQuadFilter.cpp, and BiQuad.cpp. The importer implements the mathematical parameter conversion independently. Bare LS/HS have S=0.9 and center-frequency semantics; explicit LS/HS Q/slope use corner frequency. Export always writes unambiguous LSC/HSC center-frequency Q.

Unsupported imports deliberately fail: expressions, modal decay parameters, bandwidth-in-octaves (stream sample rate required), IIR/custom coefficients, graphic EQ, includes, device conditions, delays, convolution, and non-stereo channels. Per-channel preamp fails because the preset has one common preamp. Repeated common preamps add in dB, matching APO.
