library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

-- Поддерживаемые коды SF:
-- 0000 -> SF5
-- 0001 -> SF6
-- 0010 -> SF7
-- 0011 -> SF8
-- 0100 -> SF9
-- 0101 -> SF10
-- 0110 -> SF11
-- 0111 -> SF12
--
-- На текущем этапе реализован только режим SF7 / BW=125 кГц / L=16,
-- то есть Fs=2 МГц. Для него один символ содержит 128*16=2048 отсчётов.

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
    signal retact_direct     : std_logic := '0';

    -- Для MATLAB reference_chirp при SF7/L16 фазовый шаг между соседними
    -- отсчётами является нечётной последовательностью -2047,-2045,...,+2047.
    signal down_frequency    : signed(15 downto 0) := (others => '0');
    signal up_frequency      : signed(15 downto 0) := (others => '0');
    signal current_frequency : signed(15 downto 0) := (others => '0');
    signal speed_change      : signed(15 downto 0) := (others => '0');
    signal cnt_sample        : unsigned(15 downto 0) := (others => '0');
    signal current_sample    : unsigned(15 downto 0) := (others => '0');
    signal shift_position    : signed(15 downto 0) := (others => '0');
    signal phase_start       : unsigned(15 downto 0) := (others => '0');
    signal phase_load        : std_logic := '0';
    signal valid_create      : std_logic := '0';

    type state_t is (RESET, LOAD_DATA, SELECTION_OF_PARAMETERS, FORMIRATE_SIGNAL);
    signal current_state : state_t := RESET;

    signal sample_data       : std_logic_vector(31 downto 0) := (others => '0');
    signal sample_valid      : std_logic := '0';
begin
    with current_state select
        ready_out <= '1' when LOAD_DATA,
                     '0' when others;

    with current_state select
        valid_create <= '1' when FORMIRATE_SIGNAL,
                        '0' when others;

    with current_state select
        phase_load <= '1' when SELECTION_OF_PARAMETERS,
                      '0' when others;

    process(clk)
        variable symbol_value : integer;
        variable phase_value  : integer;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                current_state     <= RESET;
                retact_direct     <= '0';
                down_frequency    <= (others => '0');
                up_frequency      <= (others => '0');
                current_frequency <= (others => '0');
                speed_change      <= (others => '0');
                cnt_sample        <= (others => '0');
                current_sample    <= (others => '0');
                shift_position    <= (others => '0');
                phase_start       <= (others => '0');
            else
                case current_state is
                    when RESET =>
                        current_state <= LOAD_DATA;

                    when LOAD_DATA =>
                        if valid_in = '1' then
                            -- Пока поддержан только SF7/BW125 при Fs=2 МГц (L=16).
                            if sf_in = b"0010" and bw_in = b"000" then
                                symbol_value := to_integer(unsigned(h_in));

                                if symbol_value >= 0 and symbol_value < 128 then
                                    down_frequency <= to_signed(-2047, 16);
                                    up_frequency   <= to_signed(2047, 16);
                                    if direction_in = '0' then
                                        speed_change <= to_signed(2, 16);
                                    else
                                        speed_change <= to_signed(-2, 16);
                                    end if;

                                    current_sample <= (others => '0');
                                    cnt_sample     <= to_unsigned(2047, 16);
                                    shift_position <= to_signed(symbol_value * 32, 16);

                                    -- MATLAB:
                                    -- m = symbol * L = symbol * 16
                                    -- phaseWord = 65536 * (0.5*m^2/(128*16^2) - 0.5*m/16)
                                    --           = 256*symbol^2 - 32768*symbol  (mod 65536)
                                    phase_value := (256 * symbol_value * symbol_value -
                                                    32768 * symbol_value) mod 65536;
                                    if direction_in = '1' then
                                        phase_value := (-phase_value) mod 65536;
                                    end if;
                                    phase_start <= to_unsigned(phase_value, 16);

                                    retact_direct <= direction_in;
                                    current_state <= SELECTION_OF_PARAMETERS;
                                end if;
                            end if;
                        end if;

                    when SELECTION_OF_PARAMETERS =>
                        if retact_direct = '0' then
                            current_frequency <= down_frequency + shift_position;
                        else
                            current_frequency <= up_frequency - shift_position;
                        end if;
                        current_state <= FORMIRATE_SIGNAL;

                    when FORMIRATE_SIGNAL =>
                        if current_sample < cnt_sample then
                            current_sample <= current_sample + 1;
                        else
                            current_state  <= LOAD_DATA;
                            current_sample <= (others => '0');
                        end if;

                        if retact_direct = '0' then
                            if current_frequency >= up_frequency then
                                current_frequency <= down_frequency;
                            else
                                current_frequency <= current_frequency + speed_change;
                            end if;
                        else
                            if current_frequency <= down_frequency then
                                current_frequency <= up_frequency;
                            else
                                current_frequency <= current_frequency + speed_change;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

    phase_to_sample_inst : entity work.phase_to_sample
    port map (
        clk           => clk,
        rst           => rst,
        phase_load_in => phase_load,
        phase_in      => std_logic_vector(phase_start),
        valid_in      => valid_create,
        data_in       => std_logic_vector(current_frequency),
        valid_out     => sample_valid,
        data_out      => sample_data
    );

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                valid_out <= '0';
                data_out  <= (others => '0');
            else
                valid_out <= sample_valid;
                data_out  <= sample_data;
            end if;
        end if;
    end process;
end Behavioral;
