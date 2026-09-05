library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity phase_to_sample is
Port (
    clk           : in std_logic;
    rst           : in std_logic;
    phase_load_in : in std_logic;
    phase_in      : in std_logic_vector(15 downto 0);
    valid_in      : in std_logic;
    data_in       : in std_logic_vector(15 downto 0);
    valid_out     : out std_logic;
    data_out      : out std_logic_vector(31 downto 0)
);
end phase_to_sample;

architecture Behavioral of phase_to_sample is
    signal phase_accumulator : unsigned(15 downto 0) := (others => '0');

    COMPONENT dds_sin_cos_only
    PORT (
        aclk                : IN STD_LOGIC;
        aresetn             : IN STD_LOGIC;
        s_axis_phase_tvalid : IN STD_LOGIC;
        s_axis_phase_tdata  : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
        m_axis_data_tvalid  : OUT STD_LOGIC;
        m_axis_data_tdata   : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
    END COMPONENT;

    signal sample_data  : std_logic_vector(31 downto 0) := (others => '0');
    signal sample_valid : std_logic := '0';
begin
    -- DDS получает текущую фазу, а накопитель обновляется для следующего
    -- отсчёта. Поэтому первый sample после phase_load имеет ровно phase_in.
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                phase_accumulator <= (others => '0');
            elsif phase_load_in = '1' then
                phase_accumulator <= unsigned(phase_in);
            elsif valid_in = '1' then
                phase_accumulator <= phase_accumulator + unsigned(data_in);
            end if;
        end if;
    end process;

    dds_sin_cos_only_inst : dds_sin_cos_only
    PORT MAP (
        aclk                => clk,
        aresetn             => not rst,
        s_axis_phase_tvalid => valid_in,
        s_axis_phase_tdata  => std_logic_vector(phase_accumulator),
        m_axis_data_tvalid  => sample_valid,
        m_axis_data_tdata   => sample_data
    );

    valid_out <= sample_valid;

    -- DDS Compiler v6.0 выдаёт cosine в младших 16 битах, sine в старших.
    -- В проекте принят формат {real=cosine, imag=sine}; дополнительно
    -- сохраняем исходное деление амплитуды на 2 (Q14-подобный уровень).
    data_out <= sample_data(15) & sample_data(15 downto 1) &
                sample_data(31) & sample_data(31 downto 17);
end Behavioral;
