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
-- Поддерживаемые коды BW. Samples-per-chip L зафиксирован (=16) для любого
-- bw_in — конкретная Fs = BW*16 задаётся тактированием вне этого блока,
-- сам блок оперирует только SF и L, поэтому bw_in лишь проверяется на
-- принадлежность списку известных значений и не входит в арифметику:
-- 000 -> BW 125  кГц (при L=16 соответствует Fs 2.000  МГц)
-- 001 -> BW 250  кГц (Fs 4.000  МГц)
-- 010 -> BW 500  кГц (Fs 8.000  МГц)
-- 011 -> BW 1000 кГц (Fs 16.000 МГц)
-- 100 -> BW 2000 кГц (Fs 32.000 МГц)
-- 101..111 -> зарезервировано, не принимается
--
-- Реализованы SF5/SF6/SF7 (при любом из перечисленных выше bw_in). Это не
-- прихоть: 16-битный аккумулятор фазы (phase_to_sample -> dds_sin_cos_only)
-- при L=16 даёт целочисленный симметричный шаг частоты
-- speed_change = 65536/(2^SF * L^2) только для SF<=7 (SF7 -> 2, SF6 -> 4,
-- SF5 -> 8); при SF8 speed_change=1 не делится на симметричный ±диапазон
-- без half-LSB, а при SF9..SF12 speed_change уже дробный. Коды SF8..SF12
-- распознаются интерфейсом (см. таблицу выше), но пока не формируют выход —
-- как и раньше для любой нереализованной комбинации; расширение потребует
-- отдельного дробного аккумулятора частоты, а не просто параметров.

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

    -- L = samples per chip зафиксирован для всех поддержанных BW-кодов.
    constant SAMPLES_PER_CHIP : integer := 16;

    -- bw_in не входит в арифметику (L фиксирован), но принимается только из
    -- списка известных кодов BW — см. таблицу в шапке файла.
    function bw_code_is_valid(bw_code : std_logic_vector(2 downto 0)) return boolean is
    begin
        case bw_code is
            when b"000" | b"001" | b"010" | b"011" | b"100" =>
                return true;
            when others =>
                return false;
        end case;
    end function;
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
        variable symbol_value      : integer;
        variable phase_value       : integer;
        variable symbol_count      : integer; -- N = 2^SF
        variable speed_change_int  : integer;
        variable up_frequency_int  : integer;
        variable shift_multiplier  : integer; -- speed_change * SAMPLES_PER_CHIP
        variable phase_multiplier  : integer; -- 2^(15-SF)
        variable sf_supported      : boolean;
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
                            sf_supported     := false;
                            symbol_count     := 0;
                            speed_change_int := 0;
                            up_frequency_int := 0;
                            shift_multiplier := 0;
                            phase_multiplier := 0;

                            -- Константы выведены из общей формулы для L=16
                            -- (см. комментарий в шапке файла):
                            --   speed_change = 65536/(2^SF * L^2)
                            --   up_frequency = speed_change*(2^SF*L-1)/2
                            --   shift_multiplier = speed_change * L
                            --   phase_multiplier = 2^(15-SF)
                            -- Точные целые только для SF5..SF7 при L=16.
                            case sf_in is
                                when b"0000" => -- SF5
                                    symbol_count     := 32;
                                    speed_change_int := 8;
                                    up_frequency_int := 2044;
                                    shift_multiplier := 128;
                                    phase_multiplier := 1024;
                                    sf_supported     := true;
                                when b"0001" => -- SF6
                                    symbol_count     := 64;
                                    speed_change_int := 4;
                                    up_frequency_int := 2046;
                                    shift_multiplier := 64;
                                    phase_multiplier := 512;
                                    sf_supported     := true;
                                when b"0010" => -- SF7
                                    symbol_count     := 128;
                                    speed_change_int := 2;
                                    up_frequency_int := 2047;
                                    shift_multiplier := 32;
                                    phase_multiplier := 256;
                                    sf_supported     := true;
                                when others =>
                                    -- SF8..SF12: см. комментарий в шапке файла.
                                    sf_supported := false;
                            end case;

                            if sf_supported and bw_code_is_valid(bw_in) then
                                symbol_value := to_integer(unsigned(h_in));

                                if symbol_value >= 0 and symbol_value < symbol_count then
                                    down_frequency <= to_signed(-up_frequency_int, 16);
                                    up_frequency   <= to_signed(up_frequency_int, 16);
                                    if direction_in = '0' then
                                        speed_change <= to_signed(speed_change_int, 16);
                                    else
                                        speed_change <= to_signed(-speed_change_int, 16);
                                    end if;

                                    current_sample <= (others => '0');
                                    cnt_sample     <= to_unsigned(
                                        symbol_count * SAMPLES_PER_CHIP - 1, 16);
                                    shift_position <= to_signed(
                                        symbol_value * shift_multiplier, 16);

                                    -- MATLAB:
                                    -- m = symbol * L
                                    -- phaseWord = 65536 * (0.5*m^2/(N*L^2) - 0.5*m/L)
                                    --           = phase_multiplier*symbol^2
                                    --             - 32768*symbol  (mod 65536)
                                    phase_value := (phase_multiplier * symbol_value * symbol_value -
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
