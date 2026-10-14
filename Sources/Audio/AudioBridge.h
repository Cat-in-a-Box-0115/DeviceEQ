#pragma once
#include "../DSP/DSP.h"
#ifdef __cplusplus
extern "C" {
#endif
void DEQFreeString(char *value);
char *DEQDevicesJSON(void);
/* Physical native volume; unsupported hardware returns supportsVolume=false/0.
   Channel fallback preserves balance. Never applies additional DSP gain. */
char *DEQDeviceVolumeJSON(const char *uid);
int DEQDeviceSetVolume(const char *uid, float scalar);
int DEQDeviceSetMute(const char *uid, int muted);
/* Removes only recorded, unlocked stale DeviceEQ endpoints. Call before route restoration. */
int DEQCleanupStaleRoutes(void);
/* Test/state restoration: save current UID, then restore that exact output if present. */
char *DEQDefaultOutputUID(void);
int DEQRestoreOutputUID(const char *uid);
char *DEQRouteError(void);
typedef struct DEQRoute DEQRoute;
/* Prepare never starts capture or changes default output. */
DEQRoute *DEQRoutePrepare(const char *deviceUID, const DEQConfig *config);
/* Native-volume mode: private processor scoped to the physical UID. The physical
   output remains selectable normally in macOS; no public endpoint needed. */
DEQRoute *DEQRoutePreparePhysical(const char *deviceUID, const DEQConfig *config);
DEQRoute *DEQRouteCreatePhysical(const char *deviceUID, const DEQConfig *config);
int DEQRouteStart(DEQRoute *route);
DEQRoute *DEQRouteCreate(const char *deviceUID, const DEQConfig *config);
void DEQRouteDestroy(DEQRoute *route);
int DEQRouteUpdate(DEQRoute *route, const DEQConfig *config);
int DEQRouteSelect(DEQRoute *route);
char *DEQRouteStatsJSON(DEQRoute *route);
/* Testing only: starts an UNMUTED observational tap in this app permission context.
   No default-output change. Stats are digital pre-hardware, not analog-loopback proof. */
typedef struct DEQMonitor DEQMonitor;
DEQMonitor *DEQMonitorStart(const char *deviceUID, double frequency);
/* Include only DeviceEQ's own audio process, excluding the raw external producer. */
DEQMonitor *DEQMonitorStartOwnProcess(const char *deviceUID, double frequency);
char *DEQMonitorStatsJSON(DEQMonitor *monitor);
void DEQMonitorDestroy(DEQMonitor *monitor);
/* Blocking controlled test, after user recording permission; serial control thread only.
   JSON: {"deviceUIDs":["physicalA","physicalB"],"toneHelperPath":"/absolute/route-tone"}.
   Requires no preexisting routes for those UIDs. Emits three bounded -60 dBFS tones;
   uses endpoints directly, preserves default output, returns actual evidence JSON. */
char *DEQRoutingVerify(const char *argumentsJSON);
/* Explicit authorized test, no other routes for UID. JSON deviceUID/toneHelperPath.
   Bounded quiet tones; selects physical output temporarily, lowers hardware volume
   to at most .25, then restores exact original volume/output. Same app TCC context. */
char *DEQPhysicalRoutingVerify(const char *argumentsJSON);
#ifdef __cplusplus
}
#endif
