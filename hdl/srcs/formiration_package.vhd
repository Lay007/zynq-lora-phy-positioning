library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

entity formiration_package is
Port (
    clk             : in std_logic;
    rst             : in std_logic;
    valid_in        : in std_logic;
    begin_in        : in std_logic;
    h_in            : in std_logic_vector(15 downto 0);
    sf_in           : in std_logic_vector(3 downto 0);
    bw_in           : in std_logic_vector(2 downto 0);
    direction_in    : in std_logic;
    ready_out       : out std_logic;
    valid_out       : out std_logic;
    data_out        : out std_logic_vector(31 downto 0)  
);
end formiration_package;

architecture Behavioral of formiration_package is
    --
    COMPONENT fifo_1024_32
    PORT (
        s_axis_aresetn : IN STD_LOGIC;
        s_axis_aclk : IN STD_LOGIC;
        s_axis_tvalid : IN STD_LOGIC;
        s_axis_tready : OUT STD_LOGIC;
        s_axis_tdata : IN STD_LOGIC_VECTOR(23 DOWNTO 0);
        m_axis_tvalid : OUT STD_LOGIC;
        m_axis_tready : IN STD_LOGIC;
        m_axis_tdata : OUT STD_LOGIC_VECTOR(23 DOWNTO 0);
        prog_empty : OUT STD_LOGIC;
        prog_full : OUT STD_LOGIC
    );
    END COMPONENT;
    --
    signal fifo_in_valid    : std_logic := '0';
    signal fifo_in_data     : std_logic_vector(23 downto 0) := (others => '0');
    signal fifo_out_ready   : std_logic := '0';
    signal fifo_out_valid   : std_logic := '0';
    signal fifo_out_data    : std_logic_vector(23 downto 0) := (others => '0');
    signal fifo_in_ready    : std_logic := '0';
    signal fifo_empty       : std_logic := '0';
    signal fifo_full        : std_logic := '0';
    --
    type state_t is (RESET, LOAD_PREAMBULA, LOAD_DATA);
    signal current_state : state_t := RESET;
    --
    signal cnt_load     : unsigned(7 downto 0) := (others => '0');
    signal temp_data_in : std_logic_vector(23 downto 0) := (others => '0');
    signal temp_ready   : std_logic := '0';
    --
    signal ready_form_chirp : std_logic := '0';
    signal valid_form_chirp : std_logic := '0';
    signal data_form_chirp  : std_logic_vector(31 downto 0) := (others => '0');
    --
begin
    --
    with current_state select
        temp_ready <= '1' when LOAD_DATA,
                     '0' when others;
    --
    ready_out <= temp_ready and (not fifo_full);
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
                    when LOAD_PREAMBULA =>
                        if cnt_load = 7 then
                            fifo_in_valid <= '0';
                            cnt_load <= (others => '0');
                            current_state <= LOAD_DATA;
                        elsif cnt_load = 6 then
                            cnt_load <= cnt_load + 1;
                            fifo_in_data <= temp_data_in;
                        else
                            cnt_load <= cnt_load + 1;
                            fifo_in_valid <= '1';
                            fifo_in_data <= x"0000" & temp_data_in(7 downto 1) & '0';
                        end if;
                        --
                    when LOAD_DATA =>
                        if valid_in = '1' and fifo_full = '0' then
                            if begin_in = '1' then
                                temp_data_in <= h_in & sf_in & bw_in & direction_in;
                                current_state <= LOAD_PREAMBULA;
                                fifo_in_valid <= '0';
                            else
                                fifo_in_data <= h_in & sf_in & bw_in & direction_in;
                                fifo_in_valid <= '1';
                            end if;
                        else
                            fifo_in_valid <= '0';    
                        end if;
                end case;     
            end if;
        end if;
    end process;
    --
    fifo_1024_32_inst : fifo_1024_32
    PORT MAP (
        s_axis_aresetn => not rst,
        s_axis_aclk => clk,
        s_axis_tvalid => fifo_in_valid,
        s_axis_tready => fifo_out_ready,
        s_axis_tdata => fifo_in_data,
        m_axis_tvalid => fifo_out_valid,
        m_axis_tready => fifo_in_ready,
        m_axis_tdata => fifo_out_data,
        prog_empty => fifo_empty,
        prog_full => fifo_full
    );
    --
    fifo_in_ready <= ready_form_chirp;
    formiration_chirp_inst : entity work.formiration_chirp
    port map (
        clk             => clk,
        rst             => rst,
        valid_in        => fifo_out_valid,
        h_in            => fifo_out_data(23 downto 8),
        sf_in           => fifo_out_data(7 downto 4),
        bw_in           => fifo_out_data(3 downto 1),
        direction_in    => fifo_out_data(0),
        ready_out       => ready_form_chirp,
        valid_out       => valid_form_chirp,
        data_out        => data_form_chirp 
    );
    --
    valid_out <= valid_form_chirp;
    data_out  <= data_form_chirp;
    --
end Behavioral;