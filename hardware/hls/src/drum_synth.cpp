#include "drum_synth.hpp"

namespace {

constexpr int kAudioMax = (1 << 23) - 1;
constexpr int kAudioMin = -(1 << 23);

inline int clamp_audio24(const long long value) {
  if (value > kAudioMax) {
    return kAudioMax;
  }
  if (value < kAudioMin) {
    return kAudioMin;
  }
  return static_cast<int>(value);
}

inline int mix_sample(const int sample, const short gain_q15) {
  const long long wet = (static_cast<long long>(sample) * static_cast<long long>(gain_q15)) >> 15;
  const int dry = sample >> 2;
  return clamp_audio24(wet + dry);
}

}  // namespace

extern "C" {
void drum_synth(const ap_uint<32>* sample_mem,
               const ap_uint<32>* gain_mem,
               ap_uint<32>* mixed_mem,
               const unsigned int n) {
#pragma HLS INTERFACE m_axi port = sample_mem offset = slave bundle = gmem0 max_read_burst_length = 64 num_read_outstanding = 16
#pragma HLS INTERFACE m_axi port = gain_mem offset = slave bundle = gmem1 max_read_burst_length = 64 num_read_outstanding = 16
#pragma HLS INTERFACE m_axi port = mixed_mem offset = slave bundle = gmem2 max_write_burst_length = 64 num_write_outstanding = 16
#pragma HLS INTERFACE s_axilite port = sample_mem bundle = control
#pragma HLS INTERFACE s_axilite port = gain_mem bundle = control
#pragma HLS INTERFACE s_axilite port = mixed_mem bundle = control
#pragma HLS INTERFACE s_axilite port = n bundle = control
#pragma HLS INTERFACE s_axilite port = return bundle = control

  for (unsigned int i = 0; i < n; ++i) {
#pragma HLS PIPELINE II = 1
    const int sample = static_cast<int>(sample_mem[i]);
    const short gain_q15 = static_cast<short>(gain_mem[i] & 0xFFFF);
    const int mixed = mix_sample(sample, gain_q15);
    mixed_mem[i] = static_cast<ap_uint<32>>(mixed);
  }
}
}
