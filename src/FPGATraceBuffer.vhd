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
    FPGA_TRIG_I         : in    std_logic;
    -- Trace input
    FPGA_TRACE_I        : in    std_logic;
    -- Bit serial output for data transfer.
    FPGA_DOUT_O         : out   std_logic;
    -- FPGA side signal indicating fulfilled trigger condition and trace acquisition.
    FPGA_TRIG_O         : out   std_logic
  );
end entity FPGA_TRACE_BUFFER;

architecture BEHAVIORAL of FPGA_TRACE_BUFFER is

  type state_t is (st_idle, st_wait_for_trigger, st_capture_trace, st_rwmode, st_done);

  signal state,     state_next                       : state_t;

  signal addr_low,  addr_low_next                    : integer range 0 to TRB_WIDTH - 1;
  signal addr_high                                   : integer range 0 to TRB_DEPTH - 1;
  signal addr_high_next                              : integer range 0 to TRB_DEPTH - 1;
  signal addr_high_prev                              : integer range 0 to TRB_DEPTH - 1;

  signal timer,     timer_next                       : integer range 0 to TRB_BITS - 1;

  signal status,    status_next                      : status_t;
  signal config                                      : config_t;

  signal trace_reg, trace_reg_next                   : std_logic_vector(TRB_WIDTH - 1 downto 0);
  signal fpga_serial_valid                           : std_logic;

  function get_limit (
    constant config_i : config_t
  ) return integer is
  begin

    -- Formular for the limit L:
    -- Let n := timer_stop, P := TRB_BITS, N := 2**timer_stop'length
    -- L = (n+1)/N * P - 1
    -- Example: Trace Buffer can hold 64 bits (P = 64), timer_stop is 3
    -- bits (N = 8 => 0<n<8) and timer_stop is set to "011" (n=3):
    -- L = (3 + 1)/ 8 * 64 - 1 = 31
    return ((to_integer(unsigned(config.timer_stop)) + 1) * TRB_BITS) /
      (2 ** config.timer_stop'length) - 1;

  end function;

begin

  READ_ADDR_O  <= std_logic_vector(to_unsigned(addr_high, TRB_ADDR_BITS));
  WRITE_ADDR_O <= std_logic_vector(to_unsigned(addr_high_prev, TRB_ADDR_BITS));
  FPGA_DOUT_O  <= trace_reg(addr_low);

  -- Change function of FPGA_TRIG_O based on config.
  FPGA_TRIGGER_OUTPUT : process (status, config, fpga_serial_valid) is
  begin

    if (config.TE_mode = "0") then
      FPGA_TRIG_O <= status.tr_hit(0);
    else
      FPGA_TRIG_O <= not status.tr_hit(0) and fpga_serial_valid;
    end if;

  end process FPGA_TRIGGER_OUTPUT;

  -- Synchronous update of mode signal and status output.
  CONFIG_STATUS_UPDATE : process (FPGA_CLK_I) is
  begin

    if rising_edge(FPGA_CLK_I) then
      config <= slv_to_config(CONFIG_I);
      -- Reset is held for exactly one cycle.
      STATUS_O <= status_to_slv(status);
    end if;

  end process CONFIG_STATUS_UPDATE;

  FSM_CORE : process (FPGA_CLK_I) is
  begin

    if rising_edge(FPGA_CLK_I) then
      if (config.reset = "1") then
        state          <= st_idle;
        status         <= STATUS_DEFAULT;
        addr_low       <= 0;
        addr_high      <= 0;
        addr_high_prev <= TRB_DEPTH - 1;
        timer          <= 0;
        trace_reg      <= (others => '0');

        WE_O   <= '0';
        DATA_O <= (others => '0');
      else
        if (config.enable = "1") then
          state          <= state_next;
          status         <= status_next;
          addr_low       <= addr_low_next;
          addr_high      <= addr_high_next;
          addr_high_prev <= addr_high;
          timer          <= timer_next;
          trace_reg      <= trace_reg_next;

          fpga_serial_valid <= '0';

          WE_O   <= '0';
          DATA_O <= (others => '0');

          if (state = st_wait_for_trigger or state = st_capture_trace) then
            -- Output current bit of the trace register.
            if (addr_low = TRB_WIDTH - 1) then
              -- trace_register is full, write out to buffer.
              WE_O      <= '1';
              DATA_O    <= FPGA_TRACE_I & trace_reg(TRB_WIDTH - 2 downto 0);
              trace_reg <= DATA_I;
            end if;
          end if;
          if (state = st_rwmode) then
            fpga_serial_valid <= '1';
            if (addr_low = 0) then
              trace_reg <= DATA_I;
            end if;
            -- Output current bit of the trace register.
            if (FPGA_TRIG_I = '1' and addr_low = TRB_WIDTH - 1) then
              -- trace_register is full, write out to buffer.
              WE_O   <= '1';
              DATA_O <= FPGA_TRACE_I & trace_reg(TRB_WIDTH - 2 downto 0);
            end if;
          end if;
        end if;
      end if;
    end if;

  end process FSM_CORE;

  FSM : process (state, addr_low, addr_high, timer, trace_reg, config, FPGA_TRACE_I, FPGA_TRIG_I) is
  begin

    if (config.reset = "1") then
      state_next <= st_idle;
    else
      state_next     <= state;
      status_next    <= status;
      addr_low_next  <= addr_low;
      addr_high_next <= addr_high;
      timer_next     <= timer;
      trace_reg_next <= trace_reg;

      case state is

        when st_idle =>
          -- Reset address high and low;
          addr_low_next  <= 0;
          addr_high_next <= 0;
          -- TE_mode switches between TraceBuffer- and RWBuffer-mode.
          if (config.te_mode = "0") then
            state_next <= st_wait_for_trigger;
          else
            state_next <= st_rwmode;
          end if;

        when st_wait_for_trigger =>
          -- Keep incrementing trace buffer address.
          addr_low_next <= (addr_low + 1) mod TRB_WIDTH;
          if (addr_low_next = TRB_WIDTH - 1) then
            addr_high_next <= (addr_high + 1) mod TRB_DEPTH;
          end if;
          -- Populate trace register with data.
          trace_reg_next(addr_low) <= FPGA_TRACE_I;

          if (FPGA_TRIG_I = '1') then
            -- Trigger has been activated.
            state_next <= st_capture_trace;
            -- Save position of trigger event in trace buffer.
            status_next.event_pos  <= std_logic_vector(to_unsigned(addr_low_next, TRB_WIDTH_BITS));
            status_next.event_addr <= std_logic_vector(to_unsigned(addr_high,   TRB_ADDR_BITS));
          end if;

        when st_capture_trace =>
          -- Keep incrementing trace buffer address.
          addr_low_next <= (addr_low + 1) mod TRB_WIDTH;
          if (addr_low_next = TRB_WIDTH - 1) then
            addr_high_next <= (addr_high + 1) mod TRB_DEPTH;
          end if;
          -- Populate trace register with data.
          trace_reg_next(addr_low) <= FPGA_TRACE_I;

          if (timer < get_limit(config)) then
            timer_next <= timer + 1;
          else
            state_next         <= st_done;
            status_next.tr_hit <= "1";
          end if;

        when st_rwmode =>
          if (FPGA_TRIG_I = '1') then
            if (timer < get_limit(config)) then
              timer_next <= timer + 1;
            else
              state_next         <= st_done;
              status_next.tr_hit <= "1";
            end if;

            trace_reg_next(addr_low) <= FPGA_TRACE_I;

            addr_low_next <= (addr_low + 1) mod TRB_WIDTH;
            if (addr_low = TRB_WIDTH - 1) then
              addr_high_next <= (addr_high + 1) mod TRB_DEPTH;
            end if;
            status_next.event_pos  <= std_logic_vector(to_unsigned(addr_low_next, TRB_WIDTH_BITS));
            status_next.event_addr <= std_logic_vector(to_unsigned(addr_high,   TRB_ADDR_BITS));
          end if;

        when st_done =>
          status_next.tr_hit <= "1";

      end case;

    end if;

  end process FSM;

end architecture BEHAVIORAL;
