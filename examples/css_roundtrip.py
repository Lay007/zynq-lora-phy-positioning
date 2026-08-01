"""Run a deterministic CSS modulation/channel/demodulation example."""

import numpy as np

from zynq_lora_phy import (
    CssConfig,
    add_awgn,
    apply_frequency_offset,
    demodulate,
    estimate_frequency_offset,
    modulate,
)


def main() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=2)
    transmitted = np.array([0, 1, 17, 42, 127])
    normalized_cfo = 0.00125
    waveform = modulate(transmitted, config)
    impaired = apply_frequency_offset(waveform, normalized_cfo)
    impaired = add_awgn(impaired, snr_db=12.0, rng=np.random.default_rng(7))

    first_symbol = impaired[: config.samples_per_symbol]
    estimated_cfo = estimate_frequency_offset(first_symbol, config, known_symbol=0)
    received = demodulate(
        impaired,
        config,
        frequency_offset_cycles_per_sample=estimated_cfo,
    )

    print(f"true normalized CFO:      {normalized_cfo:+.7f} cycles/sample")
    print(f"estimated normalized CFO: {estimated_cfo:+.7f} cycles/sample")
    print(f"transmitted symbols:       {transmitted.tolist()}")
    print(f"received symbols:          {received.tolist()}")
    if not np.array_equal(transmitted, received):
        raise SystemExit("round-trip failed")


if __name__ == "__main__":
    main()
