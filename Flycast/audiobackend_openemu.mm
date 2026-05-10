#import "audiobackend_openemu.h"
#import "FlycastGameCore.h"
#import <OpenEmuBase/OERingBuffer.h>

#include <chrono>

class OpenEmuAudioBackend : public AudioBackend
{
public:
    OpenEmuAudioBackend() : AudioBackend("openemu", "OpenEmu") {}

    bool init() override
    {
        return true;
    }

    u32 push(const void* frame, u32 samples, bool wait) override
    {
        (void)wait;

        id<OEAudioBuffer> buffer = [_current audioBufferAtIndex:0];
        const size_t byteCount = (size_t)samples * 4;
        (void)[buffer write:frame maxLength:byteCount];
        return 1;
    }

    void term() override {}
};

static OpenEmuAudioBackend openEmuAudioBackend;

