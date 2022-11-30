
------------------------------------------------------
-- Title      : DTB_PKG
-- Project    :
-------------------------------------------------------------------------------
-- File       : DTB_PKG.vhdl
-- Author     : Stephan Proß <s.pross@stud.uni-heidelberg.de>
-- Company    :
-- Created    : 2022-09-13
-- Last update: 2022-11-14
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
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;

package dtb_pkg is

  -- Ideally keep all values as a power of two.
  -- Write/Read width of the trace buffer.
  constant trb_width : natural := 8;
  -- Number of bits required to iterate over TRB_WIDTH
  constant trb_width_bits : natural := natural(ceil(log2(real(trb_width))));
  -- Number of words buffer can contain.
  constant trb_depth : natural := 8;
  -- Number of bits required to address all words.
  constant trb_addr_bits : natural := natural(ceil(log2(real(trb_depth))));
  -- Total number of bits stored in buffer.
  constant trb_bits : natural := trb_width * trb_depth;

  type config_t is record
    -- Reset trigger logic.
    trg_reset : std_logic_vector(0 downto 0);
    -- Enable for logic.
    trg_enable : std_logic_vector(0 downto 0);
    -- Config changing TE from trigger to enable.
    trg_mode : std_logic_vector(0 downto 0);
    -- Controls when trace recording is stopped after trigger is received.
    trg_delay : std_logic_vector(2 downto 0);
  end record config_t;

  constant config_bits    : natural := 6;
  constant config_default : config_t
 :=
 (
   trg_reset => "0",
   trg_enable => "0",
   trg_mode => "0",
   trg_delay => (others => '1')
 );

  function slv_to_config (value : std_logic_vector(config_bits - 1 downto 0)) return config_t;

  function config_to_slv (config : config_t) return std_logic_vector;

  type status_t is record
    -- Has the trigger been hit?
    trg_event : std_logic_vector(0 downto 0);
    -- Bit corresponding to the trigger event.
    event_pos : std_logic_vector(trb_width_bits - 1 downto 0);
    -- Byte address containing the event.
    event_addr : std_logic_vector(trb_addr_bits - 1 downto 0);
  end record status_t;

  constant status_bits    : natural := 1 + trb_width_bits + trb_addr_bits;
  constant status_default : status_t
 :=
 (
   trg_event => "0",
   event_pos => (others => '0'),
   event_addr => (others => '0')
 );

  function status_to_slv (status : status_t) return std_logic_vector;

  function slv_to_status (value : std_logic_vector(status_bits - 1 downto 0)) return status_t;

  type sysint_config_t is record
    op       :   std_logic;
    auto_inc :  std_logic;
    addr     : std_logic_vector(trb_addr_bits - 1 downto 0);
  end record sysint_config_t;

  constant sysconfig_bits : natural := 2 + trb_addr_bits;

  constant sysconf_default : sysint_config_t :=
  (
    op => '0',
    auto_inc => '0',
    addr => (others => '0')
  );

end package dtb_pkg;

package body dtb_pkg is

  function config_to_slv (config : config_t) return std_logic_vector is
  begin

    return config.trg_reset &
      config.trg_enable &
      config.trg_mode &
      config.trg_delay;

  end function config_to_slv;

  function slv_to_config (value : std_logic_vector(config_bits - 1 downto 0)) return config_t is
  begin

    return (
      trg_reset => value(5 downto 5),
      trg_enable => value(4 downto 4),
      trg_mode => value(3 downto 3),
      trg_delay => value(2 downto 0)
      );

  end function;

  function status_to_slv (status : status_t) return std_logic_vector is
  begin

    return status.trg_event & status.event_pos & status.event_addr;

  end function status_to_slv;

  function slv_to_status (value : std_logic_vector(status_bits - 1 downto 0)) return status_t is
  begin

    return (
      event_addr => value(trb_addr_bits - 1 downto 0),
      event_pos => value(trb_width_bits + trb_width_bits - 1 downto trb_addr_bits),
      trg_event => value(trb_width_bits + trb_width_bits downto trb_width_bits + trb_width_bits)
      );

  end function;

end package body dtb_pkg;
