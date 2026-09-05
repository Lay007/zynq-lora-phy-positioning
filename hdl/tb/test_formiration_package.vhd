library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

use work.ci16_file_io_pkg.all;

entity test_formiration_package is
end test_formiration_package;

architecture Behavioral of test_formiration_package is
    constant CLK_PERIOD     : time := 10 ns;
    constant SYMBOL_SAMPLES : integer := 2048;
    constant SYMBOL_COUNT   : integer := 10;
    constant TOTAL_SAMPLES  : integer := SYMBOL_COUNT * SYMBOL_SAMPLES;

    signal clk          : std_logic := '0';
    signal valid_in     : std_logic := '0';
    signal rst          : std_logic := '1';
    signal begin_in     : std_logic := '0';
    signal h_in         : std_logic_vector(15 downto 0) := (others => '0');
    signal sf_in        : std_logic_vector(3 downto 0) := b"0010";
    signal bw_in        : std_logic_vector(2 downto 0) := b"000";
    signal direction_in : std_logic := '0';

    signal valid_out    : std_logic;
    signal data_out     : std_logic_vector(31 downto 0);
    signal ready_out    : std_logic;
    signal sample_count : integer range 0 to TOTAL_SAMPLES := 0;
    signal done         : std_logic := '0';

    file fout : byte_file;
begin
    clk <= not clk after CLK_PERIOD / 2;

    writer : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sample_count <= 0;
                done <= '0';
            elsif valid_out = '1' then
                write_ci16_sample(fout, data_out);
                if sample_count = TOTAL_SAMPLES-1 then
                    sample_count <= TOTAL_SAMPLES;
                    done <= '1';
                else
                    sample_count <= sample_count + 1;
                end if;
            end if;
        end if;
    end process;

    formiration_packet_inst : entity work.formiration_package
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
        -- Manual simulator capture. The filename follows the same convention
        -- used by the GHDL/Inspector end-to-end regression. The simulator
        -- writes it into its current working directory.
        file_open(fout, "hdl_sf7_bw125k_fs2000k_package.pcm", WRITE_MODE);

        for i in 1 to 6 loop
            wait_clock;
        end loop;
        rst <= '0';
        wait_clock;
        wait_clock;

        -- Keep this stimulus identical to test_formiration_package_golden:
        -- six automatic h=0 upchirps, then 5 up, 17 up, 64 down, 127 up.
        enqueue_symbol(5,   '0', '1');
        enqueue_symbol(17,  '0', '0');
        enqueue_symbol(64,  '1', '0');
        enqueue_symbol(127, '0', '0');

        while done /= '1' loop
            wait_clock;
        end loop;

        file_close(fout);
        report "HDL CI16 package capture written" severity note;
        finish;
        wait;
    end process;
end Behavioral;
