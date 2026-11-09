const lengthInput = document.getElementById('length');
const sampleRateInput = document.getElementById('sample-rate');
const bpmInput = document.getElementById('bpm');
const seedInput = document.getElementById('seed');
const kickInput = document.getElementById('kick');
const snareInput = document.getElementById('snare');
const hatInput = document.getElementById('hat');

const synthBtn = document.getElementById('synth-btn');
const playCpuBtn = document.getElementById('play-cpu-btn');
const playFpgaBtn = document.getElementById('play-fpga-btn');
const synthMeta = document.getElementById('synth-meta');
const fpgaSynthMeta = document.getElementById('fpga-synth-meta');

const waveCanvas = document.getElementById('wave-canvas');
const waveCtx = waveCanvas.getContext('2d');
const waveFpgaCanvas = document.getElementById('wave-fpga-canvas');
const waveFpgaCtx = waveFpgaCanvas.getContext('2d');

const benchMode = document.getElementById('bench-mode');
const elementsInput = document.getElementById('elements');
const iterationsInput = document.getElementById('iterations');
const deviceInput = document.getElementById('device');
const kernelInput = document.getElementById('kernel');
const xclbinInput = document.getElementById('xclbin');
const statusBtn = document.getElementById('status-btn');
const programBtn = document.getElementById('program-btn');
const benchBtn = document.getElementById('bench-btn');
const logEl = document.getElementById('runtime-log');
const runtimeSummary = document.getElementById('runtime-summary');

let lastCpuMixed = [];
let lastFpgaMixed = [];
let lastSampleRate = 48000;
let audioCtx = null;

function appendLog(msg) {
  const now = new Date().toLocaleTimeString();
  logEl.textContent = `[${now}] ${msg}\n${logEl.textContent}`.slice(0, 50000);
}

function clearWave(ctx, canvas) {
  ctx.fillStyle = '#04080f';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.strokeStyle = '#24354f';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(0, canvas.height / 2);
  ctx.lineTo(canvas.width, canvas.height / 2);
  ctx.stroke();
}

function drawWaveform(ctx, canvas, samples, color) {
  clearWave(ctx, canvas);
  if (!samples || !samples.length) return;

  const w = canvas.width;
  const h = canvas.height;
  ctx.strokeStyle = color;
  ctx.lineWidth = 1.1;
  ctx.beginPath();

  const n = samples.length;
  for (let x = 0; x < w; x++) {
    const idx = Math.floor((x / Math.max(1, w - 1)) * (n - 1));
    const yNorm = samples[idx] / (1 << 23);
    const y = (h * 0.5) - yNorm * (h * 0.42);
    if (x === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.stroke();
}

function getSynthesisPayload() {
  return {
    length: Math.max(512, Number(lengthInput.value || 65536)),
    sample_rate: Math.max(8000, Number(sampleRateInput.value || 48000)),
    bpm: Number(bpmInput.value || 120),
    seed: Number(seedInput.value || 1),
    kick_level: Number(kickInput.value || 0.9),
    snare_level: Number(snareInput.value || 0.65),
    hat_level: Number(hatInput.value || 0.45),
  };
}

async function synthesizeBoth() {
  synthBtn.disabled = true;
  synthMeta.textContent = 'Synthesizing CPU...';
  fpgaSynthMeta.textContent = 'Synthesizing FPGA...';

  try {
    const payload = getSynthesisPayload();
    const resp = await fetch('/api/drum/synthesize-both', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await resp.json();
    if (!resp.ok) {
      throw new Error(data.detail || 'Synthesis failed');
    }

    const cpu = data.cpu || {};
    const fpga = data.fpga || {};

    const cpuMixed = cpu.preview?.mixed || [];
    const fpgaMixed = fpga.preview?.mixed || [];

    drawWaveform(waveCtx, waveCanvas, cpuMixed, '#60a5fa');
    drawWaveform(waveFpgaCtx, waveFpgaCanvas, fpgaMixed, '#f97316');

    lastCpuMixed = cpuMixed;
    lastFpgaMixed = fpgaMixed;
    lastSampleRate = Number(cpu.sample_rate || payload.sample_rate || 48000);

    elementsInput.value = String(cpu.length || payload.length);

    synthMeta.textContent =
      `CPU synthesis ${(cpu.length || payload.length)} samples in ${Number(cpu.elapsed_ms || 0).toFixed(3)} ms | ` +
      `RMS ${Number(cpu.rms || 0).toFixed(6)}`;
    fpgaSynthMeta.textContent =
      `FPGA-model synthesis ${(fpga.length || payload.length)} samples in ${Number(fpga.elapsed_ms || 0).toFixed(3)} ms | ` +
      `RMS ${Number(fpga.rms || 0).toFixed(6)}`;

    if (runtimeSummary) {
      runtimeSummary.textContent =
        `Synthesis complete | CPU ${Number(cpu.elapsed_ms || 0).toFixed(3)} ms | ` +
        `FPGA-model ${Number(fpga.elapsed_ms || 0).toFixed(3)} ms.`;
    }
  } catch (err) {
    synthMeta.textContent = `Synthesis error: ${err.message}`;
    fpgaSynthMeta.textContent = `Synthesis error: ${err.message}`;
  } finally {
    synthBtn.disabled = false;
  }
}

function ensureAudioContext() {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }
  return audioCtx;
}

function playSamples(samples, sampleRate) {
  if (!samples || !samples.length) {
    appendLog('No samples available for playback.');
    return;
  }

  const ctx = ensureAudioContext();
  const buffer = ctx.createBuffer(1, samples.length, sampleRate);
  const ch = buffer.getChannelData(0);
  for (let i = 0; i < samples.length; i++) {
    ch[i] = Math.max(-1, Math.min(1, samples[i] / (1 << 23)));
  }

  const src = ctx.createBufferSource();
  src.buffer = buffer;
  src.connect(ctx.destination);
  src.start();
}

async function runStatus() {
  appendLog('Querying FPGA status...');
  const resp = await fetch('/api/fpga/status');
  const data = await resp.json();
  if (!resp.ok) throw new Error(data.detail || 'Status failed');
  appendLog(data.output || '(no output)');
}

async function runProgram() {
  appendLog('Programming FPGA...');
  const payload = {
    xclbin_path: xclbinInput.value.trim(),
    device: deviceInput.value.trim() || '0',
  };
  const resp = await fetch('/api/fpga/program', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const data = await resp.json();
  if (!resp.ok) throw new Error(data.detail || 'Program failed');
  appendLog(data.output || '(program command completed)');
}

async function runBenchmark() {
  benchBtn.disabled = true;
  appendLog('Running benchmark...');
  try {
    const payload = {
      mode: benchMode.value,
      elements: Math.max(1, Number(elementsInput.value || 1)),
      iterations: Math.max(1, Number(iterationsInput.value || 1)),
      device: deviceInput.value.trim() || '0',
      kernel: kernelInput.value.trim() || 'drum_synth',
      seed: Number(seedInput.value || 1),
      xclbin_path: xclbinInput.value.trim(),
    };
    const resp = await fetch('/api/benchmark', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const data = await resp.json();
    if (!resp.ok) throw new Error(data.detail || 'Benchmark failed');

    appendLog(data.cmd);
    appendLog(data.summary || '(no summary line found)');
    if (data.output_tail) appendLog(data.output_tail);
    if (runtimeSummary) {
      runtimeSummary.textContent = data.summary || 'Benchmark completed (no summary line found).';
    }
  } catch (err) {
    appendLog(`Benchmark error: ${err.message}`);
  } finally {
    benchBtn.disabled = false;
  }
}

synthBtn.addEventListener('click', () => {
  synthesizeBoth().catch((err) => {
    synthMeta.textContent = `Synthesis error: ${err.message}`;
  });
});
playCpuBtn.addEventListener('click', () => {
  playSamples(lastCpuMixed, lastSampleRate);
});
playFpgaBtn.addEventListener('click', () => {
  playSamples(lastFpgaMixed, lastSampleRate);
});

statusBtn.addEventListener('click', () => runStatus().catch((err) => appendLog(`Status error: ${err.message}`)));
programBtn.addEventListener('click', () => runProgram().catch((err) => appendLog(`Program error: ${err.message}`)));
benchBtn.addEventListener('click', () => runBenchmark().catch((err) => appendLog(`Benchmark error: ${err.message}`)));

clearWave(waveCtx, waveCanvas);
clearWave(waveFpgaCtx, waveFpgaCanvas);
synthesizeBoth().catch((err) => {
  synthMeta.textContent = `Synthesis error: ${err.message}`;
});
