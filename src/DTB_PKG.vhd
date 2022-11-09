
------------------------------------------------------
-- Title      : DTB_PKG
-- Project    :
-------------------------------------------------------------------------------
-- File       : DTB_PKG.vhdl
-- Author     : Stephan Proß <s.pross@stud.uni-heidelberg.de>
-- Company    :
-- Created    : 2022-09-13
-- Last update: 2022-11-09
-- Platform   :
-- Standard   : VHDL'08
-------------------------------------------------------------------------------
-- Description: Package containing definitions for the Data Trace Buffer and  communication
-- with it.
-------------------------------------------------------------------------------
-- Copyright (c) 2022
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2022-09-13  1.0      spross  Created
-------------------------------------------------------------------------------

library IEEE;
  use IEEE.STD_LOGIC_1164.ALL;
  use IEEE.NUMERIC_STD.ALL;
  use IEEE.math_real.ALL;

package dtb_pkg is

  -- Ideally keep all values as a power of two.
  -- Write/Read width of the trace buffer.
  constant TRB_WIDTH : natural := 8;
  -- Number of bits required to iterate over TRB_WIDTH
  constant TRB_WIDTH_BITS : natural := natural(ceil(log2(real(TRB_WIDTH))));
  -- Number of words buffer can contain.
  constant TRB_DEPTH : natural := 8;
  -- Number of bits required to address all words.
  constant TRB_ADDR_BITS : natural := natural(ceil(log2(real(TRB_DEPTH))));
  -- Total number of bits stored in buffer.
  constant TRB_BITS : natural := TRB_WIDTH * TRB_DEPTH;


  type config_t is record
    -- Reset trigger logic.
    reset : std_logic_vector(0 downto 0);
    -- Enable for logic.
    enable : std_logic_vector(0 downto 0);
    -- Config changing TE from trigger to enable.
    te_mode : std_logic_vector(0 downto 0);
    -- Controls when trace recording is stopped after trigger is received.
    timer_stop : std_logic_vector(2 downto 0);
    -- RW address of the system interface.
    sys_addr : std_logic_vector(TRB_ADDR_BITS - 1 downto 0);
  end record;

  constant CONFIG_BITS : natural := 6 + TRB_ADDR_BITS;
  constant CONFIG_DEFAULT : config_t
 :=(
     reset => "0",
     enable => "0",
     te_mode => "0",
     timer_stop => (others => '1'),
     sys_addr => (others => '0')
   );

  function slv_to_config (value : std_logic_vector(CONFIG_BITS - 1 downto 0)) return config_t;

  function config_to_slv (config : config_t) return std_logic_vector;


  type status_t is record
    -- Has the trigger been hit?
    tr_hit : std_logic_vector(0 downto 0);
    -- Bit corresponding to the trigger event.
    event_pos : std_logic_vector(TRB_WIDTH_BITS-1 downto 0);
    -- Byte address containing the event.
    event_addr : std_logic_vector(TRB_ADDR_BITS-1 downto 0);
  end record;

  constant STATUS_BITS : natural := 1 + TRB_WIDTH_BITS + TRB_ADDR_BITS;
  constant STATUS_DEFAULT : status_t
 :=(
     tr_hit => "0",
     event_pos => (others => '0'),
     event_addr => (others => '0')
   );



  function status_to_slv (status : status_t) return std_logic_vector;

  function slv_to_status (value : std_logic_vector(STATUS_BITS - 1 downto 0)) return status_t;

end package dtb_pkg;

package body dtb_pkg is

  function config_to_slv (config : config_t) return std_logic_vector is
  begin

    return config.reset &
      config.enable &
      config.te_mode &
      config.timer_stop &
      config.sys_addr;

  end function config_to_slv;

  function slv_to_config (value : std_logic_vector(CONFIG_BITS - 1 downto 0)) return config_t is
  begin

    return (
      reset => value(TRB_ADDR_BITS + 5 downto TRB_ADDR_BITS + 5),
      enable => value(TRB_ADDR_BITS + 4 downto TRB_ADDR_BITS + 4),
      te_mode => value(TRB_ADDR_BITS + 3 downto TRB_ADDR_BITS + 3),
      timer_stop => value(TRB_ADDR_BITS + 2 downto TRB_ADDR_BITS),
      sys_addr => value(TRB_ADDR_BITS - 1  downto 0)
      );

  end function;

  function status_to_slv (status : status_t) return std_logic_vector is
  begin

    return status.tr_hit & status.event_pos & status.event_addr;

  end function status_to_slv;

  function slv_to_status (value : std_logic_vector(STATUS_BITS - 1 downto 0)) return status_t is
  begin

    return (
      event_addr => value(TRB_ADDR_BITS -1 downto 0),
      event_pos => value(TRB_WIDTH_BITS+TRB_WIDTH_BITS-1 downto TRB_ADDR_BITS),
      tr_hit => value(TRB_WIDTH_BITS+TRB_WIDTH_BITS downto TRB_WIDTH_BITS+TRB_WIDTH_BITS)
      );

  end function;

end package body dtb_pkg;
