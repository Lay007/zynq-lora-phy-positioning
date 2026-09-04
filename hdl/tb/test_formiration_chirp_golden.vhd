library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
use std.env.all;

entity test_formiration_chirp_golden is
end test_formiration_chirp_golden;

architecture Behavioral of test_formiration_chirp_golden is
    constant CLK_PERIOD         : time := 10 ns;
    constant SYMBOL_SAMPLES     : integer := 2048;
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

        procedure run_case(
            constant symbol_value : integer;
            constant direction    : std_logic
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
            direction_in <= direction;
            valid_in     <= '1';
            wait_clock;
            valid_in     <= '0';

            while sample_index < SYMBOL_SAMPLES loop
                wait_clock;
                if valid_out = '1' then
                    shifted_n := (sample_index + symbol_value * SAMPLES_PER_CHIP)
                        mod SYMBOL_SAMPLES;
                    phase_word := (shifted_n * shifted_n -
                                   SYMBOL_SAMPLES * shifted_n) mod 65536;
                    if direction = '1' then
                        phase_word := (-phase_word) mod 65536;
                    end if;

                    angle := 2.0 * MATH_PI * real(phase_word) / 65536.0;
                    expected_re := q14_half(cos(angle));
                    expected_im := q14_half(sin(angle));
                    actual_re := signed(data_out(31 downto 16));
                    actual_im := signed(data_out(15 downto 0));

                    assert actual_re = expected_re
                        report "real mismatch: symbol=" & integer'image(symbol_value) &
                               " sample=" & integer'image(sample_index) &
                               " got=" & integer'image(to_integer(actual_re)) &
                               " expected=" & integer'image(to_integer(expected_re))
                        severity failure;
                    assert actual_im = expected_im
                        report "imag mismatch: symbol=" & integer'image(symbol_value) &
                               " sample=" & integer'image(sample_index) &
                               " got=" & integer'image(to_integer(actual_im)) &
                               " expected=" & integer'image(to_integer(expected_im))
                        severity failure;

                    sample_index := sample_index + 1;
                end if;
            end loop;

            -- No 2049th sample is allowed.
            for guard in 1 to 8 loop
                wait_clock;
                assert valid_out = '0'
                    report "extra HDL chirp sample after 2048 samples"
                    severity failure;
            end loop;
        end procedure;
    begin
        for i in 1 to 6 loop
            wait_clock;
        end loop;
        rst <= '0';
        wait_clock;
        wait_clock;

        -- MATLAB/C++ representative symbol set plus downchirp checks.
        run_case(0,   '0');
        run_case(1,   '0');
        run_case(17,  '0');
        run_case(63,  '0');
        run_case(127, '0');
        run_case(0,   '1');
        run_case(64,  '1');

        report "HDL LoRa chirp golden regression PASS" severity note;
        finish;
        wait;
    end process;
end Behavioral;
