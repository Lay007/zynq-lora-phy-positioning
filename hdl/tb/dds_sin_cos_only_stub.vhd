library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

-- Test-only behavioral replacement for Xilinx DDS Compiler configured as
-- SIN/COS LUT only. The production design still uses hdl/ip/dds_sin_cos_only.xci.
-- DDS Compiler v6.0 packs cosine in the low 16 bits and sine in the high 16 bits.
entity dds_sin_cos_only is
Port (
    aclk                : in std_logic;
    aresetn             : in std_logic;
    s_axis_phase_tvalid : in std_logic;
    s_axis_phase_tdata  : in std_logic_vector(15 downto 0);
    m_axis_data_tvalid  : out std_logic;
    m_axis_data_tdata   : out std_logic_vector(31 downto 0)
);
end dds_sin_cos_only;

architecture Behavioral of dds_sin_cos_only is
begin
    process(aclk)
        variable phase_value  : integer;
        variable angle        : real;
        variable sine_value   : integer;
        variable cosine_value : integer;
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                m_axis_data_tvalid <= '0';
                m_axis_data_tdata  <= (others => '0');
            else
                m_axis_data_tvalid <= s_axis_phase_tvalid;
                if s_axis_phase_tvalid = '1' then
                    phase_value := to_integer(unsigned(s_axis_phase_tdata));
                    angle := 2.0 * MATH_PI * real(phase_value) / 65536.0;
                    cosine_value := integer(round(cos(angle) * 32767.0));
                    sine_value   := integer(round(sin(angle) * 32767.0));
                    m_axis_data_tdata <=
                        std_logic_vector(to_signed(sine_value, 16)) &
                        std_logic_vector(to_signed(cosine_value, 16));
                end if;
            end if;
        end if;
    end process;
end Behavioral;
