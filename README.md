# U55C Drum Synthesis

Cornell ECE5760 drum project port with an HLS sample-processing kernel, XRT host
code, CPU synthesis functions and a local waveform/audio interface. Original
course source attribution is retained.

## Build and run

```bash
./scripts/check_setup.sh
./scripts/build_host.sh
make -C hardware/hls xclbin TARGET=hw KERNEL_NAME=drum_synth PLATFORM=xilinx_u55c_gen3x16_xdma_3_202210_1
./scripts/run_webapp_drum.sh
```

Open `http://127.0.0.1:9892`. The web synthesis endpoint includes a Python FPGA
model; a model result is not a hardware measurement. Actual hardware benchmarks
require a matching XCLBIN and XRT host execution. `make correctness` runs the
existing correctness workflow. No new board-validation claim is made by this export.

Original course project: https://github.com/matthales123/ece5760-drum-synth

## Requirements

For FPGA builds, install AMD Vitis/Vivado 2025.1, XRT, and the compatible
`xilinx_u55c_gen3x16_xdma_3_202210_1` platform. Source your installation's
`settings64.sh` and XRT setup script before building. Python 3, a C++ compiler,
CMake and Make are required for the host/tooling. Run commands from this repository.
Keep the checkout path free of spaces for Vitis HLS.

The source includes host programs, HDL/HLS, tests and local web tooling. Generated
builds, debugging sessions, reports and results are excluded from this public copy.
Web applications are local development interfaces with hardware controls; public
Internet demo access is a separate future deployment.
