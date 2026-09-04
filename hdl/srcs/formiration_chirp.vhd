library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
--
--  sf  0000     - 2^5=32
--      0001     - 2^6=64
--      0010     - 2^7=128
--      0011     - 2^8=256
--      0100     - 2^9=512
--      0101     - 2^10=1_024
--      0101     - 2^11=2_048
--      0110     - 2^12=4_096
--
-- bw   000     - 125 kHz

--

entity formiration_chirp is
Port (
    clk             : in std_logic;
    rst             : in std_logic;
    valid_in        : in std_logic;
    h_in            : in std_logic_vector(15 downto 0);
    sf_in           : in std_logic_vector(3 downto 0);
    bw_in           : in std_logic_vector(2 downto 0);
    direction_in    : in std_logic;
    ready_out       : out std_logic;
    valid_out       : out std_logic;
    data_out        : out std_logic_vector(31 downto 0)
);
end formiration_chirp;

architecture Behavioral of formiration_chirp is
    --
    signal retact_valid     : std_logic := '0';
    signal retact_h         : std_logic_vector(15 downto 0) := (others => '0');
    signal retact_sf        : std_logic_vector(3 downto 0) := (others => '0');
    signal retact_bw        : std_logic_vector(2 downto 0) := (others => '0');
    signal retact_direct    : std_logic := '0';
    --
    signal down_frequency   : signed(15 downto 0) := (others => '0');
    signal up_frequency     : signed(15 downto 0) := (others => '0');
    signal current_frequency: signed(15 downto 0) := (others => '0');
    signal speed_change     : signed(15 downto 0) := (others => '0');
    signal cnt_sample       : unsigned(15 downto 0) := (others => '0');
    signal current_sample   : unsigned(15 downto 0) := (others => '0');
    signal shift_position   : signed(15 downto 0) := (others => '0');      
    signal valid_create     : std_logic := '0';
    --
    type state_t is (RESET, LOAD_DATA, SELECTION_OF_PARAMETERS, FORMIRATE_SIGNAL);
    signal current_state : state_t := RESET;
    --
    signal sample_data      : std_logic_vector(31 downto 0) := (others => '0');
    signal sample_valid     : std_logic := '0';
    --
begin
    --
    with current_state select
        ready_out <= '1' when LOAD_DATA,
                     '0' when others;
    --
    with current_state select
        valid_create <= '1' when FORMIRATE_SIGNAL,
                        '0' when others;
    --
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                current_state <= RESET;
            else
                case current_state is
                    when RESET =>
                        current_state <= LOAD_DATA;
                    when LOAD_DATA =>
                         if valid_in = '1' then
                            case sf_in & bw_in is
                                when b"0010" & b"000" =>
                                    down_frequency      <= x"f800";
                                    up_frequency        <= x"0800";
                                    if direction_in = '0' then speed_change <= x"0002"; else speed_change <= x"fffe"; end if;        
                                    current_sample      <= x"0000";
                                    cnt_sample          <= x"0800";
                                    shift_position(15 downto 5) <= signed(h_in(15) & h_in(9 downto 0));
                                    shift_position(4 downto 0) <= (others => '0');
                                when others =>
                            end case;
                            retact_direct   <= direction_in;
                            current_state   <= SELECTION_OF_PARAMETERS;
                        end if;
                    when SELECTION_OF_PARAMETERS =>
                        current_frequency <= down_frequency + shift_position;
                        current_state <= FORMIRATE_SIGNAL;      
                    when FORMIRATE_SIGNAL =>
                        if current_sample < cnt_sample then
                            current_sample <= current_sample + 1;
                        else
                            current_state <= LOAD_DATA;
                            current_sample <= (others => '0');
                        end if;
                        --
                        if current_frequency >= up_frequency and retact_direct = '0' then
                            current_frequency <= down_frequency;
                        elsif current_frequency <= down_frequency and retact_direct = '1' then
                            current_frequency <= up_frequency;
                        else
                            current_frequency <= current_frequency + speed_change;      
                        end if;
                        --
               end case; 
            end if;
        end if;
    end process;
    --
    phase_to_sample_inst : entity work.phase_to_sample
    port map (
        clk         => clk,
        rst         => rst,
        valid_in    => valid_create,
        data_in     => std_logic_vector(current_frequency),
        valid_out   => sample_valid,
        data_out    => sample_data
    );
    --
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                valid_out   <= '0';
                data_out    <= (others => '0');
            else
                valid_out   <= sample_valid;
                data_out    <= sample_data;
            end if;
        end if;
    end process;
    --
end Behavioral;