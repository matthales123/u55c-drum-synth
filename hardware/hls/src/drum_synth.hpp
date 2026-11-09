#pragma once

#include <ap_int.h>

extern "C" {
void drum_synth(const ap_uint<32>* sample_mem,
               const ap_uint<32>* gain_mem,
               ap_uint<32>* mixed_mem,
               unsigned int n);
}
