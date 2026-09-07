library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Test-only behavioral replacement for the Xilinx AXI-Stream FIFO used by
-- formiration_package. The production design still uses fifo_1024_32.xci.
entity fifo_1024_32 is
Port (
    s_axis_aresetn : in  std_logic;
    s_axis_aclk    : in  std_logic;
    s_axis_tvalid  : in  std_logic;
    s_axis_tready  : out std_logic;
    s_axis_tdata   : in  std_logic_vector(23 downto 0);
    m_axis_tvalid  : out std_logic;
    m_axis_tready  : in  std_logic;
    m_axis_tdata   : out std_logic_vector(23 downto 0);
    prog_empty     : out std_logic;
    prog_full      : out std_logic
);
end fifo_1024_32;

architecture Behavioral of fifo_1024_32 is
    constant DEPTH : integer := 1024;
    constant PROG_FULL_THRESHOLD : integer := 900;
    type memory_t is array (0 to DEPTH-1) of std_logic_vector(23 downto 0);
    signal memory : memory_t := (others => (others => '0'));
    signal write_pointer : integer range 0 to DEPTH-1 := 0;
    signal read_pointer  : integer range 0 to DEPTH-1 := 0;
    signal count         : integer range 0 to DEPTH := 0;
begin
    s_axis_tready <= '1' when count < DEPTH else '0';
    m_axis_tvalid <= '1' when count > 0 else '0';
    m_axis_tdata  <= memory(read_pointer) when count > 0 else (others => '0');
    prog_empty    <= '1' when count = 0 else '0';
    prog_full     <= '1' when count >= PROG_FULL_THRESHOLD else '0';

    process(s_axis_aclk)
        variable do_write : boolean;
        variable do_read  : boolean;
    begin
        if rising_edge(s_axis_aclk) then
            if s_axis_aresetn = '0' then
                write_pointer <= 0;
                read_pointer  <= 0;
                count         <= 0;
            else
                do_write := s_axis_tvalid = '1' and count < DEPTH;
                do_read  := m_axis_tready = '1' and count > 0;

                if do_write then
                    memory(write_pointer) <= s_axis_tdata;
                    if write_pointer = DEPTH-1 then
                        write_pointer <= 0;
                    else
                        write_pointer <= write_pointer + 1;
                    end if;
                end if;

                if do_read then
                    if read_pointer = DEPTH-1 then
                        read_pointer <= 0;
                    else
                        read_pointer <= read_pointer + 1;
                    end if;
                end if;

                if do_write and not do_read then
                    count <= count + 1;
                elsif do_read and not do_write then
                    count <= count - 1;
                end if;
            end if;
        end if;
    end process;
end Behavioral;
