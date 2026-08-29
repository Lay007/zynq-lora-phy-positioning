#!/bin/sh
set -eu

# Read-only IIO inventory plus a reversible receiver reset/enable check.
# This script never touches QSPI, FPGA manager, TX controls, or RF gain.

if ! command -v devmem >/dev/null 2>&1; then
    echo 'FAIL: devmem is not available in this root filesystem.' >&2
    exit 2
fi

read32() {
    devmem "$1" 32 | tr 'A-F' 'a-f'
}

write32() {
    devmem "$1" 32 "$2" >/dev/null
}

expect_hex() {
    actual_value=$(read32 "$2")
    if [ "$actual_value" != "$3" ]; then
        echo "FAIL: $1 at $2: expected $3, got $actual_value" >&2
        exit 3
    fi
    echo "PASS: $1 = $actual_value"
}

echo '=== IIO inventory (read-only) ==='
for iio_dev in /sys/bus/iio/devices/iio:device*; do
    [ -d "$iio_dev" ] || continue
    if [ -r "$iio_dev/name" ]; then
        iio_name=$(cat "$iio_dev/name")
    else
        iio_name='unknown'
    fi
    echo "$iio_dev: $iio_name"
    for freq_file in "$iio_dev"/*sampling_frequency; do
        [ -r "$freq_file" ] || continue
        echo "  $(basename "$freq_file")=$(cat "$freq_file")"
    done
done

echo '=== LoRa PL identity ==='
expect_hex 'axi_gpreg core ID' 0x79040004 0x4c4f5241
expect_hex 'bridge signature' 0x790405c8 0x4c4f5241

echo '=== Receiver sample-domain reset/enable ==='
# sync word 0x12, stream reset asserted, receiver enabled
write32 0x79040404 0x00001203
sleep 1
# release only the stream reset; receiver remains enabled
write32 0x79040404 0x00001201
sleep 1

status=$(read32 0x79040408)
status_value=$((status))
echo "status=$status"

if [ $(((status_value >> 16) & 0xffff)) -ne 1 ]; then
    echo 'FAIL: unexpected bridge build version.' >&2
    exit 4
fi
if [ $(((status_value >> 8) & 0xff)) -ne 18 ]; then
    echo 'FAIL: sync word 0x12 did not read back.' >&2
    exit 5
fi
if [ $((status_value & 0x01)) -eq 0 ]; then
    echo 'FAIL: receiver enable is not requested in the PS domain.' >&2
    exit 6
fi
if [ $((status_value & 0x02)) -eq 0 ]; then
    echo 'FAIL: receiver enable did not cross into the sample domain.' >&2
    exit 7
fi
if [ $((status_value & 0x08)) -ne 0 ]; then
    echo 'FAIL: sticky metadata/mailbox overflow is set.' >&2
    exit 8
fi
if [ $((status_value & 0x40)) -eq 0 ]; then
    echo 'FAIL: no formatted RX sample was observed after reset.' >&2
    exit 9
fi

echo 'PASS: sample-domain enable and formatted RX activity observed.'

echo '=== Atomic metadata snapshot (may be zero before the first packet) ==='
sequence_before=$(read32 0x79040448)
coarse_lo=$(read32 0x79040488)
coarse_hi=$(read32 0x790404c8)
fraction_q12=$(read32 0x79040508)
log_peak_q12=$(read32 0x79040548)
debug_word=$(read32 0x79040588)
sequence_after=$(read32 0x79040448)

echo "sequence_before=$sequence_before"
echo "coarse_hi=$coarse_hi coarse_lo=$coarse_lo"
echo "fraction_q12=$fraction_q12 log_peak_q12=$log_peak_q12"
echo "debug=$debug_word sequence_after=$sequence_after"

if [ "$sequence_before" != "$sequence_after" ]; then
    echo 'RETRY: metadata changed during the read; run the script again.' >&2
    exit 10
fi

echo 'PASS: cold-boot PL smoke test completed without RF transmission.'
