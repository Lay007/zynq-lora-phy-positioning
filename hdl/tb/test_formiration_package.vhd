library IEEE;
use ieee.std_logic_1164.ALL;
use ieee.std_logic_arith.all;

entity test_formiration_package is
end test_formiration_package;

architecture Behavioral of test_formiration_package is
    --
    signal clk                  : std_logic := '0';
    signal valid_in             : std_logic := '0';
    signal rst                  : std_logic := '0';
    signal begin_in             : std_logic := '0';
    signal h_in                 : std_logic_vector(15 downto 0) := (others => '0');
    signal sf_in                : std_logic_vector(3 downto 0) := (others => '0');
    signal bw_in                : std_logic_vector(2 downto 0) := (others => '0');
    signal direction_in         : std_logic := '0';
    --
    signal valid_out    : std_logic := '0';
    signal data_out     : std_logic_vector(31 downto 0) := (others => '0');
    signal ready_out    : std_logic := '0';
    --
    constant clk_period : time := 10 ns;
    type int_file is file of integer;
    --
    file fout : int_file;
    --
    signal cnt_chirps : integer := 0;
    --
begin
    --
    clk_process :process
    begin
	   clk <= '0';
	   wait for clk_period/2;
	   clk <= '1';
	   wait for clk_period/2;
    end process;    
    --
    process(clk)
		variable dout: integer;
		variable dat: std_logic_vector(31 downto 0);
   begin
		if (rising_edge(clk)) then
		  if rst = '1' then
		  else
			if valid_out = '1' then
				dat := data_out;
				dout := conv_integer(signed(dat));
				--
				write(fout, dout);
			end if;
		  end if;    	
		end if;
	end process;   
    --
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                    valid_in        <= '1';
                    begin_in        <= '1';
                    h_in            <= (others => '0');
                    sf_in           <= b"0010";
                    bw_in           <= b"000";
                    direction_in    <= '0';
            else
                if valid_in = '1' and ready_out = '1' then
                    cnt_chirps <= cnt_chirps + 1;
                    begin_in <= '0';
                end if; 
                
                case cnt_chirps  is
                    when 0 =>
                        h_in <= x"0000";
                        direction_in <= '0';
                    when 1 =>
                        h_in <= x"0010";
                        direction_in <= '0';
                    when 2 =>
                        h_in <= x"0040";
                        direction_in <= '1';
                    when 3 =>
                        h_in <= x"0010";
                        direction_in <= '1';
                    when others =>
                        valid_in <= '0';
                end case;
            end if;
        end if;
    end process;
    --
    formiration_packet_inst : entity work.formiration_package 
    port map (
        clk             => clk,
        rst             => rst,
        valid_in        => valid_in,
        begin_in        => begin_in,
        h_in            => h_in,
        sf_in           => sf_in,
        bw_in           => bw_in,
        direction_in    => direction_in,
        ready_out       => ready_out,
        valid_out       => valid_out,
        data_out        => data_out
    );
    
    --
    stim_proc: process
    begin		
		file_open(fout, "D:\signal\sim\output_hdl.pcm", WRITE_MODE);
		-- hold reset state for 100 ns.
        rst <= '1';
        wait for 10000 ns;
        rst <= '0';	
        wait for clk_period*10;	
        -- insert stimulus here
	    wait for 15000000 us;		
		file_close(fout);
        assert false report "time is out, simulation ended" severity failure;
    end process;

    --
end Behavioral;
