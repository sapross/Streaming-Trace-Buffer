-------------------------------------------------
-- Author: Stephan Proß
--
-- Create Date: 03/08/2022 02:46:11 PM
-- Design Name:
-- Module Name: TB_FPGATraceBuffer - Behavioral
-- Project Name: UART-DTM
-- Tool Versions: Vivado 2021.2
-- Description: Simulation testing functionality of the FPGA facing side of the
-- TraceBuffer.
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.all;
  use IEEE.NUMERIC_STD.all;
  use IEEE.MATH_REAL.uniform;
  use IEEE.MATH_REAL.floor;
  use WORK.DTB_PKG.all;

entity TB_FPGATRACEBUFFER is
end entity TB_FPGATRACEBUFFER;

architecture TB of TB_FPGATRACEBUFFER is

  constant CLK_PERIOD                  : time    := 1 ns;           -- ns;

  signal config_slv                    : std_logic_vector(CONFIG_BITS - 1 downto 0);
  signal config                        : config_t;

  signal status_slv                    : std_logic_vector(STATUS_BITS - 1 downto  0);
  signal status                        : status_t;
  signal read_addr                     : std_logic_vector(TRB_ADDR_BITS - 1 downto 0);
  signal write_addr                    : std_logic_vector(TRB_ADDR_BITS - 1 downto 0);
  signal we                            : std_logic;
  signal clk                           : std_logic;

  signal data_in, data_out             : std_logic_vector(TRB_WIDTH - 1 downto 0);

  signal trig_i                        : std_logic;
  signal trig_o                        : std_logic;
  signal trace                         : std_logic;
  signal dout                          : std_logic;

  type ram_t is array(0 to TRB_DEPTH - 1) of std_logic_vector(TRB_WIDTH - 1 downto 0);

  signal ram                           : ram_t := (others => (others => '0'));

begin

  config_slv <= config_to_slv(config);
  status     <= slv_to_status(status_slv);

  FPGA_TRACE_BUFFER_1 : entity work.fpga_trace_buffer
    port map (
      CONFIG_I     => config_slv,
      STATUS_O     => status_slv,
      READ_ADDR_O  => read_addr,
      WRITE_ADDR_O => write_addr,
      WE_O         => we,
      DATA_O       => data_out,
      DATA_I       => data_in,
      FPGA_CLK_I   => clk,
      FPGA_TRIG_I    => trig_i,
      FPGA_TRACE_I => trace,
      FPGA_DOUT_O  => dout,
      FPGA_TRIG_O  => trig_o
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
      data_in <= ram(to_integer(unsigned(read_addr)));
      if (we = '1') then
        ram(to_integer(unsigned(write_addr))) <= data_out;
      end if;
    end if;

  end process RAM_PROC;

  RAND_TRACE : process is

    variable seed1, seed2 : positive := 1;
    variable x            : real;

  begin

    while true loop

      uniform(seed1, seed2, x);

      if (x < 0.5) then
        trace <= '0';
      else
        trace <= '1';
      end if;

      wait for CLK_PERIOD;

    end loop;

  end process RAND_TRACE;

  MAIN : process is

  begin

    wait for 1 ps;
    config        <= CONFIG_DEFAULT;
    config.reset  <= "1";
    trig_i        <= '0';
    wait for CLK_PERIOD;
    config.reset  <= "0";
    wait for CLK_PERIOD;
    config.enable <= "1";

    wait for 20 * CLK_PERIOD;
    report "Testing Trigger functionality with default timer stop (full future)";
    trig_i <= '1';
    wait for CLK_PERIOD;
    trig_i <= '0';

    while status.tr_hit = "0" loop

      wait for CLK_PERIOD;

    end loop;

    report "Testing Trigger functionality with centered timer stop (centered event)";
    config.reset      <= "1";
    config.timer_stop <= "011";
    wait for CLK_PERIOD;
    config.reset      <= "0";
    wait for 2 * CLK_PERIOD;
    trig_i            <= '1';
    wait for CLK_PERIOD;
    trig_i            <= '0';

    report "Testing Trigger functionality with immediate timer stop (full history)";
    config.reset      <= "1";
    config.timer_stop <= "000";
    wait for CLK_PERIOD;
    config.reset      <= "0";
    wait for 2 * CLK_PERIOD;
    trig_i            <= '1';
    wait for CLK_PERIOD;
    trig_i            <= '0';

    report "Testing Data Transfer functionality";
    config.reset      <= "1";
    config.te_mode    <= "1";
    config.timer_stop <= "111";
    config.enable     <= "0";
    wait for CLK_PERIOD;
    config.reset      <= "0";
    wait for CLK_PERIOD;
    config.enable     <= "1";

    while (trig_o = '0') loop

      wait for CLK_PERIOD;

    end loop;

    trig_i <= '1';
    wait for CLK_PERIOD;
    trig_i <= '0';
    wait for 5 * CLK_PERIOD;
    trig_i <= '1';
    wait;

  end process MAIN;

end architecture TB;
