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

        -- Общая формула фазы (см. formiration_chirp.vhd): при L=16
        -- phaseWord = phase_coeff*shifted_n^2 - 2048*shifted_n (mod 65536),
        -- phase_coeff = 32768/(2^SF * L^2) = 128/2^SF (целое только для
        -- SF<=7); линейный коэффициент 2048 = 32768/L фиксирован и не
        -- зависит от SF, поскольку L=16 для всех поддержанных BW-кодов.
        procedure run_case(
            constant sf_code       : std_logic_vector(3 downto 0);
            constant symbol_samples: integer;
            constant phase_coeff   : integer;
            constant symbol_value  : integer;
            constant direction     : std_logic
        ) is
            variable sample_index : integer := 0;
            variable shifted_n    : integer;
            variable phase_word   : integer;
            variable angle        : real;
            variable expected_re  : signed(15 downto 0);
            variable expected_im  : signed(15 downto 0);
            variable actual_re    : signed(15 downto 0);
            variable actual_im    : signed(15 downto 0);
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

            while sample_index < symbol_samples loop
                wait_clock;
                if valid_out = '1' then
                    shifted_n := (sample_index + symbol_value * SAMPLES_PER_CHIP)
                        mod symbol_samples;
                    -- Linear term coefficient is 32768/SAMPLES_PER_CHIP = 2048,
                    -- fixed regardless of SF (only equals symbol_samples by
                    -- coincidence for SF7, where symbol_samples is also 2048).
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
            constant sf_code        : std_logic_vector(3 downto 0);
            constant spreading_factor : integer;
            constant phase_coeff    : integer
        ) is
            variable symbol_count   : integer;
            variable symbol_samples : integer;
        begin
            symbol_count   := 2 ** spreading_factor;
            symbol_samples := symbol_count * SAMPLES_PER_CHIP;
            for symbol_value in 0 to symbol_count - 1 loop
                run_case(sf_code, symbol_samples, phase_coeff, symbol_value, '0');
            end loop;
            for symbol_value in 0 to symbol_count - 1 loop
                run_case(sf_code, symbol_samples, phase_coeff, symbol_value, '1');
            end loop;
            report "HDL LoRa SF" & integer'image(spreading_factor) &
                   " all-symbol golden regression PASS" severity note;
        end procedure;
    begin
        for i in 1 to 6 loop
            wait_clock;
        end loop;
        rst <= '0';
        wait_clock;
        wait_clock;

        -- Exhaustive symbol map for every SF the HDL chirp generator
        -- currently implements (see formiration_chirp.vhd header comment
        -- for why SF8..SF12 are not yet included): every cyclic shift is
        -- checked in both directions against the MATLAB/C++ phase
        -- convention.
        run_sf_sweep(b"0000", 5, 4); -- SF5, phase_coeff = 128/32
        run_sf_sweep(b"0001", 6, 2); -- SF6, phase_coeff = 128/64
        run_sf_sweep(b"0010", 7, 1); -- SF7, phase_coeff = 128/128

        -- Rejected sf_in/bw_in combinations: not-yet-implemented SF8, and a
        -- reserved bw_in code paired with an otherwise-valid SF7.
        expect_no_output(b"0011", b"000", "SF8 (not yet implemented)");
        expect_no_output(b"0010", b"101", "reserved bw_in code");

        -- FSM must still work normally afterwards (not left wedged).
        run_case(b"0010", 128 * SAMPLES_PER_CHIP, 1, 0, '0');
        report "HDL LoRa rejected-config and recovery checks PASS" severity note;

        report "HDL LoRa SF5/SF6/SF7 all-symbol golden regression PASS" severity note;
        finish;
        wait;
    end process;
end Behavioral;
