#include "../../Sources/DSP/DSP.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>
#include <thread>
#include <atomic>
static DEQConfig config(){DEQConfig c{};c.sampleRate=48000;return c;}
static void close(double actual,double expected,double tolerance=.02){assert(std::isfinite(actual));assert(std::abs(actual-expected)<tolerance);}
int main(){
 auto c=config();c.bandCount=1;c.bands[0]={DEQ_PEAK,DEQ_LEFT,1,1000,12,1};
 close(DEQResponseDB(&c,1000,0),12);close(DEQResponseDB(&c,1000,1),0);
 c.bands[0].type=DEQ_LOW_SHELF;close(DEQResponseDB(&c,0,0),12);close(DEQResponseDB(&c,24000,0),0);
 c.bands[0].type=DEQ_HIGH_SHELF;close(DEQResponseDB(&c,0,0),0);close(DEQResponseDB(&c,24000,0),12);
 c.bands[0].type=DEQ_LOW_PASS;c.bands[0].q=std::sqrt(.5);close(DEQResponseDB(&c,1000,0),-3.0103);
 c.bands[0].type=DEQ_HIGH_PASS;close(DEQResponseDB(&c,1000,0),-3.0103);
 c.bands[0].type=DEQ_NOTCH;assert(DEQResponseDB(&c,1000,0)<-200);
 c.bands[0]={DEQ_PEAK,DEQ_LEFT,1,1000,12,1};c.autoHeadroom=1;close(DEQEffectivePreampDB(&c),-12.1);c.autoHeadroom=0;
 auto *e=DEQCreate(48000);assert(e);assert(DEQSetConfig(e,&c));
 std::vector<float> audio(48000*2);for(int f=0;f<48000;f++)audio[f*2]=audio[f*2+1]=.1f*std::sin(2*3.141592653589793*1000*f/48000);
 DEQProcessInterleaved(e,audio.data(),48000,2);double l=0,r=0;for(int f=24000;f<48000;f++){l+=audio[2*f]*audio[2*f];r+=audio[2*f+1]*audio[2*f+1];}close(10*std::log10(l/r),12);
 c.bypass=1;assert(DEQSetConfig(e,&c));for(int f=0;f<48000;f++)audio[f*2]=audio[f*2+1]=.1f;DEQProcessInterleaved(e,audio.data(),48000,2);close(audio.back(),.1,1e-7);close(audio[audio.size()-2],.1,1e-7);
 c.bypass=0;c.limiter=1;assert(DEQSetConfig(e,&c));for(int f=0;f<48000;f++)audio[f*2]=audio[f*2+1]=.9f*std::sin(2*3.141592653589793*1000*f/48000);DEQProcessInterleaved(e,audio.data(),48000,2);for(auto a:audio)assert(std::abs(a)<=1.000001);
 c.bands[0].q=0;assert(!DEQSetConfig(e,&c));c.bands[0].q=1;
 // SPSC publication and queue overflow with a live consumer.
 std::atomic<bool> done{false};std::thread consumer([&]{float buffer[256]{};while(!done.load())DEQProcessInterleaved(e,buffer,128,2);});
 for(int i=0;i<100;i++){c.bands[0].gainDB=(i%2)?12:-12;while(!DEQSetConfig(e,&c))std::this_thread::yield();}done=true;consumer.join();DEQDestroy(e);
 puts("DSP tests passed: RBJ response, shelf endpoints, pass cutoff, notch, headroom, stereo isolation, rendered gain, bypass, limiter, invalid input, lock-free publication.");
}
