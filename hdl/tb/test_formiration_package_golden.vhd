library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
use std.env.all;

use work.ci16_file_io_pkg.all;

entity test_formiration_package_golden is
end test_formiration_package_golden;

architecture Behavioral of test_formiration_package_golden is
    constant CLK_PERIOD       : time := 10 ns;
    constant SAMPLES_PER_CHIP : integer := 16;
    constant SEGMENT_COUNT    : integer := 3;
    constant SYMBOLS_PER_SEGMENT : integer := 10;

    type integer_array_t is array (natural range <>) of integer;

    -- SF7/BW125 production contract, unchanged: six auto h=0 preamble
    -- upchirps, then the current test symbol sequence at exactly this file
    -- path -- CI and lora_phy.verify_tx_checkpoint (tag "package") depend on
    -- both the path and this exact sequence.
    constant SF7_SYMBOLS    : integer_array_t(0 to 9) :=
        (0, 0, 0, 0, 0, 0, 5, 17, 64, 127);
    constant SF7_DIRECTIONS : std_logic_vector(0 to 9) := "0000000010";

    -- SF5/SF6 analogues (small, small-mid, half, max), scaled to each SF's
    -- valid symbol range. formiration_package.vhd itself needed no changes
    -- for these -- it only forwards h_in/sf_in/bw_in to the now-generalized
    -- formiration_chirp. lora_phy.verify_tx_checkpoint's "package" stage
    -- golden model (package_test_sequence in verify_tx_checkpoint.m) must
    -- match these exactly -- both are golden checks against the same VHDL
    -- production contract, just from different tools.
    constant SF5_SYMBOLS    : integer_array_t(0 to 9) :=
        (0, 0, 0, 0, 0, 0, 1, 5, 16, 31);
    constant SF5_DIRECTIONS : std_logic_vector(0 to 9) := "0000000010";

    constant SF6_SYMBOLS    : integer_array_t(0 to 9) :=
        (0, 0, 0, 0, 0, 0, 2, 9, 32, 63);
    constant SF6_DIRECTIONS : std_logic_vector(0 to 9) := "0000000010";

    constant SEGMENT_SF           : integer_array_t(0 to SEGMENT_COUNT-1) := (5, 6, 7);
    constant SEGMENT_PHASE_COEFF  : integer_array_t(0 to SEGMENT_COUNT-1) := (4, 2, 1);

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal valid_in     : std_logic := '0';
    signal begin_in     : std_logic := '0';
    signal h_in         : std_logic_vector(15 downto 0) := (others => '0');
    signal sf_in        : std_logic_vector(3 downto 0) := b"0010";
    signal bw_in        : std_logic_vector(2 downto 0) := b"000";
    signal direction_in : std_logic := '0';
    signal ready_out    : std_logic;
    signal valid_out    : std_logic;
    signal data_out     : std_logic_vector(31 downto 0);
    signal all_done     : std_logic := '0';

    function q14_half(value : real) return signed is
        variable full_scale : signed(15 downto 0);
    begin
        full_scale := to_signed(integer(round(value * 32767.0)), 16);
        return shift_right(full_scale, 1);
    end function;

    function segment_symbols(constant segment : integer; constant idx : integer) return integer is
    begin
        case segment is
            when 0 => return SF5_SYMBOLS(idx);
            when 1 => return SF6_SYMBOLS(idx);
            when others => return SF7_SYMBOLS(idx);
        end case;
    end function;

    function segment_direction(constant segment : integer; constant idx : integer) return std_logic is
    begin
        case segment is
            when 0 => return SF5_DIRECTIONS(idx);
            when 1 => return SF6_DIRECTIONS(idx);
            when others => return SF7_DIRECTIONS(idx);
        end case;
    end function;

    function segment_sf_code(constant segment : integer) return std_logic_vector is
    begin
        case segment is
            when 0 => return b"0000";
            when 1 => return b"0001";
            when others => return b"0010";
        end case;
    end function;

begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.formiration_package
    port map (
        clk          => clk,
        rst          => rst,
        valid_in     => valid_in,
        begin_in     => begin_in,
        h_in         => h_in,
        sf_in        => sf_in,
        bw_in        => bw_in,
        direction_in => direction_in,
        ready_out    => ready_out,
        valid_out    => valid_out,
        data_out     => data_out
    );

    -- Runs continuously from reset, independent of how far the stimulus
    -- process has progressed queueing symbols: formiration_package's
    -- ready_out only reflects FIFO/state readiness for the *next input*,
    -- not whether formiration_chirp has finished *emitting* previously
    -- queued symbols, so sample capture must not be gated by the stimulus
    -- process's own pacing (an earlier single-process version of this
    -- testbench lost the first several output samples this way).
    monitor : process(clk)
        variable sample_count : integer := 0;
        variable segment, local_index, symbol_index, sample_index : integer;
        variable symbol_samples, symbol_value, phase_coeff : integer;
        variable segment_base_sample, segment_total_samples : integer;
        variable direction    : std_logic;
        variable shifted_n, phase_word : integer;
        variable angle        : real;
        variable expected_re, expected_im : signed(15 downto 0);
        variable actual_re, actual_im     : signed(15 downto 0);

        file capture_sf5 : byte_file open write_mode is "build/ghdl-lora/hdl_sf5_bw125k_fs2000k_package.pcm";
        file capture_sf6 : byte_file open write_mode is "build/ghdl-lora/hdl_sf6_bw125k_fs2000k_package.pcm";
        file capture_sf7 : byte_file open write_mode is "build/ghdl-lora/hdl_sf7_bw125k_fs2000k_package.pcm";
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sample_count := 0;
                all_done <= '0';
            elsif all_done /= '1' and valid_out = '1' then
                -- Locate which SF segment sample_count falls into (segments
                -- have different symbol_samples, so this is not a plain
                -- division by a single constant).
                segment := 0;
                segment_base_sample := 0;
                for s in 0 to SEGMENT_COUNT-1 loop
                    symbol_samples := (2 ** SEGMENT_SF(s)) * SAMPLES_PER_CHIP;
                    segment_total_samples := SYMBOLS_PER_SEGMENT * symbol_samples;
                    if sample_count < segment_base_sample + segment_total_samples then
                        segment := s;
                        exit;
                    end if;
                    segment_base_sample := segment_base_sample + segment_total_samples;
                end loop;

                symbol_samples := (2 ** SEGMENT_SF(segment)) * SAMPLES_PER_CHIP;
                phase_coeff    := SEGMENT_PHASE_COEFF(segment);
                local_index    := sample_count - segment_base_sample;
                symbol_index   := local_index / symbol_samples;
                sample_index   := local_index mod symbol_samples;
                symbol_value   := segment_symbols(segment, symbol_index);
                direction      := segment_direction(segment, symbol_index);

                shifted_n := (sample_index + symbol_value * SAMPLES_PER_CHIP)
                    mod symbol_samples;
                phase_word := (phase_coeff * shifted_n * shifted_n -
                               2048 * shifted_n) mod 65536;
                if direction = '1' then
                    phase_word := (-phase_word) mod 65536;
                end if;

                angle := 2.0 * MATH_PI * real(phase_word) / 65536.0;
                expected_re := q14_half(cos(angle));
                expected_im := q14_half(sin(angle));
                actual_re := signed(data_out(31 downto 16));
                actual_im := signed(data_out(15 downto 0));

                assert actual_re = expected_re
                    report "package real mismatch: sf=" & integer'image(SEGMENT_SF(segment)) &
                           " output_symbol=" & integer'image(symbol_index) &
                           " h=" & integer'image(symbol_value) &
                           " sample=" & integer'image(sample_index) &
                           " got=" & integer'image(to_integer(actual_re)) &
                           " expected=" & integer'image(to_integer(expected_re))
                    severity failure;
                assert actual_im = expected_im
                    report "package imag mismatch: sf=" & integer'image(SEGMENT_SF(segment)) &
                           " output_symbol=" & integer'image(symbol_index) &
                           " h=" & integer'image(symbol_value) &
                           " sample=" & integer'image(sample_index) &
                           " got=" & integer'image(to_integer(actual_im)) &
                           " expected=" & integer'image(to_integer(expected_im))
                    severity failure;

                -- Same self-checked samples exported for offline inspection
                -- (see file-naming caveat in the constant declarations above).
                case segment is
                    when 0 => write_ci16_sample(capture_sf5, data_out);
                    when 1 => write_ci16_sample(capture_sf6, data_out);
                    when others => write_ci16_sample(capture_sf7, data_out);
                end case;

                if segment = SEGMENT_COUNT-1 and symbol_index = SYMBOLS_PER_SEGMENT-1
                        and sample_index = symbol_samples-1 then
                    all_done <= '1';
                    file_close(capture_sf5);
                    file_close(capture_sf6);
                    file_close(capture_sf7);
                    report "HDL LoRa SF5/SF6/SF7 full-package golden regression PASS" severity note;
                end if;

                sample_count := sample_count + 1;
            end if;
        end if;
    end process;

    stimulus : process
        procedure wait_clock is
        begin
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;

        procedure enqueue_symbol(
            constant symbol_value : integer;
            constant direction    : std_logic;
            constant begin_packet : std_logic
        ) is
        begin
            while ready_out /= '1' loop
                wait_clock;
            end loop;
            h_in         <= std_logic_vector(to_unsigned(symbol_value, 16));
            direction_in <= direction;
            begin_in     <= begin_packet;
            valid_in     <= '1';
            wait_clock;
            valid_in     <= '0';
            begin_in     <= '0';
        end procedure;

        procedure run_segment(constant segment : integer) is
        begin
            sf_in <= segment_sf_code(segment);
            for k in 6 to SYMBOLS_PER_SEGMENT-1 loop
                if k = 6 then
                    enqueue_symbol(segment_symbols(segment, k), segment_direction(segment, k), '1');
                else
                    enqueue_symbol(segment_symbols(segment, k), segment_direction(segment, k), '0');
                end if;
            end loop;
        end procedure;
    begin
        for i in 1 to 6 loop
            wait_clock;
        end loop;
        rst <= '0';
        wait_clock;
        wait_clock;

        for segment in 0 to SEGMENT_COUNT-1 loop
            run_segment(segment);
        end loop;

        while all_done /= '1' loop
            wait_clock;
        end loop;

        -- Ensure the FIFO/package path does not emit a duplicate trailing symbol.
        for guard in 1 to 64 loop
            wait_clock;
            assert valid_out = '0'
                report "unexpected trailing package sample"
                severity failure;
        end loop;

        report "HDL CI16 captures written for SF5/SF6/SF7 packages" severity note;
        finish;
        wait;
    end process;
end Behavioral;
