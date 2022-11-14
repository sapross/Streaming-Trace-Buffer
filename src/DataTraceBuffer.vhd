----------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    12:15:23 07/27/2017
-- Design Name:
-- Module Name:    DataTraceBuffer - Behavioral
-- Project Name:
-- Target Devices:
-- Tool versions:
-- Description:
-- Trace Buffer implementation based on dual-port BRAM with the ability to also
-- allow two way data transfer between host and fabric.
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------

library IEEE;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.dtb_pgk.all;

entity DATATRACEBUFFER is
  port (
    -- System interface:
    CLK_I               : in    std_logic;
    RST_I               : in    std_logic;

    SELECT_I            : in    std_logic;
    CONFIG_WRITE_I      : in    std_logic_vector(CONFIG_BITS - 1 downto 0);
    DATA_WRITE_I        : in    std_logic_vector(7 downto 0);
    REG_WRITE_READY_O   : out   std_logic;
    REG_WRITE_VALID_I   : in    std_logic;

    CONFIG_READ_O       : out   std_logic_vector(STATUS_BITS - 1 downto 0);
    DATA_READ_O         : out   std_logic_vector(7 downto 0);
    REG_READ_READY_I    : in    std_logic;
    REG_READ_VALID_O    : out   std_logic;

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
end entity DATATRACEBUFFER;

architecture BEHAVIORAL of DATATRACEBUFFER is

  type memory_t is array(0 to TRB_DEPTH - 1) of std_logic_vector(TRB_WIDTH - 1 downto 0);

  signal memory                   : memory_t;

  signal trg_we                   : std_logic;
  signal trg_word_i, trg_word_o   : std_logic_vector(TRB_WIDTH - 1 downto 0);
  signal trg_raddr,  trg_waddr    : std_logic_vector(TRB_ADDR_BITS - 1 downto 0);
  signal trg_config               : std_logic_vector(CONFIG_BITS - 1 downto 0);
  signal trg_status               : std_logic_vector(STATUS_BITS - 1 downto 0);

  signal int_we                   : std_logic;
  signal int_word_i, int_word_o   : std_logic_vector(TRB_WIDTH - 1 downto 0);
  signal int_addr                 : std_logic_vector(TRB_ADDR_BITS - 1 downto 0);
  signal int_config               : std_logic_vector(CONFIG_BITS - 1 downto 0);
  signal int_status               : std_logic_vector(STATUS_BITS - 1 downto 0);

begin

  DTBINTERFACE_1 : entity work.dtbinterface
    port map (
      CLK_I             => CLK_I,
      RST_I             => RST_I,
      SELECT_I          => SELECT_I,
      CONFIG_WRITE_I    => CONFIG_WRITE_I,
      DATA_WRITE_I      => DATA_WRITE_I,
      REG_WRITE_READY_O => REG_WRITE_READY_O,
      REG_WRITE_VALID_I => REG_WRITE_VALID_I,
      CONFIG_READ_O     => CONFIG_READ_O,
      DATA_READ_O       => DATA_READ_O,
      REG_READ_READY_I  => REG_READ_READY_I,
      REG_READ_VALID_O  => REG_READ_VALID_O,
      CONFIG_O          => trg_config,
      STATUS_I          => trg_status,
      WE_O              => int_we,
      ADDR_O            => int_addr,
      DATA_I            => int_word_i,
      DATA_O            => int_word_o
    );

  FPGA_TRACE_BUFFER_1 : entity work.fpga_trace_buffer
    port map (
      CONFIG_I     => trg_config,
      STATUS_O     => trg_status,
      READ_ADDR_O  => trg_raddr,
      WRITE_ADDR_O => trg_waddr,
      WE_O         => trg_we,
      DATA_O       => trg_word_o,
      DATA_I       => trg_word_i,
      FPGA_CLK_I   => FPGA_CLK_I,
      FPGA_TRIG_I  => FPGA_TRIG_I,
      FPGA_TRACE_I => FPGA_TRACE_I,
      FPGA_DOUT_O  => FPGA_DOUT_O,
      FPGA_TRIG_O  => FPGA_TRIG_O
    );

  TRG_MEM : process (CLK_I) is
  begin

    if rising_edge(CLK_I) then
      if (RST_I = '1') then
        trg_word_o <= (others =>'0');
      else
        trg_word_o <= mem(trg_raddr);
        if (trg_we = '1') then
          mem(trg_waddr) <= trg_word_i;
        end if;
      end if;
    end if;

  end process TRG_MEM;

  INT_MEM : process (CLK_I) is
  begin

    if rising_edge(CLK_I) then
      if (RST_I = '1') then
        int_word_o <= (others =>'0');
      else
        int_word_o <= mem(int_addr);
        if (int_we = '1') then
          mem(int_addr) <= int_word_i;
        end if;
      end if;
    end if;

  end process INT_MEM;

end architecture BEHAVIORAL;
