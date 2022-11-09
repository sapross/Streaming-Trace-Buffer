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
    CONFIG_I            : in    std_logic_vector(CONFIG_BITS - 1 downto 0);
    STATUS_O            : out   std_logic_vector(STATUS_BITS - 1 downto  0);
    READ_ADDR_O         : out   std_logic_vector(TRB_ADDR_BITS - 1 downto 0);
    WRITE_ADDR_O        : out   std_logic_vector(TRB_ADDR_BITS - 1 downto 0);
    WE_O                : out   std_logic;

    DATA_O              : out   std_logic_vector(TRB_WIDTH - 1 downto 0);
    DATA_I              : in    std_logic_vector(TRB_WIDTH - 1 downto 0);

    -- FPGA interface.
    -- CLK from FPGA fabric.
    FPGA_CLK_I          : in    std_logic;
    -- Trigger/Enable signal.
    FPGA_TE_I           : in    std_logic;
    -- Trace input
    FPGA_TRACE_I        : in    std_logic;
    -- Bit serial output for data transfer.
    FPGA_DOUT_O         : out   std_logic
  );
end entity FPGA_TRACE_BUFFER;

architecture BEHAVIORAL of FPGA_TRACE_BUFFER is

  signal addr_low                     : integer range 0 to TRB_WIDTH - 1;
  signal addr_high, addr_high_prev    : integer range 0 to TRB_DEPTH - 1;

  signal timer                        : integer range 0 to TRB_BITS - 1;

  signal status                       : status_t;
  signal config                       : config_t;

  signal sticky_trigger               : std_logic;
  signal pointer_inc                  : std_logic;

  signal trace_reg                    : std_logic_vector(TRB_WIDTH - 1 downto 0);

begin

  READ_ADDR_O  <= std_logic_vector(to_unsigned(addr_high, TRB_ADDR_BITS));
  WRITE_ADDR_O <= std_logic_vector(to_unsigned(addr_high_prev, TRB_ADDR_BITS));

  -- Synchronous update of mode signal and status output.
  CONFIG_STATUS_UPDATE : process (FPGA_CLK_I) is
  begin

    if rising_edge(FPGA_CLK_I) then
      config <= slv_to_config(CONFIG_I);
      -- Reset is held for exactly one cycle.
      if (config.reset = "1") then
        config.reset <= "0";
      end if;
      STATUS_O <= status_to_slv(status);
    end if;

  end process CONFIG_STATUS_UPDATE;

  -- Denpending on te_mode, TE_I is either sticky or treated simply as an
  -- enable.
  TRIGGER : process (FPGA_CLK_I) is
  begin

    if rising_edge(FPGA_CLK_I) then
      if (config.reset = "1") then
        sticky_trigger    <= '0';
        status.event_pos  <= (others => '0');
        status.event_addr <= (others => '0');
      else
        if (config.te_mode = "0") then
          if (FPGA_TE_I = '1' and  sticky_trigger = '0') then
            status.event_pos  <= std_logic_vector(to_unsigned(addr_low, TRB_WIDTH_BITS));
            status.event_addr <= std_logic_vector(to_unsigned(addr_high_prev, TRB_ADDR_BITS));
            sticky_trigger    <= '1';
          end if;
        else
          sticky_trigger <= FPGA_TE_I;
          if (FPGA_TE_I = '1') then
            status.event_pos  <= std_logic_vector(to_unsigned(addr_low, TRB_WIDTH_BITS));
            status.event_addr <= std_logic_vector(to_unsigned(addr_high, TRB_ADDR_BITS));
          end if;
        end if;
      end if;
    end if;

  end process TRIGGER;

  -- Starts a timer if trigger is set and disables pointer increment on timer overflow.
  --
  TIMER_PROC : process (FPGA_CLK_I) is
  begin

    if rising_edge(FPGA_CLK_I) then
      if (config.reset = "1") then
        timer         <= 0;
        pointer_inc   <= '1';
        status.tr_hit <= "0";
      else
        if (FPGA_TE_I = '1' or sticky_trigger = '1') then
          -- Formular for the limit L:
          -- Let n := timer_stop, P := TRB_BITS, N := 2**timer_stop'length
          -- L = (n+1)/N * P
          -- Example: Trace Buffer can hold 64 bits (P = 64), timer_stop is 3
          -- bits (N = 8 => 0<n<8) and timer_stop is set to "011" (n=3):
          -- L = (3 + 1)/ 8 * 64 = 32
          if (timer < ((to_integer(unsigned(config.timer_stop)) + 1) * TRB_BITS) / ((2 ** config.timer_stop'length)) - 1) then
            timer <= timer + 1;
          else
            pointer_inc   <= '0';
            status.tr_hit <= "1";
          end if;
        end if;
      end if;
    end if;

  end process TIMER_PROC;

  ADDR_PROC : process (FPGA_CLK_I) is
  begin

    if rising_edge(FPGA_CLK_I) then
      if (config.reset = "1") then
        addr_low <= 0;
        -- Since the write happens one cycle after addr_high is incremented,
        -- addr_high needs to be initialized with ones to start filling the
        -- bram at address zero.
        addr_high      <= 0;
        addr_high_prev <= TRB_DEPTH - 1;
        WE_O           <= '0';
        DATA_O         <= (others => '0');
        trace_reg      <= (others => '0');
        FPGA_DOUT_O    <= '0';
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
            WE_O      <= '1';
            DATA_O    <= FPGA_TRACE_I & trace_reg(TRB_WIDTH - 2 downto 0);
            trace_reg <= DATA_I;

            addr_high_prev <= addr_high;
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
