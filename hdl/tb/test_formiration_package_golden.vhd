library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
use std.env.all;

entity test_formiration_package_golden is
end test_formiration_package_golden;

architecture Behavioral of test_formiration_package_golden is
    constant CLK_PERIOD       : time := 10 ns;
    constant SYMBOL_SAMPLES   : integer := 2048;
    constant SAMPLES_PER_CHIP : integer := 16;
    constant SYMBOL_COUNT     : integer := 10;
    constant TOTAL_SAMPLES    : integer := SYMBOL_COUNT * SYMBOL_SAMPLES;

    type integer_array_t is array (natural range <>) of integer;
    constant EXPECTED_SYMBOLS : integer_array_t(0 to SYMBOL_COUNT-1) :=
        (0, 0, 0, 0, 0, 0, 5, 17, 64, 127);
    constant EXPECTED_DIRECTIONS : std_logic_vector(0 to SYMBOL_COUNT-1) :=
        "0000000010";

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
    signal sample_count : integer range 0 to TOTAL_SAMPLES := 0;
    signal done         : std_logic := '0';

    function q14_half(value : real) return signed is
        variable full_scale : signed(15 downto 0);
    begin
        full_scale := to_signed(integer(round(value * 32767.0)), 16);
        return shift_right(full_scale, 1);
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

    monitor : process(clk)
        variable symbol_index : integer;
        variable sample_index : integer;
        variable symbol_value : integer;
        variable direction    : std_logic;
        variable shifted_n    : integer;
        variable phase_word   : integer;
        variable angle        : real;
        variable expected_re  : signed(15 downto 0);
        variable expected_im  : signed(15 downto 0);
        variable actual_re    : signed(15 downto 0);
        variable actual_im    : signed(15 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sample_count <= 0;
                done <= '0';
            elsif valid_out = '1' then
                assert sample_count < TOTAL_SAMPLES
                    report "extra sample after expected package waveform"
                    severity failure;

                symbol_index := sample_count / SYMBOL_SAMPLES;
                sample_index := sample_count mod SYMBOL_SAMPLES;
                symbol_value := EXPECTED_SYMBOLS(symbol_index);
                direction := EXPECTED_DIRECTIONS(symbol_index);

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
                    report "package real mismatch: output_symbol=" &
                           integer'image(symbol_index) &
                           " h=" & integer'image(symbol_value) &
                           " sample=" & integer'image(sample_index)
                    severity failure;
                assert actual_im = expected_im
                    report "package imag mismatch: output_symbol=" &
                           integer'image(symbol_index) &
                           " h=" & integer'image(symbol_value) &
                           " sample=" & integer'image(sample_index)
                    severity failure;

                if sample_count = TOTAL_SAMPLES-1 then
                    sample_count <= TOTAL_SAMPLES;
                    done <= '1';
                else
                    sample_count <= sample_count + 1;
                end if;
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
    begin
        for i in 1 to 6 loop
            wait_clock;
        end loop;
        rst <= '0';
        wait_clock;
        wait_clock;

        -- Current formiration_package contract:
        -- begin_in inserts six h=0 upchirps, then forwards the first symbol.
        enqueue_symbol(5,   '0', '1');
        enqueue_symbol(17,  '0', '0');
        enqueue_symbol(64,  '1', '0');
        enqueue_symbol(127, '0', '0');

        while done /= '1' loop
            wait_clock;
        end loop;

        -- Ensure the FIFO/package path does not emit a duplicate trailing symbol.
        for guard in 1 to 64 loop
            wait_clock;
            assert valid_out = '0'
                report "unexpected trailing package sample"
                severity failure;
        end loop;

        report "HDL LoRa full-package golden regression PASS" severity note;
        finish;
        wait;
    end process;
end Behavioral;
