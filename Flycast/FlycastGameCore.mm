/*
 Copyright (c) 2013, OpenEmu Team
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of the OpenEmu Team nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "FlycastGameCore.h"
#import <OpenEmuBase/OERingBuffer.h>

#include "audiobackend_openemu.h"
#include "OEFCBridging.h"

#include "types.h"
#include "emulator.h"
#include "stdclass.h"
#include "cheats.h"
#include "cfg/cfg.h"
#include "hw/mem/addrspace.h"
#include "hw/maple/maple_cfg.h"
#include "hw/maple/maple_devs.h"
#include "hw/pvr/Renderer_if.h"
#include "hw/pvr/pvr_mem.h"
#include "hw/pvr/ta_ctx.h"
#include "oslib/oslib.h"
#include "audio/audiostream.h"
#include "ui/gui.h"
#include "rend/TexCache.h"
#include <sys/stat.h>
#include "wsi/context.h"

#include <OpenGL/gl3.h>
#include <dlfcn.h>
#include <functional>
#include <chrono>
#include <cstdio>
#include <os/log.h>
#include <sys/sysctl.h>

#define SAMPLERATE 44100
#define SIZESOUNDBUFFER 44100 / 60 * 4
#define DC_PLATFORM DC_PLATFORM_DREAMCAST
#define DC_Contollers 4

#if 1    /* was set to #if 1 by ./configure */
#  define Z_HAVE_UNISTD_H
#endif

#if 1    /* was set to #if 1 by ./configure */
#  define Z_HAVE_STDARG_H
#endif

typedef std::function<void(bool status, const std::string &message, void *cbUserData)> Callback;

@interface FlycastGameCore () <OEDCSystemResponderClient>
{
    uint16_t *_soundBuffer;
    int videoWidth, videoHeight;
    NSString *romPath;
    NSString *romFile;
    NSString *autoLoadStatefileName;
}
@end

__weak FlycastGameCore *_current;

@implementation FlycastGameCore

- (id)init
{
    self = [super init];
    
    if(self)
    {
        videoHeight = 480;
        videoWidth = 640;
        _soundBuffer = (uint16_t *)malloc(SIZESOUNDBUFFER * sizeof(uint16_t));
        memset(_soundBuffer, 0, SIZESOUNDBUFFER * sizeof(uint16_t));
    }
    
    _current = self;
    return self;
}

- (void)dealloc
{
    free(_soundBuffer);
}

static bool system_init;

# pragma mark - Reicast Execution functions

extern void common_linux_setup();

int darw_printf(const char* text,...) {
    va_list args;
    
    char temp[2048];
    va_start(args, text);
    vsprintf(temp, text, args);
    va_end(args);
    
    NSLog(@"%s", temp);
    
    return 0;
}

static void flycast_log(const char *format, ...)
{
    char message[2048];
    va_list args;
    va_start(args, format);
    vsnprintf(message, sizeof(message), format, args);
    va_end(args);

    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "Flycast: %{public}s", message);

    fputs("Flycast: ", stderr);
    fputs(message, stderr);
    fputc('\n', stderr);
    fflush(stderr);
}

static void flycast_log_effective_runtime_config(void)
{
    flycast_log(
        "effective hostCpu=%d featShrec=%d featArec=%d featDsprec=%d backend=%s dynarec=%d threaded=%d renderer=%d resolution=%d emulateFb=%d delaySwap=%d vsync=%d autoSkip=%d maxThreads=%d renderToTextureBuffer=%d",
        HOST_CPU,
        FEAT_SHREC,
        FEAT_AREC,
        FEAT_DSPREC,
        config::AudioBackend.get().c_str(),
        (int)config::DynarecEnabled.get(),
        (int)config::ThreadedRendering.get(),
        (int)config::RendererType.get(),
        config::RenderResolution.get(),
        (int)config::EmulateFramebuffer.get(),
        (int)config::DelayFrameSwapping.get(),
        (int)config::VSync.get(),
        config::AutoSkipFrame.get(),
        config::MaxThreads.get(),
        (int)config::RenderToTextureBuffer.get());
}

// Returns true when the process is running as an x86_64 binary translated by
// Rosetta 2 on Apple Silicon. In that mode Flycast's SH4 JIT emits fresh
// x86_64 code that Rosetta 2 has never seen, causing severe double-JIT
// warm-up overhead (~27 s to first frame). The interpreter is a better choice.
static bool isRunningUnderRosetta(void)
{
    int translated = 0;
    size_t size = sizeof(translated);
    if (sysctlbyname("sysctl.proc_translated", &translated, &size, NULL, 0) == -1)
        return false;
    return translated != 0;
}

volatile bool has_init = false;
static bool startupTimingActive = false;
static std::chrono::steady_clock::time_point startupT0;
static std::chrono::steady_clock::time_point presentedFramesT0;
static unsigned presentedFrameCount = 0;
static unsigned noPresentStreak = 0;
static unsigned noPresentMaxStreak = 0;

// Glad GL function pointer loader using the system OpenGL framework.
// Must be called while an OpenGL context is current.
typedef void* (*GLADloadfunc)(const char* name);
extern "C" int gladLoadGL(GLADloadfunc load);

static void* flycast_gl_get_proc(const char* name) {
    static void* handle = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_LAZY);
    return handle ? dlsym(handle, name) : NULL;
}

# pragma mark - Reicast thread
- (void)emu_init
{
    common_linux_setup();
    
    // The audio backend self-registers via its constructor in audiobackend_openemu.mm
    
    // Set battery save dir
    NSURL *SavesDirectory = [NSURL fileURLWithPath:[self batterySavesDirectoryPath]];
    
    //create the save direcory for the game
    [[NSFileManager defaultManager] createDirectoryAtURL:[SavesDirectory URLByAppendingPathComponent:romFile] withIntermediateDirectories:YES attributes:nil error:nil];
    
    // create the data directory
    [[NSFileManager defaultManager] createDirectoryAtPath:[[self supportDirectoryPath] stringByAppendingPathComponent:@"data"] withIntermediateDirectories:YES attributes:nil error:nil];
    
    //setup the user and system directories
    set_user_config_dir([[self supportDirectoryPath] fileSystemRepresentation]);
    set_user_data_dir([SavesDirectory URLByAppendingPathComponent:romFile].fileSystemRepresentation);
    add_system_data_dir([[self supportDirectoryPath] fileSystemRepresentation]);
    
    //Setup the bios directory
    add_system_data_dir([self biosDirectoryPath].fileSystemRepresentation);
    
    // Initialize flycast core first (calls gui_init() which creates ImGui context)
    char* argv[] = { (char*)"reicast" };
    reicast_init(1, argv);

    // Force OpenEmu host pacing by selecting the OpenEmu audio backend.
    // NOTE: ThreadedRendering must stay TRUE. executeFrame() acts as the render
    // thread: it calls rend_single_frame() which blocks on the PVR Present queue
    // that the emu thread fills. With threaded=false those messages are executed
    // synchronously on the emu thread, leaving the queue empty when
    // rend_single_frame() runs, so it would time out on every call.
    const bool underRosetta = isRunningUnderRosetta();
    // Interpreter mode under Rosetta significantly reduces runtime speed in
    // gameplay-heavy scenes, which causes audio crackle/chop from under-run.
    // Keep dynarec enabled for stable full-speed runtime.
    const bool useDynarec = true;
    config::AudioBackend.override("openemu");
    config::DynarecEnabled.override(useDynarec);
    config::AutoSkipFrame.override(1);
    config::AudioBufferSize.override(12288);
    flycast_log("config backend=%s dynarec=%d threaded=%d audioBuffer=%d underRosetta=%d",
                config::AudioBackend.get().c_str(),
                (int)config::DynarecEnabled.get(),
                (int)config::ThreadedRendering.get(),
                config::AudioBufferSize.get(),
                underRosetta ? 1 : 0);
    
    // Initialize glad GL function pointers using the system OpenGL framework.
    // This must happen while an OpenGL context is current (executeFrame guarantees this).
    static bool glad_initialized = false;
    if (!glad_initialized) {
        int glad_result = gladLoadGL(flycast_gl_get_proc);
        flycast_log("gladLoadGL result=%d", glad_result);
        glad_initialized = (glad_result != 0);
    }

    // Initialize the GL graphics context (requires ImGui context to exist,
    // sets GraphicsContext::instance and fills theGLContext with GL version info)
    try {
        initRenderApi();
        // Initialize core renderer (requires initRenderApi() to have been called)
        rend_init_renderer();
        has_init = true;
    } catch (const std::exception& e) {
        flycast_log("graphics init failed on first attempt: %s (will retry)", e.what());
    } catch (...) {
        flycast_log("graphics init failed with unknown exception (will retry)");
    }
}

# pragma mark - Execution

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    romFile = [[path lastPathComponent] stringByDeletingPathExtension];
    romPath = path;
    
    return YES;
}

- (void)setupEmulation
{
    settings.display.width = videoWidth;
    settings.display.height = videoHeight;
}

- (void)stopEmulation
{
    NSLog(@"Stopping Emulation Core");

    if (has_init) {
        try {
            dc_exit();   // stops DC CPU thread (waits for it to finish)
        } catch (...) {}
        rend_term_renderer(); // clean up GL resources while context is still current
        has_init = false;
        system_init = false;  // allow re-init if core is reused
    }

    [super stopEmulation];
}

- (void)resetEmulation
{
    dc_request_reset();
}

- (void)executeFrame
{
    if (!system_init && !has_init)
    {
        startupT0 = std::chrono::steady_clock::now();
        startupTimingActive = true;

        //Set the game to the virtual drive
        
        //start the reicast core
        [self emu_init];

        if (startupTimingActive) {
            auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startupT0).count();
            flycast_log("startup emu_init=%lld ms", (long long)ms);
        }

        if (!has_init) {
            flycast_log("emu_init failed, skipping dc_start_game");
            return;
        }
        
        gui_state = GuiState::Closed;
        
        try {
            dc_start_game([romPath fileSystemRepresentation]);
        } catch (const std::exception& e) {
            flycast_log("dc_start_game failed: %s", e.what());
            has_init = false;
            return;
        } catch (...) {
            flycast_log("dc_start_game failed with unknown exception");
            has_init = false;
            return;
        }

        if (startupTimingActive) {
            auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startupT0).count();
            flycast_log("startup dc_start_game=%lld ms", (long long)ms);
        }

        // dc_start_game calls Settings::load() which calls Option::set() directly,
        // bypassing the overridden flag and resetting all our overrides. Re-apply
        // every critical override here so they actually take effect at runtime.
        config::AudioBackend.override("openemu");
        config::DynarecEnabled.override(true);
        config::AutoSkipFrame.override(1);
        config::AudioBufferSize.override(12288);
        flycast_log_effective_runtime_config();
        
        dc_resume();
    }
    
    //System is initialized - render the frames
    if (!has_init)
        return;
    
    bool rsf = rend_single_frame(true);
    
    if (rsf)
    {
        if (noPresentStreak > noPresentMaxStreak)
            noPresentMaxStreak = noPresentStreak;
        noPresentStreak = 0;

        if (!system_init){
            system_init = true;
            settings.display.height = videoHeight;
            settings.display.width = videoWidth;
            if (startupTimingActive) {
                auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startupT0).count();
                flycast_log("startup first_frame=%lld ms", (long long)ms);
                startupTimingActive = false;
            }
            presentedFramesT0 = std::chrono::steady_clock::now();
            presentedFrameCount = 0;
        }

        presentedFrameCount++;
        if (presentedFrameCount % 300 == 0) {
            auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - presentedFramesT0).count();
            double fps = elapsedMs > 0 ? (presentedFrameCount * 1000.0) / (double)elapsedMs : 0.0;
            flycast_log("runtime presentedFrames=%u elapsedMs=%lld fps=%.2f",
                        presentedFrameCount,
                        (long long)elapsedMs,
                        fps);
            if (noPresentMaxStreak > 0) {
                flycast_log("runtime no_present_max_streak=%u", noPresentMaxStreak);
                noPresentMaxStreak = 0;
            }
        }
        
        if ([self needsDoubleBufferedFBO])
           [self.renderDelegate presentDoubleBufferedFBO];
        else
           [self.renderDelegate presentationFramebuffer];
                   
        calcFPS();
    }
    else
    {
        noPresentStreak++;
    }
}

# pragma mark - Video
void os_SetWindowText(const char * text) {
    puts(text);
}

void os_DoEvents() {
}

void os_CreateWindow() {
}

void* libPvr_GetRenderTarget() {
    return 0;
}

void* libPvr_GetRenderSurface() {
    return 0;
}

bool gl_init(void*, void*) {
    return true;
}

void gl_term() {}

double emuFrameInterval = 59.94;

void calcFPS(){
    const int spg_clks[4] = { 26944080, 13458568, 13462800, 26944080 };
    u32 pixel_clock = spg_clks[(SPG_CONTROL.full >> 6) & 3];
    
    switch (pixel_clock)
    {
        case 26944080:
            emuFrameInterval = 60.00;
            //info->timing.fps = 60.00; /* (VGA  480 @ 60.00) */
            break;
        case 26917135:
            emuFrameInterval = 59.94;
            //info->timing.fps = 59.94; /* (NTSC 480 @ 59.94) */
            break;
        case 13462800:
            emuFrameInterval = 50.00;
            // info->timing.fps = 50.00; /* (PAL 240  @ 50.00) */
            break;
        case 13458568:
            emuFrameInterval = 59.94;
            // info->timing.fps = 59.94; /* (NTSC 240 @ 59.94) */
            break;
        case 25925600:
            emuFrameInterval = 50.00;
            //info->timing.fps = 50.00; /* (PAL 480  @ 50.00) */
            break;
    }
}

- (OEGameCoreRendering)gameCoreRendering
{
    return OEGameCoreRenderingOpenGL3Video;
}

- (BOOL)needsDoubleBufferedFBO
{
    return YES;
}

- (OEIntSize)bufferSize
{
    return OEIntSizeMake(videoWidth, videoHeight);
}

- (OEIntSize)aspectSize
{
    return OEIntSizeMake(4, 3);
}

- (NSTimeInterval)frameInterval
{
    return emuFrameInterval;
}

# pragma mark - Audio

- (NSUInteger)channelCount
{
    return 2;
}

- (double)audioSampleRate
{
    return SAMPLERATE;
}

# pragma mark - Save States
- (void)autoloadWaitThread:(id)unused
{
    @autoreleasepool
    {
        //Wait here until we get the signal for full initialization
        while (!system_init)
            usleep (10000);
        
        dc_SetStateName(autoLoadStatefileName.fileSystemRepresentation);
        dc_loadstate(0);
        
        dc_resume();
    }
}

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    if (has_init) {
        dc_SetStateName(fileName.fileSystemRepresentation);
        dc_savestate(0);
        
        dc_resume();

        block(true, nil);
    } else {
        block(false, [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotSaveStateError userInfo:nil]);
    }
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    if (!has_init) {
        //Start a separate thread to load
        autoLoadStatefileName = fileName;
        [NSThread detachNewThreadSelector:@selector(autoloadWaitThread:) toTarget:self withObject:nil];
    } else {
        dc_SetStateName(fileName.fileSystemRepresentation);
        dc_loadstate(0);
        dc_resume();
    }
    block(true, nil);
}

# pragma mark - Input

void os_SetupInput()
{
    // Create contollers, but only put vmu on the first controller
#if DC_PLATFORM == DC_PLATFORM_DREAMCAST
   for (int i = 0; i < DC_Contollers; i++)
    {
        config::MapleMainDevices[i] = MDT_SegaController;
        config::MapleExpansionDevices[i][0] = i == 0 ? MDT_SegaVMU : MDT_None;
        config::MapleExpansionDevices[i][1] = i == 0 ? MDT_SegaVMU : MDT_None;
    }
    
    mcfg_CreateDevices();
#endif
}

void UpdateInputState() {}

void UpdateVibration(u32 port, u32 value) {}

int get_mic_data(u8* buffer) { return 0; }
int push_vmu_screen(u8* buffer) { return 0; }

extern u16 kcode[4] ; //= { 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF };
extern s8 joyx[4],joyy[4];
extern u8 rt[4],lt[4];

enum DCPad
{
    Btn_C		= 1,
    Btn_B		= 1<<1,
    Btn_A		= 1<<2,
    Btn_Start	= 1<<3,
    DPad_Up		= 1<<4,
    DPad_Down	= 1<<5,
    DPad_Left	= 1<<6,
    DPad_Right	= 1<<7,
    Btn_Z		= 1<<8,
    Btn_Y		= 1<<9,
    Btn_X		= 1<<10,
    Btn_D		= 1<<11,
    DPad2_Up	= 1<<12,
    DPad2_Down	= 1<<13,
    DPad2_Left	= 1<<14,
    DPad2_Right	= 1<<15,
    
    Axis_LT= 0x10000,
    Axis_RT= 0x10001,
    Axis_X= 0x20000,
    Axis_Y= 0x20001,
};

void handle_key(int dckey, int state, int player)
{
    if (state)
        kcode[player] &= ~dckey;
    else
        kcode[player] |= dckey;
}

- (oneway void)didMoveDCJoystickDirection:(OEDCButton)button withValue:(CGFloat)value forPlayer:(NSUInteger)player
{
    if (player > DC_Contollers) return;
    
    player -= 1;
    
    switch (button)
    {
        case OEDCAnalogUp:
            joyy[player] = value * INT8_MIN;
            break;
        case OEDCAnalogDown:
            joyy[player] = value * INT8_MAX;
            break;
        case OEDCAnalogLeft:
            joyx[player] = value * INT8_MIN;
            break;
        case OEDCAnalogRight:
            joyx[player] = value * INT8_MAX;
            break;
        case OEDCAnalogL:
            lt[player] = value ? 255 : 0;
            break;
        case OEDCAnalogR:
            rt[player] = value ? 255 : 0;
            break;
        default:
            break;
    }
}

-(oneway void)didPushDCButton:(OEDCButton)button forPlayer:(NSUInteger)player
{
    if (player > DC_Contollers) return;
    
    player -= 1;
    
    switch (button) {
        case OEDCButtonUp:
            handle_key(DPad_Up, 1, (int)player);
            break;
        case OEDCButtonDown:
            handle_key(DPad_Down, 1, (int)player);
            break;
        case OEDCButtonLeft:
            handle_key(DPad_Left, 1, (int)player);
            break;
        case OEDCButtonRight:
            handle_key(DPad_Right, 1, (int)player);
            break;
        case OEDCButtonA:
            handle_key(Btn_A, 1, (int)player);
            break;
        case OEDCButtonB:
            handle_key(Btn_B, 1, (int)player);
            break;
        case OEDCButtonX:
            handle_key(Btn_X, 1, (int)player);
            break;
        case OEDCButtonY:
            handle_key(Btn_Y, 1, (int)player);
            break;
        case OEDCButtonStart:
            handle_key(Btn_Start, 1, (int)player);
            break;
        default:
            break;
    }
}

- (oneway void)didReleaseDCButton:(OEDCButton)button forPlayer:(NSUInteger)player
{
    if (player > DC_Contollers) return;
    
    player -= 1;
    
    // FIXME: Dpad up/down seems to get set and released on the same frame, making it not do anything.
    // Need to ensure actions last across a frame?
    switch (button) {
        case OEDCButtonUp:
            handle_key(DPad_Up, 0, (int)player);
            break;
        case OEDCButtonDown:
            handle_key(DPad_Down, 0, (int)player);
            break;
        case OEDCButtonLeft:
            handle_key(DPad_Left, 0, (int)player);
            break;
        case OEDCButtonRight:
            handle_key(DPad_Right, 0, (int)player);
            break;
        case OEDCButtonA:
            handle_key(Btn_A, 0, (int)player);
            break;
        case OEDCButtonB:
            handle_key(Btn_B, 0, (int)player);
            break;
        case OEDCButtonX:
            handle_key(Btn_X, 0, (int)player);
            break;
        case OEDCButtonY:
            handle_key(Btn_Y, 0, (int)player);
            break;
        case OEDCButtonStart:
            handle_key(Btn_Start, 0, (int)player);
            break;
        default:
            break;
    }
}


std::string os_Locale(){
    return [[[NSLocale preferredLanguages] objectAtIndex:0] UTF8String];
}

std::string os_PrecomposedString(std::string string){
    return [[[NSString stringWithUTF8String:string.c_str()] precomposedStringWithCanonicalMapping] UTF8String];
}

@end
