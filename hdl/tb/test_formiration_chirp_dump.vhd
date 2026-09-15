library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.env.all;

use work.ci16_file_io_pkg.all;

-- Dumps individual Stage-1 CSS symbols to headerless CI16 PCM files using the
-- naming convention documented in hdl/README.md
-- (hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_chirp-h<H>-<dir>.pcm), so they can be
-- opened directly in LoRa PHY Inspector (hdl/signal/open_in_inspector.m).
-- This exercises the generalized formiration_chirp.vhd (SF5/SF6/SF7) beyond
-- the bit-exact assertions in test_formiration_chirp_golden.vhd, producing
-- real captures for independent, human-driven inspection.
entity test_formiration_chirp_dump is
end test_formiration_chirp_dump;

architecture Behavioral of test_formiration_chirp_dump is
    constant CLK_PERIOD       : time := 10 ns;
    constant SAMPLES_PER_CHIP : integer := 16;

    signal clk          : std_logic := '0';
    signal rst          : std_logic := '1';
    signal valid_in     : std_logic := '0';
    signal h_in         : std_logic_vector(15 downto 0) := (others => '0');
    signal sf_in        : std_logic_vector(3 downto 0) := b"0000";
    signal bw_in        : std_logic_vector(2 downto 0) := b"010";
    signal direction_in : std_logic := '0';
    signal ready_out    : std_logic;
    signal valid_out    : std_logic;
    signal data_out     : std_logic_vector(31 downto 0);
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

        -- Dumps one symbol to <file_name>; SAMPLE_COUNT samples are captured.
        procedure dump_symbol(
            constant symbol_value : integer;
            constant sample_count : integer;
            constant file_name    : string
        ) is
            file output_file : byte_file open write_mode is file_name;
            variable sample_index : integer := 0;
        begin
            while ready_out /= '1' loop
                wait_clock;
            end loop;

            h_in     <= std_logic_vector(to_unsigned(symbol_value, 16));
            valid_in <= '1';
            wait_clock;
            valid_in <= '0';

            while sample_index < sample_count loop
                wait_clock;
                if valid_out = '1' then
                    write_ci16_sample(output_file, data_out);
                    sample_index := sample_index + 1;
                end if;
            end loop;

            file_close(output_file);
        end procedure;
    begin
        for i in 1 to 6 loop
            wait_clock;
        end loop;
        rst <= '0';
        wait_clock;
        wait_clock;

        -- SF5 / BW500k / Fs8000k (L=16, symbolSamples=512): the exact
        -- geometry previously exercised as a hand-made Inspector fixture in
        -- tmp/signals/hdl_sf5_bw500k_fs8000k_chirp-h*-up.pcm.
        sf_in        <= b"0000";
        bw_in        <= b"010";
        direction_in <= '0';
        dump_symbol(0, 512, "build/ghdl-lora/hdl_sf5_bw500k_fs8000k_chirp-h0-up.pcm");
        dump_symbol(1, 512, "build/ghdl-lora/hdl_sf5_bw500k_fs8000k_chirp-h1-up.pcm");
        dump_symbol(2, 512, "build/ghdl-lora/hdl_sf5_bw500k_fs8000k_chirp-h2-up.pcm");
        dump_symbol(3, 512, "build/ghdl-lora/hdl_sf5_bw500k_fs8000k_chirp-h3-up.pcm");
        dump_symbol(4, 512, "build/ghdl-lora/hdl_sf5_bw500k_fs8000k_chirp-h4-up.pcm");

        report "HDL LoRa SF5 chirp dump complete" severity note;
        finish;
        wait;
    end process;
end Behavioral;
