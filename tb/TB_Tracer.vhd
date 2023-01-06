-------------------------------------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: TB_TRACER - Behavioral
-- Project Name: StreamingTraceBuffer
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of the FPGA facing side of the
-- Streaming Trace Buffer.
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;
  use IEEE.MATH_REAL.uniform;
  use IEEE.MATH_REAL.floor;
  use WORK.DTB_PKG.all;

entity TB_TRACER is
end entity TB_TRACER;

architecture TB of TB_TRACER is

  constant CLK_PERIOD                        : time    := 1 ns;           -- ns;
  signal   clk                               : std_logic;

  -- Config signals
  signal rst                                 : std_logic;
  signal en                                  : std_logic;
  signal ntrace                              : std_logic_vector(TRB_MAX_TRACES_BITS - 1 downto 0);
  signal mode                                : std_logic;
  signal delay_event                         : std_logic;
  signal event_pos                           : std_logic_vector(4 downto 0);
  signal trg_event                           : std_logic;
  -- Memory interface signals
  signal ld_i                                : std_logic;
  signal ld_o                                : std_logic;
  signal store                               : std_logic;
  signal data_in, data_out                   : std_logic_vector(TRB_WIDTH - 1 downto 0);
  -- FPGA interface signals.
  signal trace                               : std_logic_vector(TRB_MAX_TRACES-1 downto 0);
  signal trig_i                              : std_logic;
  signal dout                                : std_logic_vector(TRB_MAX_TRACES-1 downto 0);
  signal read                                : std_logic;
  signal trig_o                              : std_logic;

  -- Simulation specific signals
  signal read_addr, write_addr               :  integer range 0 to TRB_DEPTH - 1;
  constant RAM_DEPTH : natural := 2;
  type ram_t is array(0 to RAM_DEPTH -1 ) of std_logic_vector(TRB_WIDTH - 1 downto 0);

  signal ram                                 : ram_t := (others => (others => '0'));

begin

  FPGA_STB_1 : entity work.tracer
    port map (
      RST_I        => rst,
      EN_I         => en,
      MODE_I       => mode,
      NTRACE_I     => ntrace,
      TRG_EVENT_I  => delay_event,
      DATA_I       => data_in,
      LOAD_I       => ld_i,
      EVENT_POS_O  => event_pos,
      TRG_EVENT_O  => trg_event,
      DATA_O       => data_out,
      STORE_O      => store,
      REQ_O       => ld_o,
      FPGA_CLK_I   => clk,
      FPGA_TRIG_I  => trig_i,
      FPGA_TRACE_I => trace,
      FPGA_STREAM_O => dout,
      FPGA_READ_I  => read,
      FPGA_DELAYED_TRIG_O  => trig_o
    );

  CLK_PROCESS : process is
  begin

    clk <= '0';
    wait for CLK_PERIOD / 2;
    clk <= '1';
    wait for CLK_PERIOD / 2;

  end process CLK_PROCESS;

  RAM_PROC : process (clk) is
  begin

    if rising_edge(clk) then
      if (rst = '1') then
        data_in <= (others => '0');
        write_addr <= 0;
        read_addr <= 1;
        ld_i <= '0';
      else
        ld_i <= '0';
        if (store = '1') then
          ram(write_addr) <= data_out;
          write_addr <= (write_addr + 1) mod RAM_DEPTH;
        end if;
        if (ld_o = '1') then
          data_in <= ram(read_addr);
          read_addr <= (read_addr + 1) mod RAM_DEPTH;
          ld_i    <= '1';
        end if;
      end if;
    end if;

  end process RAM_PROC;

  RAND_TRACE : process is

    variable seed1, seed2 : positive := 1;
    variable x            : real;

  begin

    while true loop

      uniform(seed1, seed2, x);
      for i in 0 to TRB_MAX_TRACES-1 loop
        if (x < 0.5) then
          trace(i) <= '0';
        else
          trace(i) <= '1';
        end if;
      end loop;


      wait for CLK_PERIOD;

    end loop;

  end process RAND_TRACE;

  MAIN : process is

  begin

    wait for 1 ps;
    rst <= '1';
    en  <= '0';

    mode        <= '0';
    ntrace      <= "01";
    delay_event <= '0';

    trig_i <= '0';
    wait for CLK_PERIOD;
    rst    <= '0';
    wait for CLK_PERIOD;
    en     <= '1';
    wait for 10 * CLK_PERIOD;
    trig_i <= '1';
    wait for CLK_PERIOD;
    trig_i <= '0';
    wait for CLK_PERIOD;
    trig_i <= '1';
    wait for CLK_PERIOD;
    trig_i <= '0';
    wait for CLK_PERIOD;

    wait for 100 * CLK_PERIOD;
    rst <= '1';
    en  <= '0';

    mode        <= '1';
    ntrace      <= "01";
    delay_event <= '0';

    read <= '0';
    wait for CLK_PERIOD;
    rst    <= '0';
    wait for CLK_PERIOD;
    en     <= '1';
    wait for 3*CLK_PERIOD;
    read <= '1';
    wait for 6*CLK_PERIOD;
    read <= '0';
    wait for 2*CLK_PERIOD;
    read <= '1';

    wait;
  end process MAIN;

end architecture TB;
