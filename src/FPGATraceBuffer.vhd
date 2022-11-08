----------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    12:15:23 07/27/2017
-- Design Name:
-- Module Name:    FPGATraceBuffer - Behavioral
-- Project Name:
-- Target Devices:
-- Tool versions:
-- Description:
-- FPGA facing side of the Trace Buffer.
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.ALL;
  use IEEE.NUMERIC_STD.ALL;
  use WORK.DTB_PKG.ALL;

entity FPGA_TRACE_BUFFER is
  port (
    -- DTB internal signals:
    CONFIG_I           : in    std_logic_vector(CONFIG_BITS - 1 downto 0);
    STATUS_O           : out   std_logic_vector(STATUS_BITS - 1 downto  0);
    READ_ADDR_O        : out   std_logic_vector(TRB_ADDR_BITS - 1 downto 0);
    WRITE_ADDR_O       : out   std_logic_vector(TRB_ADDR_BITS - 1 downto 0);
    WE_O               : out   std_logic;

    DOUT_O             : out   std_logic_vector(TRB_WIDTH - 1 downto 0);
    DIN_I              : in    std_logic_vector(TRB_WIDTH - 1 downto 0);

    -- FPGA interface.
    -- CLK from FPGA fabric.
    FPGA_CLK_I         : in    std_logic;
    -- Trigger/Enable signal.
    FPGA_TE_I          : in    std_logic;
    -- Trace input
    FPGA_TRACE_I       : in    std_logic;
    -- Bit serial output for data transfer.
    FGPA_DOUT_O        : out   std_logic
  );
end entity FPGA_TRACE_BUFFER;

architecture BEHAVIORAL of FPGA_TRACE_BUFFER is

  signal addr_low       : integer range 0 to TRB_WIDTH - 1;
  signal addr_high      : integer range 0 to TRB_DEPTH - 1;

  signal timer          : integer range 0 to TRB_BITS - 1;

  signal status         : status_t;
  signal config         : config_t;

  signal sticky_trigger : std_logic;
  signal pointer_inc    : std_logic;

  signal trace_reg      : std_logic_vector(TRB_WIDTH - 1 downto 0);

begin

  READ_ADDR_O  <= std_logic_vector(to_unsigned(high_pointer, TRB_ADDR_BITS));
  WRITE_ADDR_O <= std_logic_vector(to_unsigned(high_pointer, TRB_ADDR_BITS));

  -- Synchronous update of mode signal and status output.
  MODE_STATUS_UPDATE : process (FPGA_CLK_I) is
  begin

    if rising_edge(FPGA_CLK_I) then
      mode <= stl_to_config(CONFIG_I);
      -- Reset is held for exactly one cycle.
      if (mode.reset = '1') then
        mode.reset <= '0';
      end if;
      STATUS_O <= status_to_stl(status);
    end if;

  end process MODE_STATUS_UPDATE;

  -- Denpending on te_mode, TE_I is either sticky or treated simply as an
  -- enable.
  TRIGGER : process (FPGA_CLK_I) is
  begin

    if rising_edge(FPGA_CLK_I) then
      if (mode.reset = '1') then
        sticky_trigger <= '0';
      else
        if (mode.te_mode = '0') then
          if (FPGA_TE_I = '1' or sticky_trigger = '1') then
            sticky_trigger <= '1';
          end if;
        else
          sticky_trigger <= FPGA_TE_I;
        end if;
      end if;
    end if;

  end process TRIGGER;

  -- Starts a timer if trigger is set and disables pointer increment on timer overflow.
  --
  TIMER_PROC : process (FPGA_CLK_I) is
  begin

    if rising_edge(FPGA_CLK_I) then
      if (mode.reset = '1') then
        timer         <= '0';
        pointer_inc   <= '1';
        status.tr_hit <= '0';
      else
        if (FPGA_TE_I = '1' or sticky_trigger = '1') then
          -- Increment timer until the value of timer_stop shifted by the
          -- word length is reached.
          if (timer < (to_integer(unsigned(mode.timer_stop)) * TRB_BITS) / ((2 **mode.timer_stop'length) -1) - 1) then
            timer <= timer + 1;
          else
            pointer_inc   <= '0';
            status.tr_hit <= '1';
          end if;
        end if;
      end if;
    end if;

  end process TIMER_PROC;

  ADDR_PROC : process (FPGA_CLK_I) is
  begin

    if rising_edge(FPGA_CLK_I) then
      if (mode.reset = '1') then
        addr_low    <= 0;
        addr_high   <= 0;
        WE_O        <= '0';
        DOUT_O      <= (others => '0');
        trace_reg   <= (others => '0');
        FPGA_DOUT_O <= '0';
      else
        if (pointer_inc = '1') then
          trace_reg(addr_low) <= FPGA_TRACE_I;
          FPGA_DOUT_O         <= trace_reg(addr_low);

          if (addr_low < TRB_WIDTH - 1) then
            addr_low <= addr_low + 1;
            WE_O     <= '0';
          else
            addr_low <= 0;
            -- Upon overflow of the lower address exchange trace_reg with the
            -- word of the trace buffer.
            WE_O                              <= '1';
            DOUT_O                            <= trace_reg;
            trace_reg(TRB_WIDTH - 1 downto 1) <= DIN_I(TRB_WIDTH - 1 downto 1);
            FPGA_DOUT_O                       <= DIN_I(0);

            if (addr_high < TRB_DEPTH - 1) then
              addr_high <= addr_high + 1;
            else
              addr_high <= 0;
            end if;
          end if;
        end if;
      end if;
    end if;

  end process ADDR_PROC;

end architecture BEHAVIORAL;
