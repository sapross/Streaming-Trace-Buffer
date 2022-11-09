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
  use IEEE.STD_LOGIC_1164.ALL;
  use IEEE.NUMERIC_STD.ALL;

entity DataTraceBuffer is
  generic (
    TRACEBUFFER_WIDTH   : natural := 8;
    TRACEBUFFER_DEPTH   : natural := 8
  );
  port (
    -- System interface:
    CLK              : in    std_logic;
    RST              : in    std_logic;

    REG_SEL          : in std_logic;

    REG_WRITE        : in std_logic_vector(7 downto 0);
    REG_WRITE_READY  : out std_logic;
    REG_WRITE_VALID  : in std_logic;

    REG_READ         : out std_logic_vector(7 downto 0);
    REG_READ_READY   : in std_logic;
    REG_READ_VALID   : out std_logic;


    -- FPGA interface.
    FPGA_CLK         : in std_logic;
    FPGA_TE          : in std_logic;
    FPGA_TRACE       : in std_logic;
    FGPA_DOUT        : out std_logic


  );
end entity DataTraceBuffer;

architecture BEHAVIORAL of DataTraceBuffer is

  type memory_t is array(0 to TRACEBUFFER_DEPTH-1) of std_logic_vector(TRACEBUFFER_WIDTH-1 downto 0);
  signal memory : memory_t;

begin

end architecture BEHAVIORAL;
