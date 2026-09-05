library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ci16_file_io_pkg is
    -- Headerless complex-int16 stream. Each complex sample is stored as
    -- little-endian signed int16 I followed by little-endian signed int16 Q.
    type byte_file is file of character;

    procedure write_ci16_sample(
        file output_file : byte_file;
        data              : std_logic_vector(31 downto 0)
    );
end package;

package body ci16_file_io_pkg is
    procedure write_ci16_sample(
        file output_file : byte_file;
        data              : std_logic_vector(31 downto 0)
    ) is
    begin
        -- HDL bus convention: data[31:16]=I, data[15:0]=Q.
        -- File convention: I_lo, I_hi, Q_lo, Q_hi.
        write(output_file, character'val(to_integer(unsigned(data(23 downto 16)))));
        write(output_file, character'val(to_integer(unsigned(data(31 downto 24)))));
        write(output_file, character'val(to_integer(unsigned(data(7 downto 0)))));
        write(output_file, character'val(to_integer(unsigned(data(15 downto 8)))));
    end procedure;
end package body;
