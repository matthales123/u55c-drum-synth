#include "../src/drum_synth.hpp"

#include <cstdlib>
#include <iostream>
#include <vector>

namespace {

constexpr int kAudioMax = (1 << 23) - 1;
constexpr int kAudioMin = -(1 << 23);

int clamp_audio24(const long long value) {
  if (value > kAudioMax) {
    return kAudioMax;
  }
  if (value < kAudioMin) {
    return kAudioMin;
  }
  return static_cast<int>(value);
}

int mix_sample(const int sample, const short gain_q15) {
  const long long wet = (static_cast<long long>(sample) * static_cast<long long>(gain_q15)) >> 15;
  const int dry = sample >> 2;
  return clamp_audio24(wet + dry);
}

}  // namespace

int main() {
  constexpr unsigned int n = 1024;
  std::vector<ap_uint<32>> sample_mem(n);
  std::vector<ap_uint<32>> gain_mem(n);
  std::vector<ap_uint<32>> mixed_mem(n);

  for (unsigned int i = 0; i < n; ++i) {
    const int sample = static_cast<int>((static_cast<int>(i) % 4096) - 2048) << 8;
    const short gain_q15 = static_cast<short>((static_cast<int>(i % 1024) - 512) * 48);
    sample_mem[i] = static_cast<ap_uint<32>>(sample);
    gain_mem[i] = static_cast<ap_uint<32>>(static_cast<unsigned short>(gain_q15));
  }

  drum_synth(sample_mem.data(), gain_mem.data(), mixed_mem.data(), n);

  for (unsigned int i = 0; i < n; ++i) {
    const int sample = static_cast<int>(sample_mem[i]);
    const short gain_q15 = static_cast<short>(gain_mem[i] & 0xFFFF);
    const ap_uint<32> expected = static_cast<ap_uint<32>>(mix_sample(sample, gain_q15));
    if (mixed_mem[i] != expected) {
      std::cerr << "Mismatch at i=" << i << ": got " << mixed_mem[i] << " expected " << expected
                << '\n';
      return EXIT_FAILURE;
    }
  }

  std::cout << "drum_synth_tb PASS\n";
  return EXIT_SUCCESS;
}
