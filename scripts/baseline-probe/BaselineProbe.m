// Test-only observation probe for scripts/record-baselines.py. Never shipped.
//
// The baseline script injects this library into one owned simulator with
// DYLD_INSERT_LIBRARIES and names the app in GAMECORE_BASELINE_PROBE_BUNDLE.
// Every other process returns at once. In the named app it logs, to the
// unified log under subsystem "gamecore.baseline-probe":
//
//   launch  - wall time from process start (kern.proc p_starttime) to the
//             first display-link frame after UIApplicationDidBecomeActive,
//             plus phys_footprint at that frame.
//   update  - intervals between successive -[SKScene update:] calls, the
//             per-frame scene update SpriteKit makes while a scene is shown
//             and unpaused. Gaps of one second or more are reported apart.
//   memory  - phys_footprint and its lifetime peak every half second.
//
// It links only Foundation and reaches UIKit, QuartzCore and SpriteKit
// through the Objective-C runtime, so it loads harmlessly into daemons.
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <unistd.h>

@protocol GCProbeDisplayLink <NSObject>
+ (id)displayLinkWithTarget:(id)target selector:(SEL)selector;
- (void)addToRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode;
- (void)invalidate;
@end

static os_log_t probeLog;
static double timebaseToSeconds;
static double lastUpdate = -1;
static double lastSceneTime = -1;
static NSMutableString *pendingIntervals;
static NSMutableString *pendingGaps;
static unsigned long pendingCount;
static unsigned long flushSequence;
static BOOL launchReported;

static double now(void) { return (double)mach_absolute_time() * timebaseToSeconds; }

static double wallNow(void) {
    struct timeval value;
    gettimeofday(&value, NULL);
    return (double)value.tv_sec + (double)value.tv_usec / 1e6;
}

static double processStart(void) {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int name[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    if (sysctl(name, 4, &info, &size, NULL, 0) != 0 || size == 0) return -1;
    return (double)info.kp_proc.p_starttime.tv_sec + (double)info.kp_proc.p_starttime.tv_usec / 1e6;
}

static void footprint(uint64_t *current, int64_t *peak) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    *current = 0;
    *peak = -1;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return;
    if (count >= TASK_VM_INFO_REV1_COUNT) {
        *current = info.phys_footprint;
        *peak = info.ledger_phys_footprint_peak;
    }
}

static void flush(void) {
    uint64_t current; int64_t peak;
    footprint(&current, &peak);
    os_log(probeLog, "memory footprintBytes=%llu peakBytes=%lld", current, peak);
    if (pendingCount == 0 && pendingGaps.length == 0) return;
    os_log(probeLog, "update seq=%lu ms=%{public}@ gapsMs=%{public}@", ++flushSequence, pendingIntervals, pendingGaps);
    [pendingIntervals setString:@""];
    [pendingGaps setString:@""];
    pendingCount = 0;
}

static void recordUpdate(NSTimeInterval sceneTime) {
    // A subclass that calls super reaches both hooks in one frame; the scene
    // time identifies the frame.
    if (sceneTime == lastSceneTime) return;
    lastSceneTime = sceneTime;
    double time = now();
    if (lastUpdate >= 0) {
        double interval = (time - lastUpdate) * 1000.0;
        NSMutableString *target = interval >= 1000.0 ? pendingGaps : pendingIntervals;
        if (target.length) [target appendString:@","];
        [target appendFormat:@"%.2f", interval];
        if (interval < 1000.0 && ++pendingCount >= 60) flush();
    }
    lastUpdate = time;
}

static void hookSceneUpdates(void) {
    Class base = NSClassFromString(@"SKScene");
    if (!base) {
        os_log(probeLog, "update unavailable reason=%{public}s", "SpriteKit is not loaded");
        return;
    }
    SEL selector = NSSelectorFromString(@"update:");
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    unsigned int hooked = 0;
    for (unsigned int index = 0; index < count; index++) {
        Class candidate = classes[index];
        BOOL isScene = NO;
        for (Class walk = candidate; walk; walk = class_getSuperclass(walk)) {
            if (walk == base) { isScene = YES; break; }
        }
        if (!isScene) continue;
        // Only classes with their own implementation; inherited ones are reached through it.
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(candidate, &methodCount);
        for (unsigned int item = 0; item < methodCount; item++) {
            if (method_getName(methods[item]) != selector) continue;
            Method method = methods[item];
            IMP original = method_getImplementation(method);
            IMP replacement = imp_implementationWithBlock(^(id scene, NSTimeInterval sceneTime) {
                recordUpdate(sceneTime);
                ((void (*)(id, SEL, NSTimeInterval))original)(scene, selector, sceneTime);
            });
            method_setImplementation(method, replacement);
            hooked++;
        }
        free(methods);
    }
    free(classes);
    os_log(probeLog, "update hooked classes=%u", hooked);
}

@interface GCBaselineProbe : NSObject
@property(nonatomic, strong) id link;
@property(nonatomic) double activeAt;
@end

@implementation GCBaselineProbe
- (void)becameActive:(NSNotification *)notification {
    if (launchReported || self.link) return;
    self.activeAt = wallNow();
    Class linkClass = NSClassFromString(@"CADisplayLink");
    self.link = [(id<GCProbeDisplayLink>)linkClass displayLinkWithTarget:self selector:@selector(firstFrame:)];
    [(id<GCProbeDisplayLink>)self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)firstFrame:(id)link {
    [(id<GCProbeDisplayLink>)link invalidate];
    self.link = nil;
    launchReported = YES;
    double start = processStart();
    double frame = wallNow();
    uint64_t current; int64_t peak;
    footprint(&current, &peak);
    os_log(probeLog, "launch pid=%d processStart=%.6f activeMs=%.2f firstFrameMs=%.2f footprintBytes=%llu peakBytes=%lld",
           getpid(), start, (self.activeAt - start) * 1000.0, (frame - start) * 1000.0, current, peak);
    // Hook after the launch measurement so the class walk does not count in it.
    hookSceneUpdates();
}

- (void)flushNow:(NSNotification *)notification { flush(); }
@end

static GCBaselineProbe *probe;
static dispatch_source_t probeTimer;

__attribute__((constructor)) static void startProbe(void) {
    const char *target = getenv("GAMECORE_BASELINE_PROBE_BUNDLE");
    NSString *bundle = [[NSBundle mainBundle] bundleIdentifier];
    if (!target || !bundle || strcmp(target, bundle.UTF8String) != 0) return;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    timebaseToSeconds = (double)timebase.numer / (double)timebase.denom / 1e9;
    probeLog = os_log_create("gamecore.baseline-probe", "probe");
    pendingIntervals = [NSMutableString string];
    pendingGaps = [NSMutableString string];
    probe = [GCBaselineProbe new];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:probe selector:@selector(becameActive:) name:@"UIApplicationDidBecomeActiveNotification" object:nil];
    for (NSString *name in @[@"UIApplicationWillResignActiveNotification", @"UIApplicationDidEnterBackgroundNotification",
                             @"UIApplicationWillTerminateNotification"]) {
        [center addObserver:probe selector:@selector(flushNow:) name:name object:nil];
    }
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), 500 * NSEC_PER_MSEC,
                              50 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{ flush(); });
    dispatch_resume(timer);
    probeTimer = timer;
    os_log(probeLog, "loaded pid=%d bundle=%{public}@", getpid(), bundle);
}
