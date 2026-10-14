#include "DSP.h"
#include <algorithm>
#include <atomic>
#include <cmath>
#include <complex>
#include <new>
namespace {
constexpr double pi = 3.14159265358979323846;
struct Coeff {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
};
Coeff subtract(Coeff a, Coeff b, double n) {
    return {(a.b0 - b.b0) / n, (a.b1 - b.b1) / n, (a.b2 - b.b2) / n, (a.a1 - b.a1) / n, (a.a2 - b.a2) / n};
}
void advance(Coeff &a, Coeff d) {
    a.b0 += d.b0;
    a.b1 += d.b1;
    a.b2 += d.b2;
    a.a1 += d.a1;
    a.a2 += d.a2;
}
bool applicable(const DEQBand &b, int c) {
    return b.enabled && (b.channel == DEQ_STEREO || b.channel == c + 1);
}
bool valid(const DEQConfig &c) {
    if (!std::isfinite(c.sampleRate) || c.sampleRate < 8000 || c.sampleRate > 384000 || c.bandCount < 0 ||
        c.bandCount > 64 || !std::isfinite(c.preampDB) || c.preampDB < -120 || c.preampDB > 48)
        return false;
    for (int i = 0; i < c.bandCount; i++) {
        const auto &b = c.bands[i];
        if (b.type < 0 || b.type > 5 || b.channel < 0 || b.channel > 2 || !std::isfinite(b.frequency) ||
            b.frequency <= 0 || b.frequency >= c.sampleRate / 2 || !std::isfinite(b.q) || b.q < 0.05 ||
            b.q > 100 || !std::isfinite(b.gainDB) || std::abs(b.gainDB) > 48)
            return false;
    }
    return true;
}
Coeff coefficients(const DEQBand &b, double sr) {
    double w = 2 * pi * b.frequency / sr, cs = std::cos(w), sn = std::sin(w), A = std::pow(10, b.gainDB / 40),
           alpha = sn / (2 * b.q), root = 2 * std::sqrt(A) * alpha;
    double b0 = 1, b1 = 0, b2 = 0, a0 = 1, a1 = 0, a2 = 0;
    switch (b.type) {
    case DEQ_PEAK:
        b0 = 1 + alpha * A;
        b1 = -2 * cs;
        b2 = 1 - alpha * A;
        a0 = 1 + alpha / A;
        a1 = -2 * cs;
        a2 = 1 - alpha / A;
        break;
    case DEQ_LOW_SHELF:
        b0 = A * ((A + 1) - (A - 1) * cs + root);
        b1 = 2 * A * ((A - 1) - (A + 1) * cs);
        b2 = A * ((A + 1) - (A - 1) * cs - root);
        a0 = (A + 1) + (A - 1) * cs + root;
        a1 = -2 * ((A - 1) + (A + 1) * cs);
        a2 = (A + 1) + (A - 1) * cs - root;
        break;
    case DEQ_HIGH_SHELF:
        b0 = A * ((A + 1) + (A - 1) * cs + root);
        b1 = -2 * A * ((A - 1) + (A + 1) * cs);
        b2 = A * ((A + 1) + (A - 1) * cs - root);
        a0 = (A + 1) - (A - 1) * cs + root;
        a1 = 2 * ((A - 1) - (A + 1) * cs);
        a2 = (A + 1) - (A - 1) * cs - root;
        break;
    case DEQ_HIGH_PASS:
        b0 = (1 + cs) / 2;
        b1 = -(1 + cs);
        b2 = b0;
        a0 = 1 + alpha;
        a1 = -2 * cs;
        a2 = 1 - alpha;
        break;
    case DEQ_LOW_PASS:
        b0 = (1 - cs) / 2;
        b1 = 1 - cs;
        b2 = b0;
        a0 = 1 + alpha;
        a1 = -2 * cs;
        a2 = 1 - alpha;
        break;
    case DEQ_NOTCH:
        b0 = 1;
        b1 = -2 * cs;
        b2 = 1;
        a0 = 1 + alpha;
        a1 = -2 * cs;
        a2 = 1 - alpha;
        break;
    }
    return {b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
}
double magnitudeDB(Coeff a, double hz, double sr) {
    auto z = std::polar(1.0, -2 * pi * hz / sr);
    double m = std::abs((a.b0 + a.b1 * z + a.b2 * z * z) / (1.0 + a.a1 * z + a.a2 * z * z));
    return 20 * std::log10(std::max(1e-15, m));
}
struct Prepared {
    Coeff filters[2][64];
    double gain = 1, wet = 1, sampleRate = 48000;
    bool limiter = false;
};
Prepared prepare(const DEQConfig &c) {
    Prepared p;
    p.sampleRate = c.sampleRate;
    p.gain = std::pow(10, DEQEffectivePreampDB(&c) / 20);
    p.wet = c.bypass ? 0 : 1;
    p.limiter = c.limiter;
    for (int ch = 0; ch < 2; ch++)
        for (int i = 0; i < c.bandCount; i++)
            if (applicable(c.bands[i], ch))
                p.filters[ch][i] = coefficients(c.bands[i], c.sampleRate);
    return p;
}
} // namespace
struct DEQEngine {
    static constexpr unsigned capacity = 8;
    Prepared queue[capacity], current, target, delta;
    std::atomic<unsigned> read{0}, write{0};
    double z1[2][64]{}, z2[2][64]{};
    unsigned remaining = 0;
};
static_assert(std::atomic<unsigned>::is_always_lock_free, "Audio queue must be lock free");
extern "C" {
DEQEngine *DEQCreate(double sr) {
    if (!std::isfinite(sr) || sr < 8000 || sr > 384000)
        return nullptr;
    auto *e = new (std::nothrow) DEQEngine;
    if (e)
        e->current.sampleRate = e->target.sampleRate = sr;
    return e;
}
void DEQDestroy(DEQEngine *e) {
    delete e;
}
bool DEQSetConfig(DEQEngine *e, const DEQConfig *c) {
    if (!e || !c || !valid(*c))
        return false;
    unsigned w = e->write.load(std::memory_order_relaxed), r = e->read.load(std::memory_order_acquire);
    if (w - r >= DEQEngine::capacity)
        return false;
    e->queue[w % DEQEngine::capacity] = prepare(*c);
    e->write.store(w + 1, std::memory_order_release);
    return true;
}
double DEQResponseDB(const DEQConfig *c, double hz, int32_t ch) {
    if (!c || !valid(*c) || !std::isfinite(hz) || hz < 0 || hz > c->sampleRate / 2 || ch < 0 || ch > 1)
        return NAN;
    double db = 0;
    for (int i = 0; i < c->bandCount; i++)
        if (applicable(c->bands[i], ch))
            db += magnitudeDB(coefficients(c->bands[i], c->sampleRate), hz, c->sampleRate);
    return db;
}
double DEQEffectivePreampDB(const DEQConfig *c) {
    if (!c || !valid(*c))
        return NAN;
    if (!c->autoHeadroom)
        return c->preampDB;
    double peak = 0;
    double upper = c->sampleRate * .49999;
    for (int ch = 0; ch < 2; ch++) {
        Coeff cs[64];
        for (int b = 0; b < c->bandCount; b++)
            if (applicable(c->bands[b], ch))
                cs[b] = coefficients(c->bands[b], c->sampleRate);
        auto check = [&](double hz) {
            double db = 0;
            for (int b = 0; b < c->bandCount; b++)
                if (applicable(c->bands[b], ch))
                    db += magnitudeDB(cs[b], hz, c->sampleRate);
            peak = std::max(peak, db);
        };
        // Log-grid plus band-centered points capture narrow peaks. This is an estimate;
        // the separately enabled limiter guarantees the output ceiling.
        check(0);
        check(upper);
        for (int i = 0; i <= 4096; i++)
            check(std::exp(std::log(1.0) + double(i) / 4096 * std::log(upper)));
        for (int b = 0; b < c->bandCount; b++)
            if (applicable(c->bands[b], ch)) {
                check(c->bands[b].frequency);
                for (int j = -16; j <= 16; j++)
                    check(std::clamp(c->bands[b].frequency * std::exp(j / (32 * c->bands[b].q)), 1.0, upper));
            }
    }
    return std::min(c->preampDB, -peak - .1);
}
void DEQProcessInterleaved(DEQEngine *e, float *x, uint32_t frames, uint32_t channels) {
    if (!e || !x || !channels)
        return;
    unsigned r = e->read.load(std::memory_order_relaxed), w = e->write.load(std::memory_order_acquire);
    if (r != w) {
        e->target = e->queue[(w - 1) % DEQEngine::capacity];
        e->read.store(w, std::memory_order_release);
        e->remaining = std::max(1u, unsigned(e->target.sampleRate * .02));
        double n = e->remaining;
        for (int ch = 0; ch < 2; ch++)
            for (int b = 0; b < 64; b++)
                e->delta.filters[ch][b] = subtract(e->target.filters[ch][b], e->current.filters[ch][b], n);
        e->delta.gain = (e->target.gain - e->current.gain) / n;
        e->delta.wet = (e->target.wet - e->current.wet) / n;
        e->current.limiter = e->target.limiter;
    }
    for (uint32_t f = 0; f < frames; f++) {
        if (e->remaining) {
            for (int ch = 0; ch < 2; ch++)
                for (int b = 0; b < 64; b++)
                    advance(e->current.filters[ch][b], e->delta.filters[ch][b]);
            e->current.gain += e->delta.gain;
            e->current.wet += e->delta.wet;
            if (!--e->remaining)
                e->current = e->target;
        }
        for (unsigned ch = 0; ch < std::min(2u, channels); ch++) {
            double dry = std::isfinite(x[f * channels + ch]) ? x[f * channels + ch] : 0,
                   y = dry * e->current.gain;
            for (int b = 0; b < 64; b++) {
                auto a = e->current.filters[ch][b];
                double out = a.b0 * y + e->z1[ch][b];
                e->z1[ch][b] = a.b1 * y - a.a1 * out + e->z2[ch][b];
                e->z2[ch][b] = a.b2 * y - a.a2 * out;
                if (std::abs(e->z1[ch][b]) < 1e-25)
                    e->z1[ch][b] = 0;
                if (std::abs(e->z2[ch][b]) < 1e-25)
                    e->z2[ch][b] = 0;
                y = out;
            }
            if (!std::isfinite(y)) {
                y = 0;
                for (int b = 0; b < 64; b++)
                    e->z1[ch][b] = e->z2[ch][b] = 0;
            }
            if (e->current.limiter)
                y = std::clamp(y, -1.0, 1.0);
            x[f * channels + ch] = float(dry + e->current.wet * (y - dry));
        }
    }
}
}
