#!/usr/bin/env python3
from __future__ import annotations

import html
import math
import os
import random
import re
import shlex
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

try:
    import markdown as markdown_lib
except Exception:  # pragma: no cover
    markdown_lib = None

APP_NAME = "U55C Drum Synth Lab"
ROOT_DIR = Path(__file__).resolve().parents[1]
STATIC_DIR = Path(__file__).resolve().parent / "static"
PROJECT_ENV = ROOT_DIR / "config" / "project.env"
README_ROOT = ROOT_DIR / "README"
TOP_README = ROOT_DIR / "README.md"
README_ASSETS = README_ROOT / "assets"
BENCH_BIN = ROOT_DIR / "build" / "host" / "u55c_bench"
BUILD_HOST_SCRIPT = ROOT_DIR / "scripts" / "build_host.sh"
XRT_SMI = os.environ.get("WEB_XRT_SMI", "/opt/xilinx/xrt/bin/xrt-smi")
AUDIO_MAX = (1 << 23) - 1
AUDIO_MIN = -(1 << 23)


class DrumRequest(BaseModel):
    length: int = Field(default=65536, ge=512, le=500000)
    sample_rate: int = Field(default=48000, ge=8000, le=192000)
    bpm: float = Field(default=120.0, ge=40.0, le=280.0)
    seed: int = 1
    kick_level: float = Field(default=0.9, ge=0.0, le=1.0)
    snare_level: float = Field(default=0.65, ge=0.0, le=1.0)
    hat_level: float = Field(default=0.45, ge=0.0, le=1.0)


class BenchmarkRequest(BaseModel):
    mode: str = "hw"
    elements: int = Field(default=65536, ge=1, le=5_000_000)
    iterations: int = Field(default=1, ge=1, le=50)
    device: str = "0"
    kernel: str = "drum_synth"
    seed: int = 1
    xclbin_path: str = ""
    rebuild_host: bool = False


class ProgramRequest(BaseModel):
    xclbin_path: str = ""
    device: str = "0"


class DocRequest(BaseModel):
    key: str


app = FastAPI(title=APP_NAME)
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
if README_ASSETS.exists():
    app.mount("/README/assets", StaticFiles(directory=str(README_ASSETS)), name="readme_assets")


def read_project_env() -> Dict[str, str]:
    values: Dict[str, str] = {}
    if not PROJECT_ENV.exists():
        return values
    for raw in PROJECT_ENV.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def startup_gate_state() -> Dict[str, Any]:
    status_raw = os.environ.get("WEBAPP_STARTUP_GATE_STATUS", "ok").strip().lower()
    message = os.environ.get("WEBAPP_STARTUP_GATE_MESSAGE", "").strip()
    rc_raw = os.environ.get("WEBAPP_STARTUP_GATE_RC", "0").strip()

    status = status_raw if status_raw in {"ok", "warn", "skipped"} else "unknown"
    try:
        rc: Optional[int] = int(rc_raw)
    except ValueError:
        rc = None

    return {
        "status": status,
        "message": message,
        "rc": rc,
    }


def resolve_project_path(path_value: str) -> Path:
    expanded = Path(os.path.expandvars(os.path.expanduser(path_value)))
    if expanded.is_absolute():
        return expanded
    return (ROOT_DIR / expanded).resolve()


def run_command(cmd: List[str], timeout_s: int = 180) -> Dict[str, Any]:
    start = time.perf_counter()
    proc = subprocess.run(
        cmd,
        cwd=str(ROOT_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout_s,
        check=False,
    )
    elapsed_ms = (time.perf_counter() - start) * 1000.0
    return {
        "ok": proc.returncode == 0,
        "rc": proc.returncode,
        "elapsed_ms": elapsed_ms,
        "cmd": " ".join(shlex.quote(x) for x in cmd),
        "output": proc.stdout,
    }


def ensure_host_binary(rebuild: bool) -> None:
    if rebuild or not BENCH_BIN.exists():
        proc = run_command([str(BUILD_HOST_SCRIPT)], timeout_s=600)
        if not proc["ok"]:
            tail = "\n".join(proc["output"].splitlines()[-40:])
            raise HTTPException(status_code=500, detail=f"host build failed (rc={proc['rc']})\n{tail}")


def parse_bench_summary(text: str) -> Dict[str, Any]:
    lines = [line.strip() for line in text.splitlines() if line.strip().startswith("mode=")]
    if not lines:
        return {"summary_line": "", "metrics": {}}
    summary = lines[-1]
    metrics: Dict[str, Any] = {}
    for token in summary.split():
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        raw = value.strip().strip(",")
        if re.fullmatch(r"[-+]?\d+", raw):
            metrics[key] = int(raw)
        elif re.fullmatch(r"[-+]?\d*\.\d+", raw):
            metrics[key] = float(raw)
        else:
            metrics[key] = raw
    return {"summary_line": summary, "metrics": metrics}


def resolve_program_device(device: str) -> str:
    candidate = device.strip()
    if re.fullmatch(r"[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\\.[0-9a-fA-F]", candidate):
        return candidate
    if candidate.isdigit():
        probe = run_command([XRT_SMI, "examine"], timeout_s=30)
        if probe["ok"]:
            bdfs = re.findall(r"\[([0-9A-Fa-f:.]+)\]", probe["output"])
            idx = int(candidate)
            if idx < len(bdfs):
                return bdfs[idx]
    return candidate


def clamp_audio24(value: int) -> int:
    if value > AUDIO_MAX:
        return AUDIO_MAX
    if value < AUDIO_MIN:
        return AUDIO_MIN
    return value


def q15_from_float(value: float) -> int:
    return max(-32768, min(32767, int(round(value * 32767.0))))


def synthesize_drum(req: DrumRequest) -> Dict[str, Any]:
    rng = random.Random(req.seed)
    length = req.length
    sr = req.sample_rate

    step_samples = max(1, int(sr * 60.0 / req.bpm / 4.0))
    kick_pattern = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0]
    snare_pattern = [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0]
    hat_pattern = [1] * 16

    kick_env = 0.0
    snare_env = 0.0
    hat_env = 0.0
    kick_phase = 0.0

    mixed: List[int] = [0] * length
    dry_samples: List[int] = [0] * length

    two_pi = 2.0 * math.pi

    start = time.perf_counter()
    for i in range(length):
        if i % step_samples == 0:
            step = (i // step_samples) % 16
            if kick_pattern[step]:
                kick_env = req.kick_level
            if snare_pattern[step]:
                snare_env = req.snare_level
            if hat_pattern[step]:
                hat_env = req.hat_level

        kick_env *= 0.9995
        snare_env *= 0.9988
        hat_env *= 0.9973

        kick_phase += (45.0 + 90.0 * kick_env) / sr
        kick = math.sin(two_pi * kick_phase) * kick_env
        snare = (rng.random() * 2.0 - 1.0) * snare_env
        hat = (rng.random() * 2.0 - 1.0) * hat_env * 0.5

        sample = int(round((kick + snare + hat) * (1 << 22)))
        sample = clamp_audio24(sample)

        gain_q15 = q15_from_float(0.5 + 0.45 * math.sin((two_pi * i) / max(1, length)))
        wet = (sample * gain_q15) >> 15
        mixed_sample = clamp_audio24(wet + (sample >> 2))

        dry_samples[i] = sample
        mixed[i] = mixed_sample

    elapsed_ms = (time.perf_counter() - start) * 1000.0

    preview_count = min(4096, length)
    rms = math.sqrt(sum((x / float(1 << 23)) ** 2 for x in mixed) / max(1, length))

    return {
        "length": length,
        "sample_rate": sr,
        "bpm": req.bpm,
        "elapsed_ms": elapsed_ms,
        "rms": rms,
        "preview": {
            "dry": dry_samples[:preview_count],
            "mixed": mixed[:preview_count],
        },
    }


def synthesize_drum_fpga_model(req: DrumRequest) -> Dict[str, Any]:
    rng = random.Random(req.seed + 9173)
    length = req.length
    sr = req.sample_rate

    step_samples = max(1, int(sr * 60.0 / req.bpm / 4.0))
    kick_pattern = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0]
    snare_pattern = [0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0]
    hat_pattern = [1] * 16

    kick_env = 0.0
    snare_env = 0.0
    hat_env = 0.0
    kick_phase = 0.0

    mixed: List[int] = [0] * length
    dry_samples: List[int] = [0] * length

    two_pi = 2.0 * math.pi

    start = time.perf_counter()
    for i in range(length):
        if i % step_samples == 0:
            step = (i // step_samples) % 16
            if kick_pattern[step]:
                kick_env = req.kick_level
            if snare_pattern[step]:
                snare_env = req.snare_level
            if hat_pattern[step]:
                hat_env = req.hat_level

        # Slightly more quantized decay to mimic kernel-friendly fixed-point behavior.
        kick_env = round(kick_env * 0.9993 * 4096.0) / 4096.0
        snare_env = round(snare_env * 0.9985 * 4096.0) / 4096.0
        hat_env = round(hat_env * 0.9970 * 4096.0) / 4096.0

        kick_phase += (44.0 + 88.0 * kick_env) / sr
        kick_phase = kick_phase % 1.0
        kick = math.sin(two_pi * kick_phase) * kick_env
        snare = (rng.random() * 2.0 - 1.0) * snare_env
        hat = (rng.random() * 2.0 - 1.0) * hat_env * 0.45

        sample = int(round((kick + snare + hat) * (1 << 22)))
        sample = clamp_audio24(sample)

        gain_q15 = q15_from_float(0.52 + 0.42 * math.sin((two_pi * i) / max(1, length)))
        wet = (sample * gain_q15) >> 15
        mixed_sample = clamp_audio24(wet + (sample >> 2))

        dry_samples[i] = sample
        mixed[i] = mixed_sample

    elapsed_ms = (time.perf_counter() - start) * 1000.0
    preview_count = min(4096, length)
    rms = math.sqrt(sum((x / float(1 << 23)) ** 2 for x in mixed) / max(1, length))

    return {
        "length": length,
        "sample_rate": sr,
        "bpm": req.bpm,
        "elapsed_ms": elapsed_ms,
        "rms": rms,
        "mode": "fpga-model",
        "preview": {
            "dry": dry_samples[:preview_count],
            "mixed": mixed[:preview_count],
        },
    }


def docs_catalog() -> Dict[str, Path]:
    docs: Dict[str, Path] = {}
    hidden_docs = {"RUNBOOK.md", "WEBAPP.md", "TESTS.md", "SETUP.md", "INTERNAL_MILESTONES.md"}
    if TOP_README.exists():
        docs["README.md"] = TOP_README
    if README_ROOT.exists():
        for p in sorted(README_ROOT.glob("*.md")):
            if p.name in hidden_docs:
                continue
            docs[f"README/{p.name}"] = p
    return docs


def markdown_to_html(text: str) -> str:
    if markdown_lib is None:
        return f"<pre>{html.escape(text)}</pre>"
    return markdown_lib.markdown(
        text,
        extensions=["extra", "fenced_code", "tables", "toc", "sane_lists"],
        output_format="html5",
    )


def block_diagram_data() -> Dict[str, Any]:
    return {
        "root_view": "top",
        "views": {
            "top": {
                "id": "top",
                "title": "Drum Synth Accelerator Top-Level",
                "description": "Pipeline from parameterized synthesis control to HBM-backed audio output.",
                "notes": [
                    "CPU controls synthesis parameters and launches kernel work.",
                    "HBM stores sample, gain, and mixed buffers in separate banks.",
                    "Kernel applies fixed-point gain shaping and mix operations.",
                ],
                "nodes": [
                    {
                        "id": "ui",
                        "label": "Web + Host Control",
                        "subtitle": "BPM, levels, length",
                        "x": 40,
                        "y": 70,
                        "w": 240,
                        "h": 110,
                        "group": "software",
                        "details": "Collects rhythm parameters and configures runtime benchmark/synthesis calls.",
                    },
                    {
                        "id": "xrt",
                        "label": "XRT Runtime",
                        "subtitle": "program + launch",
                        "x": 330,
                        "y": 70,
                        "w": 220,
                        "h": 110,
                        "group": "platform",
                        "details": "Allocates buffers, programs xclbin, and launches drum_synth compute units.",
                    },
                    {
                        "id": "hbm",
                        "label": "HBM Audio Buffers",
                        "subtitle": "sample/gain/mixed",
                        "x": 610,
                        "y": 50,
                        "w": 280,
                        "h": 150,
                        "group": "memory",
                        "details": "Banked memory layout supports concurrent read/write paths for synthesis stages.",
                        "drill_to": "memory_path",
                    },
                    {
                        "id": "kernel",
                        "label": "drum_synth Kernel",
                        "subtitle": "fixed-point mix path",
                        "x": 330,
                        "y": 270,
                        "w": 300,
                        "h": 150,
                        "group": "compute",
                        "details": "Processes sample stream, applies gain envelope, and emits mixed output.",
                        "drill_to": "kernel_core",
                    },
                    {
                        "id": "preview",
                        "label": "Waveform Preview",
                        "subtitle": "dry + mixed traces",
                        "x": 700,
                        "y": 290,
                        "w": 240,
                        "h": 120,
                        "group": "observability",
                        "details": "CPU-side waveform overlay validates synthesis behavior and quality.",
                    },
                ],
                "edges": [
                    {"from": "ui", "to": "xrt", "label": "launch/program"},
                    {"from": "xrt", "to": "hbm", "label": "buffer setup"},
                    {"from": "hbm", "to": "kernel", "label": "sample+gain read"},
                    {"from": "kernel", "to": "hbm", "label": "mixed write"},
                    {"from": "hbm", "to": "preview", "label": "result readback"},
                ],
            },
            "kernel_core": {
                "id": "kernel_core",
                "title": "Drum Kernel Datapath",
                "description": "Sample-level fixed-point operations per synthesis step.",
                "notes": [
                    "Dry sample path is generated from rhythm/envelope state.",
                    "Gain path scales sample amplitude with Q1.15 style multiply.",
                    "Mixer combines wet and dry taps into final 24-bit output.",
                ],
                "nodes": [
                    {
                        "id": "sample",
                        "label": "Sample Generator",
                        "subtitle": "kick/snare/hat voice blend",
                        "x": 70,
                        "y": 210,
                        "w": 240,
                        "h": 120,
                        "group": "datapath",
                        "details": "Produces dry sample stream from per-voice envelopes and noise/oscillator sources.",
                    },
                    {
                        "id": "gain",
                        "label": "Gain Scaler",
                        "subtitle": "fixed-point multiply",
                        "x": 370,
                        "y": 210,
                        "w": 240,
                        "h": 120,
                        "group": "compute",
                        "details": "Applies gain profile in fixed-point arithmetic and limits result to audio range.",
                    },
                    {
                        "id": "mix",
                        "label": "Mix + Saturate",
                        "subtitle": "final 24-bit output",
                        "x": 670,
                        "y": 210,
                        "w": 240,
                        "h": 120,
                        "group": "compute",
                        "details": "Combines wet/dry taps and clamps to signed 24-bit range.",
                    },
                ],
                "edges": [
                    {"from": "sample", "to": "gain", "label": "dry sample"},
                    {"from": "gain", "to": "mix", "label": "wet sample"},
                ],
            },
            "memory_path": {
                "id": "memory_path",
                "title": "HBM Memory Path",
                "description": "Bank-level organization for drum synthesis buffers.",
                "notes": [
                    "Separate banks reduce contention across read and write channels.",
                    "Output bank can be consumed directly by host-side waveform tools.",
                ],
                "nodes": [
                    {
                        "id": "samp",
                        "label": "HBM[0] Sample Buffer",
                        "x": 90,
                        "y": 130,
                        "w": 250,
                        "h": 110,
                        "group": "memory",
                        "details": "Dry sample storage and source stream.",
                    },
                    {
                        "id": "gain",
                        "label": "HBM[1] Gain Buffer",
                        "x": 390,
                        "y": 130,
                        "w": 250,
                        "h": 110,
                        "group": "memory",
                        "details": "Gain/envelope values consumed by the kernel datapath.",
                    },
                    {
                        "id": "mix",
                        "label": "HBM[2] Mixed Buffer",
                        "x": 690,
                        "y": 130,
                        "w": 250,
                        "h": 110,
                        "group": "memory",
                        "details": "Final mixed waveform stream written by kernel.",
                    },
                ],
                "edges": [
                    {"from": "samp", "to": "mix", "label": "process path"},
                    {"from": "gain", "to": "mix", "label": "scale path"},
                ],
            },
        },
    }


@app.get("/")
def root() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/api/health")
def api_health() -> Dict[str, Any]:
    env = read_project_env()
    gate = startup_gate_state()
    return {
        "ok": True,
        "app": APP_NAME,
        "project_root": str(ROOT_DIR),
        "default_kernel": env.get("U55C_KERNEL_NAME", "drum_synth"),
        "default_xclbin": str(resolve_project_path(env.get("U55C_XCLBIN", ""))) if env.get("U55C_XCLBIN") else "",
        "startup_gate": gate,
    }


@app.get("/api/docs/list")
def api_docs_list() -> Dict[str, Any]:
    docs = docs_catalog()
    return {
        "ok": True,
        "docs": [{"key": key, "title": key} for key in docs],
    }


@app.post("/api/docs/read")
def api_docs_read(req: DocRequest) -> Dict[str, Any]:
    docs = docs_catalog()
    if req.key not in docs:
        raise HTTPException(status_code=404, detail=f"document not found: {req.key}")
    path = docs[req.key]
    content = path.read_text(encoding="utf-8", errors="replace")
    return {
        "ok": True,
        "key": req.key,
        "title": req.key,
        "content": content,
        "content_html": markdown_to_html(content),
    }


@app.get("/api/diagram")
def api_diagram() -> Dict[str, Any]:
    return block_diagram_data()


@app.post("/api/drum/synthesize")
def api_drum_synthesize(req: DrumRequest) -> Dict[str, Any]:
    return synthesize_drum(req)


@app.post("/api/drum/synthesize-fpga")
def api_drum_synthesize_fpga(req: DrumRequest) -> Dict[str, Any]:
    return synthesize_drum_fpga_model(req)


@app.post("/api/drum/synthesize-both")
def api_drum_synthesize_both(req: DrumRequest) -> Dict[str, Any]:
    cpu = synthesize_drum(req)
    fpga = synthesize_drum_fpga_model(req)
    return {
        "ok": True,
        "cpu": cpu,
        "fpga": fpga,
    }


@app.post("/api/benchmark")
def api_benchmark(req: BenchmarkRequest) -> Dict[str, Any]:
    mode = req.mode.strip().lower()
    if mode not in ("dry-run", "hw"):
        raise HTTPException(status_code=400, detail="mode must be dry-run or hw")

    ensure_host_binary(req.rebuild_host)

    env_cfg = read_project_env()
    xclbin_candidate = req.xclbin_path.strip() or env_cfg.get("U55C_XCLBIN", "")
    resolved_xclbin = ""

    if mode == "hw":
        if not xclbin_candidate:
            raise HTTPException(status_code=400, detail="xclbin path is required in hw mode")
        xclbin = resolve_project_path(xclbin_candidate)
        if not xclbin.exists():
            raise HTTPException(status_code=404, detail=f"xclbin not found: {xclbin}")
        resolved_xclbin = str(xclbin)

    cmd = [
        str(BENCH_BIN),
        "--mode",
        mode,
        "--kernel",
        req.kernel,
        "--device",
        req.device,
        "--elements",
        str(req.elements),
        "--iterations",
        str(req.iterations),
        "--seed",
        str(req.seed),
    ]
    if mode == "hw":
        cmd.extend(["--xclbin", resolved_xclbin])

    result = run_command(cmd, timeout_s=7200)
    parsed = parse_bench_summary(result["output"])
    return {
        "ok": result["ok"],
        "rc": result["rc"],
        "elapsed_ms": result["elapsed_ms"],
        "cmd": result["cmd"],
        "summary": parsed["summary_line"],
        "metrics": parsed["metrics"],
        "output_tail": "\n".join(result["output"].splitlines()[-40:]),
    }


@app.get("/api/fpga/status")
def api_fpga_status() -> Dict[str, Any]:
    if not Path(XRT_SMI).exists():
        raise HTTPException(status_code=500, detail=f"xrt-smi not found at {XRT_SMI}")
    result = run_command([XRT_SMI, "examine"], timeout_s=120)
    return {
        "ok": result["ok"],
        "rc": result["rc"],
        "elapsed_ms": result["elapsed_ms"],
        "output": result["output"],
    }


@app.post("/api/fpga/program")
def api_fpga_program(req: ProgramRequest) -> Dict[str, Any]:
    env_cfg = read_project_env()
    xclbin_candidate = req.xclbin_path.strip() or env_cfg.get("U55C_XCLBIN", "")
    if not xclbin_candidate:
        raise HTTPException(status_code=400, detail="xclbin path is required")

    xclbin = resolve_project_path(xclbin_candidate)
    if not xclbin.exists():
        raise HTTPException(status_code=404, detail=f"xclbin not found: {xclbin}")
    if xclbin.suffix != ".xclbin":
        raise HTTPException(status_code=400, detail="program path must end in .xclbin")

    program_device = resolve_program_device(req.device)
    cmd = [XRT_SMI, "--batch", "program", "--device", program_device, "--user", str(xclbin)]
    result = run_command(cmd, timeout_s=600)
    return {
        "ok": result["ok"],
        "rc": result["rc"],
        "elapsed_ms": result["elapsed_ms"],
        "cmd": result["cmd"],
        "resolved_device": program_device,
        "output": result["output"],
    }


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("WEB_PORT", "9892"))
    uvicorn.run(app, host="0.0.0.0", port=port)
