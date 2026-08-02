# One-machine transmit, capture, and analysis

`tools/run_phy_experiment.py` runs the complete first-stage PHY measurement
from one Windows computer:

```text
configure transmitter over USB serial
             ↓
arm PlutoSDR or RTL-SDR recording
             ↓
send individually acknowledged packets
             ↓
finish and checksum the IQ recording
             ↓
run unattended MATLAB inspection
             ↓
write raw data, logs, metadata, JSON, MAT, and PNG reports
```

The serial command protocol is already implemented by the LILYGO LR1121
reference firmware. The future Heltec SX1262 firmware should implement the same
`stop`, `set ...`, `show`, and `send` commands, so the host workflow does not
depend on the transmitter board.

## Installation

Create a virtual environment and install the project plus hardware extras:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -e ".[hardware,dev]"
```

PlutoSDR additionally requires the Analog Devices IIO runtime and a working
`iio_info -s`. RTL-SDR requires `rtl_sdr.exe` on `PATH`. MATLAB must be
available as `matlab`, or `analysis.matlab_command` must contain its executable
path.

## Configure and dry-run

Copy one example and edit the serial port, legal RF frequency, gain, and radio
address:

```powershell
Copy-Item experiments/configs/one-machine-pluto.example.json `
  experiments/configs/my-pluto.local.json
```

Do not commit a machine-specific copy unless it is an intentional experiment
record. Check the complete plan without opening a serial port or SDR:

```powershell
python tools/run_phy_experiment.py `
  --config experiments/configs/my-pluto.local.json `
  --dry-run
```

The dry-run validates that the recording is long enough for the requested
packet count and prints every transmitter and receiver command.
Before `--execute`, replace `bench.antenna_or_cable_path = "EDIT BEFORE RUN"`
with the real antenna geometry or complete attenuated cable path. Execution is
refused while the placeholder remains.

## Run

After connecting correct antennas, or a calculated conducted path with enough
attenuation:

```powershell
python tools/run_phy_experiment.py `
  --config experiments/configs/my-pluto.local.json `
  --execute
```

Use `one-machine-rtl-sdr.example.json` for RTL-SDR. Add `--skip-analysis` when
MATLAB is temporarily unavailable; the immutable raw recording and metadata
are still retained.

Each run is written below `artifacts/phy-runs/<UTC>-<run-name>/`:

```text
experiment-config.json       exact input configuration
run.json                     state, commit, TX confirmations, hashes
transmitter.log              timestamped serial commands and replies
receiver.stdout.log          recorder output
receiver.stderr.log          recorder diagnostics
capture/*.cf32 or *.cu8      immutable raw IQ
capture/*metadata.json       Pluto read-back configuration
analysis/*inspection.json    compact parameter estimates
analysis/*inspection.mat     complete MATLAB result structure
analysis/*inspection.png     four-panel visual report
analysis/*matlab.log         unattended MATLAB log
```

The Pluto recorder creates an arm file only after radio configuration and RX
warm-up. The orchestrator waits for this handshake and a short
`post_arm_delay_s`, allowing the blocking RX call to start before issuing
`send`.
RTL-SDR has no equivalent control handshake, so the workflow checks that its
process remains alive and uses the configured `arm_delay_s`.

## Safety and timing boundary

- The example uses 0 dBm, but it does not prove that a particular RF connection
  is safe or locally legal. Verify antennas, regional frequency, transmitter
  variant, SDR input limits, and attenuation before running it.
- The script sends individual packets rather than enabling an uncontrolled
  periodic transmitter. Every packet must return a `TX ... state=0` line.
- Real serial access and RF transmission require the explicit `--execute`
  switch; omitting both `--execute` and `--dry-run` is an error.
- If any stage fails, the receiver is terminated and `run.json` is marked
  `failed`; partial raw files are preserved for diagnosis.
- USB serial and process start times provide capture coordination, not precise
  RF timestamps. This workflow is appropriate for PHY compatibility and
  visualization. ToA/TDoA must later use hardware timestamps in PL or a shared
  trigger/clock.
