#include "AudioBridge.h"
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstring>
#include <fcntl.h>
#include <string>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

static NSString *lastError = @"";
static AudioObjectPropertyAddress address(UInt32 selector, UInt32 scope = kAudioObjectPropertyScopeGlobal) {
    return {selector, scope, kAudioObjectPropertyElementMain};
}
static NSString *stringProperty(AudioObjectID id, UInt32 selector) {
    CFStringRef s = nullptr;
    UInt32 size = sizeof(s);
    auto a = address(selector);
    if (AudioObjectGetPropertyData(id, &a, 0, nullptr, &size, &s) != noErr || !s)
        return @"";
    return CFBridgingRelease(s);
}
static UInt32 channels(AudioObjectID id, UInt32 scope) {
    auto a = address(kAudioDevicePropertyStreamConfiguration, scope);
    UInt32 n = 0;
    if (AudioObjectGetPropertyDataSize(id, &a, 0, nullptr, &n) != noErr)
        return 0;
    std::vector<unsigned char> bytes(n);
    auto b = (AudioBufferList *)bytes.data();
    if (AudioObjectGetPropertyData(id, &a, 0, nullptr, &n, b) != noErr)
        return 0;
    UInt32 c = 0;
    for (UInt32 i = 0; i < b->mNumberBuffers; i++)
        c += b->mBuffers[i].mNumberChannels;
    return c;
}
static std::vector<AudioObjectID> devices() {
    auto a = address(kAudioHardwarePropertyDevices);
    UInt32 n = 0;
    AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, nullptr, &n);
    std::vector<AudioObjectID> d(n / sizeof(AudioObjectID));
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, nullptr, &n, d.data());
    return d;
}
static AudioObjectID findDevice(NSString *uid) {
    for (auto id : devices())
        if ([stringProperty(id, kAudioDevicePropertyDeviceUID) isEqualToString:uid])
            return id;
    return 0;
}
static double sampleRate(AudioObjectID id) {
    double r = 48000;
    UInt32 n = sizeof(r);
    auto a = address(kAudioDevicePropertyNominalSampleRate);
    AudioObjectGetPropertyData(id, &a, 0, nullptr, &n, &r);
    return r;
}
static AudioObjectID defaultDevice(UInt32 selector = kAudioHardwarePropertyDefaultOutputDevice) {
    AudioObjectID d = 0;
    UInt32 n = sizeof(d);
    auto a = address(selector);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, nullptr, &n, &d);
    return d;
}
static OSStatus setDefault(AudioObjectID d, UInt32 selector = kAudioHardwarePropertyDefaultOutputDevice) {
    auto a = address(selector);
    return AudioObjectSetPropertyData(kAudioObjectSystemObject, &a, 0, nullptr, sizeof(d), &d);
}
static char *json(id obj) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    return strdup([[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding].UTF8String);
}
void DEQFreeString(char *v) {
    free(v);
}
char *DEQRouteError() {
    return strdup(lastError.UTF8String);
}
// A lease's advisory lock proves a route is still owned even if its app is idle.
// Stale cleanup requires both a recorded UID and an unlocked lease; never sweep by name alone.
static NSString *leaseDirectory() {
    NSString *base =
        NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"DeviceEQ/RouteLeases"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:@{
                                                   NSFilePosixPermissions : @0700
                                               }
                                                    error:nil];
    return dir;
}
static NSString *leasePath(NSString *uid) {
    NSString *key = [[uid dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    key = [[key stringByReplacingOccurrencesOfString:@"/"
                                          withString:@"_"] stringByReplacingOccurrencesOfString:@"+"
                                                                                     withString:@"-"];
    return [leaseDirectory() stringByAppendingPathComponent:[key stringByAppendingString:@".json"]];
}
static int acquireLease(NSString *uid) {
    int fd = open(leasePath(uid).fileSystemRepresentation, O_RDWR | O_CREAT | O_NOFOLLOW, 0600);
    if (fd < 0)
        return -1;
    if (flock(fd, LOCK_EX | LOCK_NB)) {
        close(fd);
        return -1;
    }
    return fd;
}
static bool writeLease(int fd, NSString *endpoint, NSString *physical, NSString *tap) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:@{
        @"endpointUID" : endpoint,
        @"physicalUID" : physical,
        @"tapUID" : tap ?: @"",
        @"pid" : @(getpid()),
        @"schema" : @1
    }
                                                options:0
                                                  error:nil];
    if (ftruncate(fd, 0) || lseek(fd, 0, SEEK_SET) < 0)
        return false;
    return write(fd, d.bytes, d.length) == (ssize_t)d.length && fsync(fd) == 0;
}
static NSDictionary *readLease(int fd) {
    struct stat st{};
    if (fstat(fd, &st) || st.st_size <= 0 || st.st_size > 65536)
        return nil;
    NSMutableData *d = [NSMutableData dataWithLength:st.st_size];
    if (pread(fd, d.mutableBytes, d.length, 0) != (ssize_t)d.length)
        return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    return [obj isKindOfClass:NSDictionary.class] ? obj : nil;
}
static AudioObjectID findTap(NSString *uid) {
    auto a = address(kAudioHardwarePropertyTapList);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, nullptr, &size) != noErr)
        return 0;
    std::vector<AudioObjectID> list(size / sizeof(AudioObjectID));
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, nullptr, &size, list.data()) != noErr)
        return 0;
    for (auto id : list)
        if ([stringProperty(id, kAudioTapPropertyUID) isEqualToString:uid])
            return id;
    return 0;
}
int DEQCleanupStaleRoutes() {
    @autoreleasepool {
        int removed = 0;
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:leaseDirectory()
                                                                             error:nil];
        for (NSString *file in files) {
            if (![file hasSuffix:@".json"])
                continue;
            NSString *path = [leaseDirectory() stringByAppendingPathComponent:file];
            int fd = open(path.fileSystemRepresentation, O_RDWR | O_NOFOLLOW);
            if (fd < 0)
                continue;
            if (flock(fd, LOCK_EX | LOCK_NB)) {
                close(fd);
                continue;
            }
            NSDictionary *record = readLease(fd);
            NSString *endpoint = record[@"endpointUID"], *physical = record[@"physicalUID"],
                     *tap = record[@"tapUID"];
            bool owned =
                [endpoint isKindOfClass:NSString.class] && [physical isKindOfClass:NSString.class] &&
                [tap isKindOfClass:NSString.class] &&
                [endpoint isEqualToString:[@"org.deviceeq.endpoint." stringByAppendingString:physical]] &&
                [path isEqualToString:leasePath(endpoint)] && [record[@"schema"] intValue] == 1;
            if (owned) {
                AudioObjectID id = findDevice(endpoint);
                if (id) {
                    CFArrayRef sub = nullptr;
                    UInt32 size = sizeof(sub);
                    auto a = address(kAudioAggregateDevicePropertyFullSubDeviceList);
                    bool matches = AudioObjectGetPropertyData(id, &a, 0, nullptr, &size, &sub) == noErr &&
                                   sub && CFArrayGetCount(sub) == 1 &&
                                   CFEqual(CFArrayGetValueAtIndex(sub, 0), (__bridge CFStringRef)physical);
                    if (sub)
                        CFRelease(sub);
                    if (matches) {
                        AudioObjectID destination = findDevice(physical);
                        if (destination) {
                            if (defaultDevice() == id)
                                setDefault(destination);
                            if (defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice) == id)
                                setDefault(destination, kAudioHardwarePropertyDefaultSystemOutputDevice);
                        }
                        if (AudioHardwareDestroyAggregateDevice(id) == noErr)
                            removed++;
                        else
                            owned = false;
                    } else
                        owned = false;
                }
                if (owned && tap.length) {
                    AudioObjectID tid = findTap(tap);
                    if (tid) {
                        CATapDescription *description = nil;
                        UInt32 size = sizeof(description);
                        auto a = address(kAudioTapPropertyDescription);
                        if (AudioObjectGetPropertyData(tid, &a, 0, nullptr, &size, &description) == noErr &&
                            ([description.deviceUID isEqualToString:endpoint] ||
                             [description.deviceUID isEqualToString:physical]))
                            AudioHardwareDestroyProcessTap(tid);
                    }
                }
                if (owned) {
                    ftruncate(fd, 0);
                    fsync(fd);
                }
            }
            flock(fd, LOCK_UN);
            close(fd);
        }
        return removed;
    }
}
static bool isVirtualDevice(AudioObjectID id) {
    UInt32 transport = 0, size = sizeof(transport);
    auto a = address(kAudioDevicePropertyTransportType);
    AudioObjectGetPropertyData(id, &a, 0, nullptr, &size, &transport);
    NSString *uid = stringProperty(id, kAudioDevicePropertyDeviceUID);
    NSString *model = stringProperty(id, kAudioDevicePropertyModelUID);
    return transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeAggregate ||
           [uid hasPrefix:@"org.deviceeq.endpoint."] || [uid isEqualToString:@"EQMOutputCapture"] ||
           [model.lowercaseString containsString:@"eqmac"];
}

static bool propertySettable(AudioObjectID id, UInt32 selector, UInt32 element) {
    AudioObjectPropertyAddress a{selector, kAudioObjectPropertyScopeOutput, element};
    Boolean settable = false;
    return AudioObjectHasProperty(id, &a) && AudioObjectIsPropertySettable(id, &a, &settable) == noErr &&
           settable;
}
static bool scalarVolume(AudioObjectID id, UInt32 element, float &value) {
    AudioObjectPropertyAddress a{kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, element};
    UInt32 size = sizeof(value);
    return AudioObjectHasProperty(id, &a) &&
           AudioObjectGetPropertyData(id, &a, 0, nullptr, &size, &value) == noErr;
}
static bool muteValue(AudioObjectID id, UInt32 element, UInt32 &value) {
    AudioObjectPropertyAddress a{kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, element};
    UInt32 size = sizeof(value);
    return AudioObjectHasProperty(id, &a) &&
           AudioObjectGetPropertyData(id, &a, 0, nullptr, &size, &value) == noErr;
}
static NSDictionary *volumeInfo(AudioObjectID id) {
    float master = 0, left = 0, right = 0;
    bool m = scalarVolume(id, 0, master), l = scalarVolume(id, 1, left), r = scalarVolume(id, 2, right);
    UInt32 mute = 0;
    bool hasMute = muteValue(id, 0, mute);
    if (!hasMute)
        hasMute = muteValue(id, 1, mute);
    bool writable = m ? propertySettable(id, kAudioDevicePropertyVolumeScalar, 0)
                      : l && r && propertySettable(id, kAudioDevicePropertyVolumeScalar, 1) &&
                            propertySettable(id, kAudioDevicePropertyVolumeScalar, 2);
    return @{
        @"supportsVolume" : @(writable),
        @"volumeReadable" : @(m || (l && r)),
        @"volume" : @(m ? master : std::max(left, right)),
        @"usesChannelVolume" : @(!m && l && r),
        @"supportsMute" : @(propertySettable(id, kAudioDevicePropertyMute, 0) ||
                            (propertySettable(id, kAudioDevicePropertyMute, 1) &&
                             propertySettable(id, kAudioDevicePropertyMute, 2))),
        @"muted" : @(hasMute && mute != 0)
    };
}
char *DEQDeviceVolumeJSON(const char *uid) {
    if (!uid)
        return json(@{});
    AudioObjectID id = findDevice([NSString stringWithUTF8String:uid]);
    return id ? json(volumeInfo(id)) : json(@{});
}
int DEQDeviceSetVolume(const char *uid, float value) {
    if (!uid || !std::isfinite(value) || value < 0 || value > 1)
        return 0;
    AudioObjectID id = findDevice([NSString stringWithUTF8String:uid]);
    if (!id || isVirtualDevice(id))
        return 0;
    if (propertySettable(id, kAudioDevicePropertyVolumeScalar, 0)) {
        AudioObjectPropertyAddress a{kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 0};
        return AudioObjectSetPropertyData(id, &a, 0, nullptr, sizeof(value), &value) == noErr;
    }
    float old[2] = {0, 0};
    if (!scalarVolume(id, 1, old[0]) || !scalarVolume(id, 2, old[1]) ||
        !propertySettable(id, kAudioDevicePropertyVolumeScalar, 1) ||
        !propertySettable(id, kAudioDevicePropertyVolumeScalar, 2))
        return 0;
    float max = std::max(old[0], old[1]);
    float next[2] = {max > 0 ? value * old[0] / max : value, max > 0 ? value * old[1] / max : value};
    for (UInt32 channel = 1; channel <= 2; channel++) {
        AudioObjectPropertyAddress a{kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput,
                                     channel};
        if (AudioObjectSetPropertyData(id, &a, 0, nullptr, sizeof(float), &next[channel - 1]) != noErr) {
            for (UInt32 restore = 1; restore < channel; restore++) {
                a.mElement = restore;
                AudioObjectSetPropertyData(id, &a, 0, nullptr, sizeof(float), &old[restore - 1]);
            }
            return 0;
        }
    }
    return 1;
}
int DEQDeviceSetMute(const char *uid, int muted) {
    if (!uid)
        return 0;
    AudioObjectID id = findDevice([NSString stringWithUTF8String:uid]);
    if (!id || isVirtualDevice(id))
        return 0;
    UInt32 value = muted ? 1 : 0;
    if (propertySettable(id, kAudioDevicePropertyMute, 0)) {
        AudioObjectPropertyAddress a{kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, 0};
        return AudioObjectSetPropertyData(id, &a, 0, nullptr, sizeof(value), &value) == noErr;
    }
    UInt32 old[2] = {0, 0};
    if (!muteValue(id, 1, old[0]) || !muteValue(id, 2, old[1]) ||
        !propertySettable(id, kAudioDevicePropertyMute, 1) ||
        !propertySettable(id, kAudioDevicePropertyMute, 2))
        return 0;
    for (UInt32 channel = 1; channel <= 2; channel++) {
        AudioObjectPropertyAddress a{kAudioDevicePropertyMute, kAudioObjectPropertyScopeOutput, channel};
        if (AudioObjectSetPropertyData(id, &a, 0, nullptr, sizeof(value), &value) != noErr) {
            if (channel == 2) {
                a.mElement = 1;
                AudioObjectSetPropertyData(id, &a, 0, nullptr, sizeof(UInt32), &old[0]);
            }
            return 0;
        }
    }
    return 1;
}

char *DEQDevicesJSON() {
    NSMutableArray *result = [NSMutableArray array];
    for (auto id : devices()) {
        auto c = channels(id, kAudioObjectPropertyScopeOutput);
        if (!c)
            continue;
        NSString *uid = stringProperty(id, kAudioDevicePropertyDeviceUID);
        UInt32 transport = 0;
        UInt32 size = sizeof(transport);
        auto a = address(kAudioDevicePropertyTransportType);
        AudioObjectGetPropertyData(id, &a, 0, nullptr, &size, &transport);
        [result addObject:@{
            @"id" : @(id),
            @"uid" : uid,
            @"name" : stringProperty(id, kAudioObjectPropertyName),
            @"channels" : @(c),
            @"volumeSupport" : volumeInfo(id),
            @"sampleRate" : @(sampleRate(id)),
            @"isDefault" : @(id == defaultDevice()),
            @"isVirtual" : @(isVirtualDevice(id)),
            @"managed" : @([uid hasPrefix:@"org.deviceeq.endpoint."])
        }];
    }
    return json(result);
}
struct DEQRoute {
    AudioObjectID physical = 0, endpoint = 0, tap = 0;
    AudioDeviceIOProcID proc = nullptr;
    DEQEngine *dsp = nullptr;
    double rate = 48000;
    UInt32 inputSkip = 0, physicalInputStreams = 0;
    bool hardwareInputsDisabled = false;
    std::array<float, 32768> scratch{};
    std::atomic<uint64_t> callbacks{0}, frames{0}, oversize{0};
    std::atomic<float> inputPeak{0}, outputPeak{0}, maxInputPeak{0}, maxOutputPeak{0};
    std::atomic<uint64_t> inputClips{0}, outputClips{0};
    double inputEnergy = 0, outputEnergy = 0;
    uint64_t samples = 0;
    std::atomic<double> inputRMS{0}, outputRMS{0};
    std::atomic<bool> selected{false}, invalid{false};
    bool started = false, listeners = false;
    std::string physicalUID;
    int leaseFD = -1;
    bool leaseOwnsRecord = false, physicalMode = false;
    std::string captureUID;
};
static float inputSample(const AudioBufferList *abl, UInt32 channel, UInt32 frame) {
    if (!abl)
        return 0;
    for (UInt32 i = 0; i < abl->mNumberBuffers; i++) {
        const auto &b = abl->mBuffers[i];
        if (channel >= b.mNumberChannels) {
            channel -= b.mNumberChannels;
            continue;
        }
        UInt32 samples = b.mDataByteSize / sizeof(float);
        UInt32 index = frame * b.mNumberChannels + channel;
        return b.mData && index < samples ? ((const float *)b.mData)[index] : 0;
    }
    return 0;
}
static OSStatus io(AudioObjectID, const AudioTimeStamp *, const AudioBufferList *in, const AudioTimeStamp *,
                   AudioBufferList *out, const AudioTimeStamp *, void *ctx) {
    auto *r = (DEQRoute *)ctx;
    if (!out)
        return noErr;
    UInt32 frames = 0;
    for (UInt32 i = 0; i < out->mNumberBuffers; i++) {
        auto &b = out->mBuffers[i];
        if (b.mNumberChannels)
            frames = std::max(frames, b.mDataByteSize / (UInt32)(sizeof(float) * b.mNumberChannels));
        if (b.mData)
            memset(b.mData, 0, b.mDataByteSize);
    }
    if (r->invalid.load(std::memory_order_acquire))
        return noErr;
    if (frames * 2 > r->scratch.size()) {
        r->oversize++;
        return noErr;
    }
    float ip = 0, op = 0;
    for (UInt32 f = 0; f < frames; f++)
        for (UInt32 c = 0; c < 2; c++) {
            float v = inputSample(in, r->inputSkip + c, f);
            r->scratch[f * 2 + c] = v;
            ip = std::max(ip, std::fabs(v));
            r->inputEnergy += double(v) * v;
            if (fabsf(v) >= 1)
                r->inputClips++;
            r->samples++;
        }
    DEQProcessInterleaved(r->dsp, r->scratch.data(), frames, 2);
    for (UInt32 f = 0; f < frames; f++)
        for (UInt32 c = 0; c < 2; c++) {
            float value = r->scratch[f * 2 + c];
            op = std::max(op, std::fabs(value));
            r->outputEnergy += double(value) * value;
            if (fabsf(value) >= 1)
                r->outputClips++;
        }
    UInt32 channelBase = 0;
    for (UInt32 i = 0; i < out->mNumberBuffers; i++) {
        auto &b = out->mBuffers[i];
        if (!b.mData)
            continue;
        UInt32 count = b.mDataByteSize / (sizeof(float) * std::max(1u, b.mNumberChannels));
        for (UInt32 f = 0; f < std::min(frames, count); f++)
            for (UInt32 c = 0; c < b.mNumberChannels; c++) {
                UInt32 ch = channelBase + c;
                if (ch < 2)
                    ((float *)b.mData)[f * b.mNumberChannels + c] = r->scratch[f * 2 + ch];
            }
        channelBase += b.mNumberChannels;
    }
    r->inputRMS.store(r->samples ? sqrt(r->inputEnergy / r->samples) : 0, std::memory_order_relaxed);
    r->outputRMS.store(r->samples ? sqrt(r->outputEnergy / r->samples) : 0, std::memory_order_relaxed);
    r->maxInputPeak.store(std::max(ip, r->maxInputPeak.load(std::memory_order_relaxed)),
                          std::memory_order_relaxed);
    r->maxOutputPeak.store(std::max(op, r->maxOutputPeak.load(std::memory_order_relaxed)),
                           std::memory_order_relaxed);
    r->inputPeak.store(ip, std::memory_order_relaxed);
    r->outputPeak.store(op, std::memory_order_relaxed);
    r->callbacks++;
    r->frames += frames;
    return noErr;
}
// All route control calls must be serialized on the application's main/control thread.
// HAL listeners only publish invalidation; they never mutate DSP or destroy callback state.
static OSStatus changed(AudioObjectID object, UInt32 count, const AudioObjectPropertyAddress *properties,
                        void *context) {
    auto *r = (DEQRoute *)context;
    if (object == kAudioObjectSystemObject)
        return noErr; /* Device-list events include our own aggregate creation. Never call HAL from this
                         listener: the serial control poll checks disconnection and format changes. */
    r->invalid.store(true, std::memory_order_release);
    return noErr;
}
static std::array<AudioObjectPropertyAddress, 3> routeProperties() {
    return {address(kAudioDevicePropertyNominalSampleRate), address(kAudioDevicePropertyDeviceIsAlive),
            address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeOutput)};
}
static OSStatus addListeners(DEQRoute *r) {
    auto properties = routeProperties();
    size_t added = 0;
    for (auto &a : properties) {
        OSStatus st = AudioObjectAddPropertyListener(r->physical, &a, changed, r);
        if (st) {
            for (size_t i = 0; i < added; i++)
                AudioObjectRemovePropertyListener(r->physical, &properties[i], changed, r);
            return st;
        }
        added++;
    }
    auto list = address(kAudioHardwarePropertyDevices);
    OSStatus st = AudioObjectAddPropertyListener(kAudioObjectSystemObject, &list, changed, r);
    if (st) {
        for (auto &a : properties)
            AudioObjectRemovePropertyListener(r->physical, &a, changed, r);
        return st;
    }
    r->listeners = true;
    return noErr;
}
static void removeListeners(DEQRoute *r) {
    if (!r->listeners)
        return;
    for (auto &a : routeProperties())
        AudioObjectRemovePropertyListener(r->physical, &a, changed, r);
    auto list = address(kAudioHardwarePropertyDevices);
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &list, changed, r);
    r->listeners = false;
}
static OSStatus validateStreams(AudioObjectID d, UInt32 scope, UInt32 skipStreams = 0) {
    auto a = address(kAudioDevicePropertyStreams, scope);
    UInt32 n = 0;
    OSStatus st = AudioObjectGetPropertyDataSize(d, &a, 0, nullptr, &n);
    if (st)
        return st;
    std::vector<AudioStreamID> streams(n / sizeof(AudioStreamID));
    st = AudioObjectGetPropertyData(d, &a, 0, nullptr, &n, streams.data());
    if (st)
        return st;
    for (size_t index = skipStreams; index < streams.size(); index++) {
        auto stream = streams[index];
        AudioStreamBasicDescription f{};
        n = sizeof(f);
        a = address(kAudioStreamPropertyVirtualFormat);
        st = AudioObjectGetPropertyData(stream, &a, 0, nullptr, &n, &f);
        if (st)
            return st;
        if (f.mFormatID != kAudioFormatLinearPCM || !(f.mFormatFlags & kAudioFormatFlagIsFloat) ||
            !(f.mFormatFlags & kAudioFormatFlagIsPacked) || f.mBitsPerChannel != 32)
            return kAudioDeviceUnsupportedFormatError;
    }
    return noErr;
}
static UInt32 streamCount(AudioObjectID d, UInt32 scope) {
    auto a = address(kAudioDevicePropertyStreams, scope);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(d, &a, 0, nullptr, &size) != noErr)
        return 0;
    return size / sizeof(AudioStreamID);
}
static OSStatus disablePhysicalInputs(DEQRoute *r) {
    r->physicalInputStreams = streamCount(r->physical, kAudioObjectPropertyScopeInput);
    if (!r->physicalInputStreams) {
        r->hardwareInputsDisabled = true;
        return noErr;
    }
    UInt32 total = streamCount(r->endpoint, kAudioObjectPropertyScopeInput);
    if (total <= r->physicalInputStreams)
        return kAudioDeviceUnsupportedFormatError;
    UInt32 size = offsetof(AudioHardwareIOProcStreamUsage, mStreamIsOn) + total * sizeof(UInt32);
    std::vector<unsigned char> bytes(size);
    auto *usage = (AudioHardwareIOProcStreamUsage *)bytes.data();
    usage->mIOProc = reinterpret_cast<void *>(r->proc);
    usage->mNumberStreams = total;
    for (UInt32 i = 0; i < total; i++)
        usage->mStreamIsOn[i] = i < r->physicalInputStreams ? 0 : 1;
    auto a = address(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput);
    OSStatus status = AudioObjectSetPropertyData(r->endpoint, &a, 0, nullptr, size, usage);
    if (status)
        return status;
    status = AudioObjectGetPropertyData(r->endpoint, &a, 0, nullptr, &size, usage);
    if (status)
        return status;
    for (UInt32 i = 0; i < r->physicalInputStreams; i++)
        if (usage->mStreamIsOn[i])
            return kAudioHardwareIllegalOperationError;
    for (UInt32 i = r->physicalInputStreams; i < total; i++)
        if (!usage->mStreamIsOn[i])
            return kAudioHardwareIllegalOperationError;
    r->hardwareInputsDisabled = true;
    return noErr;
}
static void restoreDirect(DEQRoute *r) {
    AudioObjectID physical = findDevice([NSString stringWithUTF8String:r->physicalUID.c_str()]);
    if (!physical)
        return;
    if (defaultDevice() == r->endpoint)
        setDefault(physical);
    if (defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice) == r->endpoint)
        setDefault(physical, kAudioHardwarePropertyDefaultSystemOutputDevice);
}
int DEQRouteStart(DEQRoute *r) {
    if (!r || r->invalid.load()) {
        lastError = @"Route changed; disable and re-enable it to rebuild at the current device format.";
        return 0;
    }
    if (r->started)
        return 1;
    OSStatus st = AudioDeviceStart(r->endpoint, r->proc);
    if (st) {
        lastError = [NSString
            stringWithFormat:@"Audio start failed (%d). Allow DeviceEQ in Screen & System Audio Recording.",
                             (int)st];
        return 0;
    }
    r->started = true;
    return 1;
}
DEQRoute *DEQRouteCreate(const char *uid, const DEQConfig *cfg) {
    auto *r = DEQRoutePrepare(uid, cfg);
    if (r && !DEQRouteStart(r)) {
        DEQRouteDestroy(r);
        return nullptr;
    }
    return r;
}
static DEQRoute *prepareRoute(const char *deviceUID, const DEQConfig *config, bool physicalMode) {
    @autoreleasepool {
        lastError = @"";
        if (!deviceUID || !config) {
            lastError = @"Missing device or EQ configuration.";
            return nullptr;
        }
        auto *r = new DEQRoute;
        r->physicalMode = physicalMode;
        NSString *uid = [NSString stringWithUTF8String:deviceUID];
        r->physical = findDevice(uid);
        if (!r->physical) {
            lastError = @"The physical output is disconnected.";
            delete r;
            return nullptr;
        }
        r->physicalUID = deviceUID;
        if (isVirtualDevice(r->physical)) {
            lastError = @"Select a physical output, not eqMac or another virtual/aggregate endpoint.";
            DEQRouteDestroy(r);
            return nullptr;
        }
        if (channels(r->physical, kAudioObjectPropertyScopeOutput) != 2) {
            lastError = @"This prototype requires a stereo output (exactly two channels).";
            DEQRouteDestroy(r);
            return nullptr;
        }
        r->rate = sampleRate(r->physical);
        r->inputSkip = channels(r->physical, kAudioObjectPropertyScopeInput);
        DEQConfig cfg = *config;
        cfg.sampleRate = r->rate;
        r->dsp = DEQCreate(r->rate);
        if (!DEQSetConfig(r->dsp, &cfg)) {
            lastError = @"Invalid EQ configuration.";
            DEQRouteDestroy(r);
            return nullptr;
        }
        NSString *endpointUID = [@"org.deviceeq.endpoint." stringByAppendingString:uid];
        NSString *captureUID = physicalMode ? uid : endpointUID;
        r->captureUID = captureUID.UTF8String;
        r->leaseFD = acquireLease(endpointUID);
        if (r->leaseFD < 0) {
            lastError = @"Another DeviceEQ process owns this output, or its route lease cannot be opened.";
            DEQRouteDestroy(r);
            return nullptr;
        }
        if (findDevice(endpointUID)) {
            lastError = @"An endpoint with this UID already exists. Quit its owning DeviceEQ instance before "
                        @"enabling this route.";
            DEQRouteDestroy(r);
            return nullptr;
        }
        if (!writeLease(r->leaseFD, endpointUID, uid, @"")) {
            lastError = @"Unable to persist the route ownership lease.";
            DEQRouteDestroy(r);
            return nullptr;
        }
        r->leaseOwnsRecord = true;
        NSDictionary *composition = @{
            @kAudioAggregateDeviceNameKey : [stringProperty(r->physical, kAudioObjectPropertyName)
                stringByAppendingString:@" — DeviceEQ"],
            @kAudioAggregateDeviceUIDKey : endpointUID,
            @kAudioAggregateDeviceSubDeviceListKey : @[
                @{@kAudioSubDeviceUIDKey : uid}
            ],
            @kAudioAggregateDeviceMainSubDeviceKey : uid,
            @kAudioAggregateDeviceIsPrivateKey : @(physicalMode)
        };
        NSString *stage = @"create aggregate";
        OSStatus status =
            AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)composition, &r->endpoint);
        if (status)
            goto fail;
        {
            stage = @"resolve own process";
            pid_t pid = getpid();
            AudioObjectID process = 0;
            UInt32 n = sizeof(process);
            auto a = address(kAudioHardwarePropertyTranslatePIDToProcessObject);
            AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, sizeof(pid), &pid, &n, &process);
            NSArray *exclude = process ? @[ @(process) ] : @[];
            if (!process) {
                status = kAudioHardwareUnspecifiedError;
                goto fail;
            }
            CATapDescription *desc = [[CATapDescription alloc] initExcludingProcesses:exclude
                                                                         andDeviceUID:captureUID
                                                                           withStream:0];
            desc.name = @"DeviceEQ isolated endpoint tap"; /* Public endpoint requires a public tap; HAL
                                                              ignores private tap on public aggregate. */
            [desc setPrivate:physicalMode];
            desc.muteBehavior = CATapMutedWhenTapped;
            stage = @"create scoped process tap";
            status = AudioHardwareCreateProcessTap(desc, &r->tap);
            if (status)
                goto fail;
            AudioStreamBasicDescription fmt{};
            n = sizeof(fmt);
            a = address(kAudioTapPropertyFormat);
            stage = @"read tap format";
            status = AudioObjectGetPropertyData(r->tap, &a, 0, nullptr, &n, &fmt);
            if (status)
                goto fail;
            if (fmt.mFormatID != kAudioFormatLinearPCM || !(fmt.mFormatFlags & kAudioFormatFlagIsFloat) ||
                !(fmt.mFormatFlags & kAudioFormatFlagIsPacked) || fmt.mBitsPerChannel != 32 ||
                fmt.mChannelsPerFrame != 2 || fabs(fmt.mSampleRate - r->rate) > 0.5) {
                lastError = @"This output tap does not expose supported Float32 PCM.";
                DEQRouteDestroy(r);
                return nullptr;
            }
            CFStringRef tuid = nullptr;
            n = sizeof(tuid);
            a = address(kAudioTapPropertyUID);
            status = AudioObjectGetPropertyData(r->tap, &a, 0, nullptr, &n, &tuid);
            if (status)
                goto fail;
            if (!writeLease(r->leaseFD, endpointUID, uid, (__bridge NSString *)tuid)) {
                CFRelease(tuid);
                status = kAudioHardwareUnspecifiedError;
                goto fail;
            }
            CFArrayRef taps =
                CFArrayCreate(kCFAllocatorDefault, (const void **)&tuid, 1, &kCFTypeArrayCallBacks);
            a = address(kAudioAggregateDevicePropertyTapList);
            stage = @"attach scoped tap to endpoint";
            status = AudioObjectSetPropertyData(r->endpoint, &a, 0, nullptr, sizeof(taps), &taps);
            CFRelease(taps);
            CFRelease(tuid);
            if (status)
                goto fail;
        }
        stage = @"validate aggregate formats";
        for (int attempt = 0;
             attempt < 80 && channels(r->endpoint, kAudioObjectPropertyScopeInput) < r->inputSkip + 2;
             attempt++)
            usleep(10000);
        if (channels(r->endpoint, kAudioObjectPropertyScopeInput) != r->inputSkip + 2) {
            status = kAudioDeviceUnsupportedFormatError;
            goto fail;
        }
        status = validateStreams(r->endpoint, kAudioObjectPropertyScopeOutput);
        if (status)
            goto fail;
        status = validateStreams(r->endpoint, kAudioObjectPropertyScopeInput,
                                 streamCount(r->physical, kAudioObjectPropertyScopeInput));
        if (status)
            goto fail;
        stage = @"create IOProc";
        status = AudioDeviceCreateIOProcID(r->endpoint, io, r, &r->proc);
        if (status)
            goto fail;
        stage = @"disable unused physical input streams";
        status = disablePhysicalInputs(r);
        if (status)
            goto fail;
        stage = @"install device listeners";
        status = addListeners(r);
        if (status)
            goto fail;
        return r;
    fail:
        lastError =
            [NSString stringWithFormat:@"Core Audio %@ failed (%d). Check System Settings → Privacy & "
                                       @"Security → Screen & System Audio Recording, and allow DeviceEQ.",
                                       stage, (int)status];
        DEQRouteDestroy(r);
        return nullptr;
    }
}
DEQRoute *DEQRoutePrepare(const char *uid, const DEQConfig *cfg) {
    return prepareRoute(uid, cfg, false);
}
DEQRoute *DEQRoutePreparePhysical(const char *uid, const DEQConfig *cfg) {
    return prepareRoute(uid, cfg, true);
}
DEQRoute *DEQRouteCreatePhysical(const char *uid, const DEQConfig *cfg) {
    auto *r = DEQRoutePreparePhysical(uid, cfg);
    if (r && !DEQRouteStart(r)) {
        DEQRouteDestroy(r);
        return nullptr;
    }
    return r;
}
void DEQRouteDestroy(DEQRoute *r) {
    if (!r)
        return;
    removeListeners(r);
    if (r->endpoint) {
        restoreDirect(r);
        if (r->proc) {
            if (r->started)
                AudioDeviceStop(r->endpoint, r->proc);
            AudioDeviceDestroyIOProcID(r->endpoint, r->proc);
        }
        AudioHardwareDestroyAggregateDevice(r->endpoint);
    }
    if (r->tap)
        AudioHardwareDestroyProcessTap(r->tap);
    if (r->dsp)
        DEQDestroy(r->dsp);
    if (r->leaseFD >= 0) {
        if (r->leaseOwnsRecord)
            ftruncate(r->leaseFD, 0);
        flock(r->leaseFD, LOCK_UN);
        close(r->leaseFD);
    }
    delete r;
}
int DEQRouteUpdate(DEQRoute *r, const DEQConfig *config) {
    if (!r || !config || r->invalid.load())
        return 0;
    DEQConfig c = *config;
    c.sampleRate = r->rate;
    return DEQSetConfig(r->dsp, &c);
}
int DEQRouteSelect(DEQRoute *r) {
    return r && r->started && !r->invalid.load() &&
           setDefault(r->physicalMode ? r->physical : r->endpoint) == noErr;
}
static UInt32 uintProperty(AudioObjectID id, UInt32 property,
                           UInt32 scope = kAudioObjectPropertyScopeGlobal) {
    UInt32 value = 0, size = sizeof(value);
    auto a = address(property, scope);
    AudioObjectGetPropertyData(id, &a, 0, nullptr, &size, &value);
    return value;
}
static int tapMuteBehavior(AudioObjectID tap) {
    __unsafe_unretained CATapDescription *description = nil;
    UInt32 size = sizeof(description);
    auto a = address(kAudioTapPropertyDescription);
    if (AudioObjectGetPropertyData(tap, &a, 0, nullptr, &size, &description) != noErr || !description)
        return -1;
    return (int)description.muteBehavior;
}
char *DEQDefaultOutputUID() {
    return strdup(stringProperty(defaultDevice(), kAudioDevicePropertyDeviceUID).UTF8String);
}
int DEQRestoreOutputUID(const char *uid) {
    if (!uid)
        return 0;
    AudioObjectID d = findDevice([NSString stringWithUTF8String:uid]);
    return d && setDefault(d) == noErr;
}
char *DEQRouteStatsJSON(DEQRoute *r) {
    if (!r)
        return json(@{});
    if (r->invalid.load() && r->started) {
        AudioDeviceStop(r->endpoint, r->proc);
        r->started = false;
        restoreDirect(r);
    }
    return json(@{
        @"physicalInputStreams" : @(r->physicalInputStreams),
        @"hardwareInputsDisabled" : @(r->hardwareInputsDisabled),
        @"tapMuteBehavior" : @(tapMuteBehavior(r->tap)),
        @"inputClippingSamples" : @(r->inputClips.load()),
        @"outputClippingSamples" : @(r->outputClips.load()),
        @"maximumInputPeak" : @(r->maxInputPeak.load()),
        @"maximumOutputPeak" : @(r->maxOutputPeak.load()),
        @"inputRMS" : @(r->inputRMS.load()),
        @"outputRMS" : @(r->outputRMS.load()),
        @"bufferFrames" : @(uintProperty(r->endpoint, kAudioDevicePropertyBufferFrameSize)),
        @"bufferPeriodMs" :
            @(1000.0 * uintProperty(r->endpoint, kAudioDevicePropertyBufferFrameSize) / r->rate),
        @"hardwareLatencyFrames" :
            @(uintProperty(r->physical, kAudioDevicePropertyLatency, kAudioObjectPropertyScopeOutput)),
        @"safetyOffsetFrames" :
            @(uintProperty(r->physical, kAudioDevicePropertySafetyOffset, kAudioObjectPropertyScopeOutput)),
        @"nativePhysicalMode" : @(r->physicalMode),
        @"volumeSupport" : volumeInfo(r->physical),
        @"captureDeviceUID" : [NSString stringWithUTF8String:r->captureUID.c_str()],
        @"inputChannels" : @(channels(r->endpoint, kAudioObjectPropertyScopeInput)),
        @"outputChannels" : @(channels(r->endpoint, kAudioObjectPropertyScopeOutput)),
        @"invalid" : @(r->invalid.load()),
        @"started" : @(r->started),
        @"callbacks" : @(r->callbacks.load()),
        @"frames" : @(r->frames.load()),
        @"oversizeBlocks" : @(r->oversize.load()),
        @"inputPeak" : @(r->inputPeak.load()),
        @"outputPeak" : @(r->outputPeak.load()),
        @"sampleRate" : @(r->rate),
        @"endpoint" : @(r->endpoint),
        @"tap" : @(r->tap),
        @"physical" : @(r->physical),
        @"selected" : @(defaultDevice() == (r->physicalMode ? r->physical : r->endpoint))
    });
}

// Unmuted observational tap. Captures pre-hardware Core Audio data; not an analog loopback.
struct DEQMonitor {
    AudioObjectID tap = 0, aggregate = 0;
    AudioDeviceIOProcID proc = nullptr;
    double rate = 48000, frequency = 997, phase = 0;
    uint64_t count = 0;
    double energy = 0, cosine = 0, sine = 0;
    float peak = 0;
    std::atomic<uint64_t> frames{0};
    std::atomic<double> rms{0}, magnitude{0};
    std::atomic<float> maxPeak{0};
    bool started = false;
};
static OSStatus monitorIO(AudioObjectID, const AudioTimeStamp *, const AudioBufferList *input,
                          const AudioTimeStamp *, AudioBufferList *, const AudioTimeStamp *, void *ctx) {
    auto *m = (DEQMonitor *)ctx;
    if (!input || !input->mNumberBuffers)
        return noErr;
    UInt32 frames =
        input->mBuffers[0].mNumberChannels
            ? input->mBuffers[0].mDataByteSize / (sizeof(float) * input->mBuffers[0].mNumberChannels)
            : 0;
    for (UInt32 f = 0; f < frames; f++) {
        float v = inputSample(input, 0, f);
        m->energy += double(v) * v;
        m->cosine += v * cos(m->phase);
        m->sine += v * sin(m->phase);
        m->peak = std::max(m->peak, fabsf(v));
        m->phase += 2 * M_PI * m->frequency / m->rate;
        if (m->phase > 2 * M_PI)
            m->phase -= 2 * M_PI;
        m->count++;
    }
    m->frames.store(m->count, std::memory_order_relaxed);
    m->rms.store(m->count ? sqrt(m->energy / m->count) : 0, std::memory_order_relaxed);
    m->magnitude.store(m->count ? 2 * hypot(m->cosine, m->sine) / m->count : 0, std::memory_order_relaxed);
    m->maxPeak.store(m->peak, std::memory_order_relaxed);
    return noErr;
}
static DEQMonitor *monitorStart(const char *deviceUID, double frequency, bool ownOnly) {
    @autoreleasepool {
        if (!deviceUID || !std::isfinite(frequency) || frequency < 20 || frequency > 18000)
            return nullptr;
        AudioObjectID device = findDevice([NSString stringWithUTF8String:deviceUID]);
        if (!device)
            return nullptr;
        auto *m = new DEQMonitor;
        m->rate = sampleRate(device);
        m->frequency = frequency;
        CATapDescription *desc = nil;
        if (ownOnly) {
            pid_t pid = getpid();
            AudioObjectID process = 0;
            UInt32 size = sizeof(process);
            auto a = address(kAudioHardwarePropertyTranslatePIDToProcessObject);
            OSStatus translated =
                AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, sizeof(pid), &pid, &size, &process);
            if (translated || !process) {
                lastError = @"Current audio process object unavailable for own-process monitor.";
                delete m;
                return nullptr;
            }
            desc = [[CATapDescription alloc] initWithProcesses:@[ @(process) ]
                                                  andDeviceUID:[NSString stringWithUTF8String:deviceUID]
                                                    withStream:0];
        } else
            desc = [[CATapDescription alloc] initExcludingProcesses:@[]
                                                       andDeviceUID:[NSString stringWithUTF8String:deviceUID]
                                                         withStream:0];
        desc.name = ownOnly ? @"DeviceEQ own-process verification monitor" : @"DeviceEQ verification monitor";
        desc.privateTap = YES;
        desc.muteBehavior = CATapUnmuted;
        OSStatus status = AudioHardwareCreateProcessTap(desc, &m->tap);
        if (status)
            goto fail;
        {
            AudioStreamBasicDescription format{};
            UInt32 size = sizeof(format);
            auto a = address(kAudioTapPropertyFormat);
            status = AudioObjectGetPropertyData(m->tap, &a, 0, nullptr, &size, &format);
            if (status || format.mFormatID != kAudioFormatLinearPCM ||
                !(format.mFormatFlags & kAudioFormatFlagIsFloat) || format.mBitsPerChannel != 32)
                goto fail;
            m->rate = format.mSampleRate;
            CFStringRef tapUID = nullptr;
            size = sizeof(tapUID);
            a = address(kAudioTapPropertyUID);
            status = AudioObjectGetPropertyData(m->tap, &a, 0, nullptr, &size, &tapUID);
            if (status)
                goto fail;
            NSDictionary *composition = @{
                @kAudioAggregateDeviceNameKey : @"DeviceEQ private verification monitor",
                @kAudioAggregateDeviceUIDKey : NSUUID.UUID.UUIDString,
                @kAudioAggregateDeviceIsPrivateKey : @YES,
                @kAudioAggregateDeviceTapListKey : @[ @{
                    @kAudioSubTapUIDKey : (__bridge NSString *)tapUID,
                    @kAudioSubTapDriftCompensationKey : @YES
                } ]
            };
            status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)composition, &m->aggregate);
            CFRelease(tapUID);
            if (status)
                goto fail;
        }
        status = AudioDeviceCreateIOProcID(m->aggregate, monitorIO, m, &m->proc);
        if (status)
            goto fail;
        status = AudioDeviceStart(m->aggregate, m->proc);
        if (status)
            goto fail;
        m->started = true;
        return m;
    fail:
        lastError = [NSString stringWithFormat:@"Verification monitor failed (%d).", (int)status];
        DEQMonitorDestroy(m);
        return nullptr;
    }
}
DEQMonitor *DEQMonitorStart(const char *uid, double frequency) {
    return monitorStart(uid, frequency, false);
}
DEQMonitor *DEQMonitorStartOwnProcess(const char *uid, double frequency) {
    return monitorStart(uid, frequency, true);
}
char *DEQMonitorStatsJSON(DEQMonitor *m) {
    if (!m)
        return json(@{});
    return json(@{
        @"frames" : @(m->frames.load()),
        @"rms" : @(m->rms.load()),
        @"toneMagnitude" : @(m->magnitude.load()),
        @"peak" : @(m->maxPeak.load()),
        @"frequency" : @(m->frequency),
        @"sampleRate" : @(m->rate)
    });
}
void DEQMonitorDestroy(DEQMonitor *m) {
    if (!m)
        return;
    if (m->proc) {
        if (m->started)
            AudioDeviceStop(m->aggregate, m->proc);
        AudioDeviceDestroyIOProcID(m->aggregate, m->proc);
    }
    if (m->aggregate)
        AudioHardwareDestroyAggregateDevice(m->aggregate);
    if (m->tap)
        AudioHardwareDestroyProcessTap(m->tap);
    delete m;
}

static id consumeJSON(char *text) {
    NSData *data = [[NSString stringWithUTF8String:text] dataUsingEncoding:NSUTF8StringEncoding];
    DEQFreeString(text);
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}
char *DEQRoutingVerify(const char *argumentsJSON) {
    @autoreleasepool {
        NSData *data = argumentsJSON ? [[NSString stringWithUTF8String:argumentsJSON]
                                           dataUsingEncoding:NSUTF8StringEncoding]
                                     : nil;
        id args = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSArray *uids = [args isKindOfClass:NSDictionary.class] ? args[@"deviceUIDs"] : nil;
        NSString *helper = [args isKindOfClass:NSDictionary.class] ? args[@"toneHelperPath"] : nil;
        if (![uids isKindOfClass:NSArray.class] || uids.count != 2 ||
            ![uids[0] isKindOfClass:NSString.class] || ![uids[1] isKindOfClass:NSString.class] ||
            ![helper isKindOfClass:NSString.class] ||
            ![[NSFileManager defaultManager] isExecutableFileAtPath:helper])
            return json(@{@"error" : @"Expected two physical deviceUIDs and executable toneHelperPath."});
        AudioObjectID original = defaultDevice();
        NSMutableArray *cases = [NSMutableArray array];
        bool passed = true;
        for (int test = 0; test < 3; test++) {
            DEQRoute *routes[2] = {nullptr, nullptr};
            DEQMonitor *monitors[2] = {nullptr, nullptr};
            for (int i = 0; i < 2; i++) {
                DEQConfig cfg{};
                cfg.sampleRate = 48000;
                cfg.bandCount = 1;
                cfg.bands[0] = {DEQ_PEAK, DEQ_STEREO, 1, 997.0, i == 0 ? -12.0 : -6.0, 1.0};
                routes[i] = DEQRouteCreate([uids[i] UTF8String], &cfg);
                if (!routes[i])
                    break;
            }
            if (!routes[0] || !routes[1]) {
                passed = false;
                [cases addObject:@{@"error" : lastError, @"case" : @(test)}];
                for (auto *r : routes)
                    DEQRouteDestroy(r);
                break;
            }
            for (int i = 0; i < 2; i++)
                monitors[i] = DEQMonitorStart([uids[i] UTF8String], 997);
            NSString *destination =
                test < 2 ? stringProperty(routes[test]->endpoint, kAudioDevicePropertyDeviceUID) : uids[0];
            NSTask *task = [NSTask new];
            task.executableURL = [NSURL fileURLWithPath:helper];
            task.arguments = @[ destination, @"997", @"1", @".001" ];
            task.standardOutput = [NSPipe pipe];
            task.standardError = [NSPipe pipe];
            NSError *error = nil;
            bool launched = [task launchAndReturnError:&error];
            if (launched)
                [task waitUntilExit];
            usleep(150000);
            NSMutableArray *stats = [NSMutableArray array], *monitorStats = [NSMutableArray array];
            for (int i = 0; i < 2; i++) {
                [stats addObject:consumeJSON(DEQRouteStatsJSON(routes[i]))];
                [monitorStats addObject:consumeJSON(DEQMonitorStatsJSON(monitors[i]))];
            }
            bool casePassed = launched && task.terminationStatus == 0;
            double ratio = 0;
            if (test < 2) {
                NSDictionary *active = stats[test], *other = stats[1 - test];
                double inRMS = [active[@"inputRMS"] doubleValue], outRMS = [active[@"outputRMS"] doubleValue];
                ratio = inRMS > 0 ? outRMS / inRMS : 0;
                double expected = pow(10.0, (test == 0 ? -12.0 : -6.0) / 20.0);
                casePassed =
                    casePassed && inRMS > 1e-6 && fabs(20 * log10(std::max(ratio, 1e-30) / expected)) < .5 &&
                    [other[@"maximumInputPeak"] doubleValue] < 1e-7 && ![active[@"invalid"] boolValue] &&
                    [active[@"outputClippingSamples"] unsignedLongLongValue] == 0;
            } else
                for (NSDictionary *s in stats)
                    casePassed = casePassed && [s[@"maximumInputPeak"] doubleValue] < 1e-7;
            [cases addObject:@{
                @"case" : test == 0 ? @"endpoint A"
                : test == 1         ? @"endpoint B"
                                    : @"direct physical A",
                @"destinationUID" : destination,
                @"pass" : @(casePassed),
                @"outputInputRMSRatio" : @(ratio),
                @"routes" : stats,
                @"physicalDigitalMonitors" : monitorStats,
                @"producerExit" : @(launched ? task.terminationStatus : -1),
                @"producerError" : error.localizedDescription ?: @""
            }];
            passed = passed && casePassed;
            for (auto *m : monitors)
                DEQMonitorDestroy(m);
            for (auto *r : routes)
                DEQRouteDestroy(r);
        }
        bool unchanged = defaultDevice() == original;
        return json(@{
            @"pass" : @(passed && unchanged),
            @"defaultOutputUnchanged" : @(unchanged),
            @"cases" : cases,
            @"limitation" : @"Digital Core Audio monitors observe process audio before hardware. They do not "
                            @"independently prove analog raw-signal suppression, acoustic playback, or "
                            @"end-to-end latency."
        });
    }
}

static NSDictionary *captureOwnTone(NSString *physical, NSString *helper, bool own) {
    DEQMonitor *m =
        own ? DEQMonitorStartOwnProcess(physical.UTF8String, 997) : DEQMonitorStart(physical.UTF8String, 997);
    if (!m)
        return @{@"error" : lastError};
    usleep(100000);
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:helper];
    task.arguments = @[ physical, @"997", @"1", @".001" ];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    NSError *error = nil;
    bool launched = [task launchAndReturnError:&error];
    if (launched)
        [task waitUntilExit];
    usleep(100000);
    NSMutableDictionary *stats = [consumeJSON(DEQMonitorStatsJSON(m)) mutableCopy];
    stats[@"producerExit"] = @(launched ? task.terminationStatus : -1);
    stats[@"producerError"] = error.localizedDescription ?: @"";
    DEQMonitorDestroy(m);
    return stats;
}
char *DEQPhysicalRoutingVerify(const char *argumentsJSON) {
    @autoreleasepool {
        NSData *d = argumentsJSON ? [[NSString stringWithUTF8String:argumentsJSON]
                                        dataUsingEncoding:NSUTF8StringEncoding]
                                  : nil;
        id args = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        NSString *uid = [args isKindOfClass:NSDictionary.class] ? args[@"deviceUID"] : nil;
        NSString *helper = [args isKindOfClass:NSDictionary.class] ? args[@"toneHelperPath"] : nil;
        if (![uid isKindOfClass:NSString.class] || ![helper isKindOfClass:NSString.class] ||
            ![[NSFileManager defaultManager] isExecutableFileAtPath:helper])
            return json(@{@"error" : @"Expected physical deviceUID and executable toneHelperPath."});
        char *defaultUID = DEQDefaultOutputUID();
        NSDictionary *originalVolume = consumeJSON(DEQDeviceVolumeJSON(uid.UTF8String));
        NSMutableDictionary *report = [@{
            @"deviceUID" : uid,
            @"beforeDefaultUID" : [NSString stringWithUTF8String:defaultUID],
            @"originalVolume" : originalVolume,
            @"baseline" : captureOwnTone(uid, helper, false)
        } mutableCopy];
        DEQConfig cfg{};
        cfg.sampleRate = 48000;
        cfg.preampDB = -12;
        DEQRoute *r = DEQRouteCreatePhysical(uid.UTF8String, &cfg);
        if (!r) {
            report[@"error"] = lastError;
            DEQFreeString(defaultUID);
            return json(report);
        }
        bool selected = DEQRouteSelect(r);
        report[@"physicalSelected"] = @(selected);
        report[@"wet"] = captureOwnTone(uid, helper, true);
        report[@"wetRouteStats"] = consumeJSON(DEQRouteStatsJSON(r));
        bool volumeSet = false, volumeRestored = true;
        if ([originalVolume[@"supportsVolume"] boolValue]) {
            float original = [originalVolume[@"volume"] floatValue];
            float lower = std::min(original, .25f);
            volumeSet = DEQDeviceSetVolume(uid.UTF8String, lower);
            report[@"lowerVolumeSetAccepted"] = @(volumeSet);
            report[@"lowerVolumeReadback"] = consumeJSON(DEQDeviceVolumeJSON(uid.UTF8String));
            if (volumeSet) {
                report[@"wetAtLowerVolume"] = captureOwnTone(uid, helper, true);
                report[@"lowerVolumeRouteStats"] = consumeJSON(DEQRouteStatsJSON(r));
                volumeRestored = DEQDeviceSetVolume(uid.UTF8String, original) != 0;
            }
        }
        report[@"volumeRestored"] = @(volumeRestored);
        cfg.bypass = 1;
        report[@"bypassUpdateAccepted"] = @(DEQRouteUpdate(r, &cfg));
        usleep(100000);
        report[@"bypass"] = captureOwnTone(uid, helper, true);
        cfg.bypass = 0;
        cfg.preampDB = -18;
        report[@"profileUpdateAccepted"] = @(DEQRouteUpdate(r, &cfg));
        usleep(100000);
        report[@"updated"] = captureOwnTone(uid, helper, true);
        report[@"finalRouteStats"] = consumeJSON(DEQRouteStatsJSON(r));
        DEQRouteDestroy(r);
        report[@"defaultRestored"] = @(DEQRestoreOutputUID(defaultUID));
        DEQFreeString(defaultUID);
        report[@"finalVolume"] = consumeJSON(DEQDeviceVolumeJSON(uid.UTF8String));
        report[@"afterDevices"] = consumeJSON(DEQDevicesJSON());
        bool pass = selected && volumeRestored && [report[@"defaultRestored"] boolValue];
        for (NSString *key in @[ @"wet", @"bypass", @"updated" ]) {
            NSDictionary *stats = report[key];
            double peak = [stats[@"peak"] doubleValue],
                   expected = [key isEqualToString:@"wet"]       ? pow(10, -12.0 / 20)
                              : [key isEqualToString:@"updated"] ? pow(10, -18.0 / 20)
                                                                 : 1;
            double gain = 20 * log10(std::max(peak, 1e-30) / .001);
            pass = pass && [stats[@"producerExit"] intValue] == 0 && fabs(gain - 20 * log10(expected)) < .5;
            report[[key stringByAppendingString:@"MeasuredGainDB"]] = @(gain);
        }
        if (volumeSet) {
            NSDictionary *low = report[@"wetAtLowerVolume"];
            double peak = [low[@"peak"] doubleValue];
            pass = pass && [low[@"producerExit"] intValue] == 0 &&
                   fabs(20 * log10(std::max(peak, 1e-30) / .001) + 12) < .5;
        }
        report[@"pass"] = @(pass);
        report[@"measurementScope"] = @"Own-process digital submission at physical device. Native volume "
                                      @"gain is intentionally not duplicated in DSP. Acoustic/hardware "
                                      @"suppression and AirPods behavior require independent tests.";
        return json(report);
    }
}
