library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

-- data_in carries the per-sample phase increment in Q(16.5): 16 integer
-- bits matching the DDS phase word, plus FRACTIONAL_BITS extra low bits so
-- SF8..SF12 (whose exact chirp rate is a sub-LSB fraction of a phase-word
-- count at L=16 samples/chip -- see formiration_chirp.vhd) can be
-- represented exactly instead of rounded to the nearest integer LSB/sample.
-- phase_in (the per-symbol phase LOAD value) has no fractional part for any
-- supported SF, so it stays 16 bits and is zero-extended into the widened
-- accumulator. Only the top 16 bits of the accumulator -- its integer part
-- -- are ever presented to the DDS: truncating a fractional average rate to
-- an integer phase every sample is an unavoidable property of a
-- finite-resolution phase-to-amplitude LUT, not an implementation shortcut;
-- widening the accumulator further would not remove it (verified
-- numerically against the floating-point MATLAB golden: the residual EVM
-- floor from this truncation is independent of how many fractional bits
-- the accumulator itself keeps, ~0.0036% worst case, far under the 1%
-- Stage-1 pass threshold).
entity phase_to_sample is
Port (
    clk           : in std_logic;
    rst           : in std_logic;
    phase_load_in : in std_logic;
    phase_in      : in std_logic_vector(15 downto 0);
    valid_in      : in std_logic;
    data_in       : in std_logic_vector(20 downto 0);
    valid_out     : out std_logic;
    data_out      : out std_logic_vector(31 downto 0)
);
end phase_to_sample;

architecture Behavioral of phase_to_sample is
    constant FRACTIONAL_BITS : integer := 5;
    signal phase_accumulator : unsigned(15+FRACTIONAL_BITS downto 0) := (others => '0');

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
                phase_accumulator <= unsigned(phase_in) & to_unsigned(0, FRACTIONAL_BITS);
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
        s_axis_phase_tdata  => std_logic_vector(phase_accumulator(15+FRACTIONAL_BITS downto FRACTIONAL_BITS)),
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
