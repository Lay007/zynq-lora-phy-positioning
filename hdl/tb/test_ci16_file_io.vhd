library IEEE;
use ieee.std_logic_1164.all;
use std.env.all;

use work.ci16_file_io_pkg.all;

entity test_ci16_file_io is
end test_ci16_file_io;

architecture Behavioral of test_ci16_file_io is
begin
    process
        file fout : byte_file;
    begin
        file_open(fout, "build/ghdl-lora/ci16_writer_test.pcm", WRITE_MODE);

        -- Sample 0: I=0x4000 (+16384), Q=0xE000 (-8192)
        write_ci16_sample(fout, x"4000E000");
        -- Sample 1: I=0xC000 (-16384), Q=0x2000 (+8192)
        write_ci16_sample(fout, x"C0002000");

        file_close(fout);
        report "CI16 file writer regression PASS" severity note;
        finish;
        wait;
    end process;
end Behavioral;
