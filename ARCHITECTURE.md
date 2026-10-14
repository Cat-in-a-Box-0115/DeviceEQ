# Architecture

SwiftUI presents independent profiles indexed by persistent Core Audio UID. The main actor owns model state; device enumeration, route construction, statistics, selection and teardown share a serial background queue. Snapshots retain native handles until their queued read finishes. Shutdown waits for pending construction and teardown.

Each enabled stereo physical output uses a private Core Audio aggregate plus a process tap scoped to that physical device. The tap excludes this app's process and uses muted-when-tapped routing; callback output is processed PCM returned to that device. Public macOS output selection stays on the physical device, retaining its native volume controls. Hardware input streams are disabled for the route IOProc. Unsupported formats fail without redirecting other outputs.

The C++ DSP implements RBJ biquads with double-precision state, a bounded lock-free SPSC configuration queue and coefficient/gain smoothing. Audio callbacks avoid allocation and locks. Auto headroom is computed from the response and reduces preamp; the app disables the internal legacy hard ceiling. Volume is not multiplied again by the DSP.

APO imports are parsed and validated transactionally before replacing a profile. External files cannot execute Include directives or partially overwrite state after an error. Persisted legacy curve metadata is supported for profile compatibility, but correction fitting/search code and its Python dependencies have been removed.

The bundle identifier `org.deviceeq.app`, executable name `DeviceEQ`, internal DEQ symbols and storage directory remain stable for existing installations. The product remains DeviceEQ. A release maintainer may choose a permanent bundle identifier before their first signed release; changing it later can require new macOS permissions.
