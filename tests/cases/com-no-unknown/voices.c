/* SPDX-License-Identifier: 0BSD */
/*
 * A vtable with no IUnknown at the front, which is the shape XAudio2's voices
 * have: three function pointers, the first of them at slot 0, and a lifetime
 * the library owns rather than a count.
 */
#include <stdio.h>

#ifdef _WIN32
#define VOICECALL __stdcall
#else
#define VOICECALL
#endif

typedef struct Voice Voice;

typedef struct VoiceVtbl
{
    int  (VOICECALL *Volume)(Voice *self);
    void (VOICECALL *SetVolume)(Voice *self, int level);
    int  (VOICECALL *Mix)(Voice *self, int left, int right);
    void (VOICECALL *Destroy)(Voice *self);
} VoiceVtbl;

struct Voice
{
    const VoiceVtbl *vtbl;
    int volume;
    int alive;
};

static int VOICECALL VolumeOf(Voice *self)
{
    return self->volume;
}

static void VOICECALL SetVolumeOf(Voice *self, int level)
{
    self->volume = level;
}

static int VOICECALL MixOf(Voice *self, int left, int right)
{
    return (left + right) * self->volume;
}

static void VOICECALL DestroyOf(Voice *self)
{
    printf("c: voice destroyed\n");
    self->alive = 0;
    self->volume = 0;
}

static const VoiceVtbl table = { VolumeOf, SetVolumeOf, MixOf, DestroyOf };

static Voice one = { &table, 3, 1 };
static Voice two = { &table, 5, 1 };

void *make_voice(int which)
{
    return which == 0 ? (void *)&one : (void *)&two;
}

int voice_is_alive(int which)
{
    return which == 0 ? one.alive : two.alive;
}
