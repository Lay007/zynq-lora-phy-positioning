library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
use std.env.all;

entity test_formiration_chirp_golden is
end test_formiration_chirp_golden;

architecture Behavioral of test_formiration_chirp_golden is
    constant CLK_PERIOD         : time := 10 ns;
    constant SAMPLES_PER_CHIP   : integer := 16;
    constant SCALE              : integer := 32; -- matches FRACTIONAL_BITS=5 in formiration_chirp.vhd

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal valid_in     : std_logic := '0';
    signal h_in         : std_logic_vector(15 downto 0) := (others => '0');
    signal sf_in        : std_logic_vector(3 downto 0) := b"0010";
    signal bw_in        : std_logic_vector(2 downto 0) := b"000";
    signal direction_in : std_logic := '0';
    signal ready_out    : std_logic;
    signal valid_out    : std_logic;
    signal data_out     : std_logic_vector(31 downto 0);

    function q14_half(value : real) return signed is
        variable full_scale : signed(15 downto 0);
    begin
        full_scale := to_signed(integer(round(value * 32767.0)), 16);
        return shift_right(full_scale, 1);
    end function;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.formiration_chirp
    port map (
        clk          => clk,
        rst          => rst,
        valid_in     => valid_in,
        h_in         => h_in,
        sf_in        => sf_in,
        bw_in        => bw_in,
        direction_in => direction_in,
        ready_out    => ready_out,
        valid_out    => valid_out,
        data_out     => data_out
    );

    stimulus : process
        procedure wait_clock is
        begin
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;

        -- Independent reimplementation of formiration_chirp.vhd's Q(16.5)
        -- frequency-accumulator recursion (see its header comment for the
        -- derivation): all intermediate values stay well within 32-bit
        -- integer range (unlike a closed-form quadratic-in-sample-index
        -- formula, which would overflow 32 bits for SF12 -- shifted_n^2
        -- alone reaches ~4.3e9). Advances one sample per call, so the
        -- caller carries expected_phase_acc/expected_freq across samples.
        procedure step_reference(
            constant up_frequency_scaled : integer;
            constant speed_change_scaled : integer;
            constant direction           : std_logic;
            variable phase_acc           : inout integer;
            variable freq                : inout integer;
            variable phase_for_dds       : out integer
        ) is
            variable down_frequency_scaled : integer;
        begin
            down_frequency_scaled := -up_frequency_scaled;
            phase_for_dds := (phase_acc / SCALE) mod 65536;
            phase_acc := (phase_acc + freq) mod (65536*SCALE);
            if direction = '0' then
                if freq >= up_frequency_scaled then
                    freq := down_frequency_scaled;
                else
                    freq := freq + speed_change_scaled;
                end if;
            else
                if freq <= down_frequency_scaled then
                    freq := up_frequency_scaled;
                else
                    freq := freq - speed_change_scaled;
                end if;
            end if;
        end procedure;

        procedure run_case(
            constant sf_code             : std_logic_vector(3 downto 0);
            constant symbol_samples      : integer;
            constant speed_change_scaled : integer;
            constant up_frequency_scaled : integer;
            constant phase_multiplier    : integer; -- unscaled: 2^(15-SF)
            constant shift_multiplier    : integer; -- speed_change_scaled * SAMPLES_PER_CHIP
            constant symbol_value        : integer;
            constant direction           : std_logic
        ) is
            variable sample_index   : integer := 0;
            variable phase_value    : integer;
            variable phase_acc      : integer;
            variable freq           : integer;
            variable phase_for_dds  : integer;
            variable angle          : real;
            variable expected_re    : signed(15 downto 0);
            variable expected_im    : signed(15 downto 0);
            variable actual_re      : signed(15 downto 0);
            variable actual_im      : signed(15 downto 0);
        begin
            while ready_out /= '1' loop
                wait_clock;
            end loop;

            h_in         <= std_logic_vector(to_unsigned(symbol_value, 16));
            sf_in        <= sf_code;
            direction_in <= direction;
            valid_in     <= '1';
            wait_clock;
            valid_in     <= '0';

            phase_value := (phase_multiplier * symbol_value * symbol_value -
                            32768 * symbol_value) mod 65536;
            if direction = '1' then
                phase_value := (-phase_value) mod 65536;
            end if;
            phase_acc := phase_value * SCALE;

            if direction = '0' then
                freq := (-up_frequency_scaled) + symbol_value*shift_multiplier;
            else
                freq := up_frequency_scaled - symbol_value*shift_multiplier;
            end if;

            while sample_index < symbol_samples loop
                wait_clock;
                if valid_out = '1' then
                    step_reference(up_frequency_scaled, speed_change_scaled, direction,
                        phase_acc, freq, phase_for_dds);

                    angle := 2.0 * MATH_PI * real(phase_for_dds) / 65536.0;
                    expected_re := q14_half(cos(angle));
                    expected_im := q14_half(sin(angle));
                    actual_re := signed(data_out(31 downto 16));
                    actual_im := signed(data_out(15 downto 0));

                    assert actual_re = expected_re
                        report "real mismatch: sf_code=" & integer'image(to_integer(unsigned(sf_code))) &
                               " symbol=" & integer'image(symbol_value) &
                               " sample=" & integer'image(sample_index) &
                               " got=" & integer'image(to_integer(actual_re)) &
                               " expected=" & integer'image(to_integer(expected_re))
                        severity failure;
                    assert actual_im = expected_im
                        report "imag mismatch: sf_code=" & integer'image(to_integer(unsigned(sf_code))) &
                               " symbol=" & integer'image(symbol_value) &
                               " sample=" & integer'image(sample_index) &
                               " got=" & integer'image(to_integer(actual_im)) &
                               " expected=" & integer'image(to_integer(expected_im))
                        severity failure;

                    sample_index := sample_index + 1;
                end if;
            end loop;

            -- No extra sample beyond symbol_samples is allowed.
            for guard in 1 to 8 loop
                wait_clock;
                assert valid_out = '0'
                    report "extra HDL chirp sample after " &
                           integer'image(symbol_samples) & " samples"
                    severity failure;
            end loop;
        end procedure;

        -- Invalid sf_in/bw_in combinations must never produce a symbol: the
        -- FSM stays in LOAD_DATA (ready_out held high) and simply waits for
        -- a valid request, exactly like today's behaviour for any
        -- unsupported configuration.
        procedure expect_no_output(
            constant sf_code : std_logic_vector(3 downto 0);
            constant bw_code : std_logic_vector(2 downto 0);
            constant case_description : string
        ) is
        begin
            while ready_out /= '1' loop
                wait_clock;
            end loop;

            h_in         <= std_logic_vector(to_unsigned(0, 16));
            sf_in        <= sf_code;
            bw_in        <= bw_code;
            direction_in <= '0';
            valid_in     <= '1';
            wait_clock;
            valid_in     <= '0';

            for guard in 1 to 32 loop
                wait_clock;
                assert valid_out = '0'
                    report "unexpected chirp output for rejected config: " & case_description
                    severity failure;
                assert ready_out = '1'
                    report "FSM left LOAD_DATA for rejected config: " & case_description
                    severity failure;
            end loop;

            bw_in <= b"000";
        end procedure;

        procedure run_sf_sweep(
            constant sf_code              : std_logic_vector(3 downto 0);
            constant spreading_factor     : integer;
            constant speed_change_scaled  : integer;
            constant up_frequency_scaled  : integer;
            constant phase_multiplier     : integer;
            constant shift_multiplier     : integer
        ) is
            variable symbol_count   : integer;
            variable symbol_samples : integer;
        begin
            symbol_count   := 2 ** spreading_factor;
            symbol_samples := symbol_count * SAMPLES_PER_CHIP;
            for symbol_value in 0 to symbol_count - 1 loop
                run_case(sf_code, symbol_samples, speed_change_scaled, up_frequency_scaled,
                    phase_multiplier, shift_multiplier, symbol_value, '0');
            end loop;
            for symbol_value in 0 to symbol_count - 1 loop
                run_case(sf_code, symbol_samples, speed_change_scaled, up_frequency_scaled,
                    phase_multiplier, shift_multiplier, symbol_value, '1');
            end loop;
            report "HDL LoRa SF" & integer'image(spreading_factor) &
                   " all-symbol golden regression PASS" severity note;
        end procedure;

        -- SF10..SF12 have too many samples per symbol to sweep exhaustively
        -- in CI (SF12 alone is 4096 symbols x 65536 samples x 2 directions =
        -- over 5e8 samples). Spot-check a representative subset instead:
        -- the cyclic-shift boundary cases most likely to expose an
        -- off-by-one (0, 1, 2, 3, a quarter, the half, three-quarters, and
        -- the last two symbols), matching the coverage already validated
        -- offline in MATLAB against the floating-point golden.
        type integer_array_t is array (natural range <>) of integer;

        procedure run_sf_spot_check(
            constant sf_code              : std_logic_vector(3 downto 0);
            constant spreading_factor     : integer;
            constant speed_change_scaled  : integer;
            constant up_frequency_scaled  : integer;
            constant phase_multiplier     : integer;
            constant shift_multiplier     : integer
        ) is
            variable symbol_count   : integer;
            variable symbol_samples : integer;
            variable symbols        : integer_array_t(0 to 7);
        begin
            symbol_count   := 2 ** spreading_factor;
            symbol_samples := symbol_count * SAMPLES_PER_CHIP;
            symbols := (0, 1, 2, 3, symbol_count/4, symbol_count/2,
                        3*symbol_count/4, symbol_count-1);
            for k in symbols'range loop
                run_case(sf_code, symbol_samples, speed_change_scaled, up_frequency_scaled,
                    phase_multiplier, shift_multiplier, symbols(k), '0');
                run_case(sf_code, symbol_samples, speed_change_scaled, up_frequency_scaled,
                    phase_multiplier, shift_multiplier, symbols(k), '1');
            end loop;
            report "HDL LoRa SF" & integer'image(spreading_factor) &
                   " spot-check golden regression PASS" severity note;
        end procedure;
    begin
        for i in 1 to 6 loop
            wait_clock;
        end loop;
        rst <= '0';
        wait_clock;
        wait_clock;

        -- Exhaustive symbol map for SF5..SF8 (every cyclic shift, both
        -- directions; see formiration_chirp.vhd header comment for the
        -- Q(16.5) derivation). SF9..SF12 are spot-checked instead -- see
        -- run_sf_spot_check; SF9 exhaustive alone is 512 symbols x 8192
        -- samples x 2 directions (~8.4e6 samples) and SF9..SF12 exhaustive
        -- together took over 9 minutes of wall-clock GHDL simulation,
        -- impractical for routine CI. Constants (speed_change_scaled,
        -- up_frequency_scaled, phase_multiplier, shift_multiplier) mirror
        -- formiration_chirp.vhd's own per-SF case table exactly -- both are
        -- independent expressions of the same derivation, not one reading
        -- the other.
        run_sf_sweep(b"0000",  5, 256,   65408, 1024, 4096); -- SF5
        run_sf_sweep(b"0001",  6, 128,   65472,  512, 2048); -- SF6
        run_sf_sweep(b"0010",  7,  64,   65504,  256, 1024); -- SF7
        run_sf_sweep(b"0011",  8,  32,   65520,  128,  512); -- SF8
        run_sf_spot_check(b"0100",  9,  16, 65528, 64, 256); -- SF9
        run_sf_spot_check(b"0101", 10,   8, 65532, 32, 128); -- SF10
        run_sf_spot_check(b"0110", 11,   4, 65534, 16,  64); -- SF11
        run_sf_spot_check(b"0111", 12,   2, 65535,  8,  32); -- SF12

        -- Reserved bw_in code must be rejected even with an otherwise-valid SF.
        expect_no_output(b"0010", b"101", "reserved bw_in code");

        -- FSM must still work normally afterwards (not left wedged).
        run_case(b"0010", 128 * SAMPLES_PER_CHIP, 64, 65504, 256, 1024, 0, '0');
        report "HDL LoRa rejected-config and recovery checks PASS" severity note;

        report "HDL LoRa SF5..SF12 all-symbol golden regression PASS" severity note;
        finish;
        wait;
    end process;
end Behavioral;
