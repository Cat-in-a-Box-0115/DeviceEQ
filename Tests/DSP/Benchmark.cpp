#include "../../Sources/DSP/DSP.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <vector>
int main(){DEQConfig c{};c.sampleRate=48000;c.bandCount=64;c.autoHeadroom=1;for(int i=0;i<64;i++)c.bands[i]={DEQ_PEAK,DEQ_STEREO,1,20*std::pow(1000.,i/63.),(i%2?1.:-1.),1.};auto*e=DEQCreate(c.sampleRate);if(!DEQSetConfig(e,&c))return 1;std::array<float,1024> block{};DEQProcessInterleaved(e,block.data(),512,2);std::vector<double>times;times.reserve(11250);for(int b=0;b<11250;b++){for(int f=0;f<512;f++)block[2*f]=block[2*f+1]=.001*std::sin(2*3.141592653589793*997*(b*512+f)/48000);auto begin=std::chrono::steady_clock::now();DEQProcessInterleaved(e,block.data(),512,2);auto end=std::chrono::steady_clock::now();times.push_back(std::chrono::duration<double,std::micro>(end-begin).count());}DEQDestroy(e);double sum=0;for(auto t:times)sum+=t;std::sort(times.begin(),times.end());printf("{\"bands\":64,\"channels\":2,\"sampleRate\":48000,\"blockFrames\":512,\"audioSeconds\":120,\"processingSeconds\":%.6f,\"estimatedOneCorePercent\":%.3f,\"p99BlockMicroseconds\":%.3f,\"maxBlockMicroseconds\":%.3f,\"bufferDeadlineMicroseconds\":10666.667,\"scope\":\"DSP microbenchmark, not live HAL CPU or dropout measurement\"}\n",sum/1e6,sum/1e6/120*100,times[times.size()*99/100],times.back());}
