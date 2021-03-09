----------------------------------------------------------------------------------
-- Prova finale di Reti Logiche 2020/2021

-- Scritto e progettato da Lucas Jose Manini (10625965 / 906915)
-- Politecnico di Milano
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity project_reti_logiche is
  Port (i_clk     : in std_logic;
        i_rst     : in std_logic;
        i_start   : in std_logic;
        i_data    : in std_logic_vector(7 downto 0);
        o_address : out std_logic_vector(15 downto 0);
        o_done    : out std_logic;
        o_en      : out std_logic;
        o_we      : out std_logic;
        o_data    : out std_logic_vector (7 downto 0)
   );
end project_reti_logiche;

architecture Behavioral of project_reti_logiche is

type FSM_STATE is (IDLE, START, STALL_C, COMPARE, COMPUTE, SETUP, STALL_W, CALC_CURRENT_DELTA, SHIFT_PIXEL,
                    PREP_WRITE, WRITE_PIXEL, CLOSE_WRITE, DONE, FINISH );

signal numCol : std_logic_vector(7 downto 0); -- Bastano 8 bit per contare fino a 128
signal numRow : std_logic_vector(7 downto 0); -- Bastano 8 bit per contare fino a 128
signal size : std_logic_vector(15 downto 0) := "0000000000000000"; -- Nel caso peggiore é size = 128*128 = 16384
signal maxPixelValue : std_logic_vector(7 downto 0) := "00000000";
signal minPixelValue : std_logic_vector(7 downto 0) := "11111111";
signal temp : std_logic_vector(15 downto 0);
signal deltaValue : std_logic_vector(7 downto 0); -- Worst case scenario : max = 255, min = 0 ==> deltaValue = 255 - 0 = 255
signal shiftValue : std_logic_vector(3 downto 0); -- shiftValue va da 0 a 8 compresi

signal addressRAM : integer := 0; -- Variabile ausiliaria per tener conto dell'indirizzo RAM al quale accedo
signal contatorePixel : integer := 0; -- Variabile ausiliaria utile per ciclare su tutti i pixel dell'immagine
signal state : FSM_STATE := IDLE;
signal en_status : std_logic := '0';
signal read_status : integer := 0;
signal write_target : std_logic_vector(15 downto 0) := "0000000000000000";

begin

    process(i_clk, i_start, i_rst)
    
     begin
     
        -- Qui va tutta la logica della fsm
        
        if (rising_edge(i_clk)) then
            
            -- Reset asincrono
            
            if (i_rst = '1') then
            
                -- Stato IDLE
                
                o_en <= '0';
                o_we <= '0';
                o_done <= '0';
                en_status <= '0';
                numCol <= "00000000";
                numRow <= "00000000";
                maxPixelValue <= "00000000";
                minPixelValue <= "11111111";
                size <= "0000000000000000";
                temp <= "0000000000000000";
                addressRAM <= 0;
                contatorePixel <= 0;
                read_status <= 0;
                state <= IDLE;
                
            else
            
                -- i_rst = 0
                
                if (i_start = '1') then
                
                    -- i_start = 1 ==> Tutti gli stati tranne FINISH
                    
                    case state is 
                    
                        when START =>

                            if (en_status = '0') then
                                o_en <= '1';
                                en_status <= '1';
                            else
                                o_address <= std_logic_vector(TO_UNSIGNED(addressRAM, o_address'length));
                                addressRAM <= addressRAM + 1;
                                state <= STALL_C;
                            end if;
                                                
                        when STALL_C =>
                            
                            state <= COMPARE;

                        when COMPARE =>
                        
                            case read_status is 
                            
                                when 0 =>
                                
                                    -- Lettura numCol
                                    numCol <= i_data;
                                    
                                    -- Set up prossima lettura
                                    o_address <= std_logic_vector(TO_UNSIGNED(addressRAM, o_address'length));
                                    addressRAM <= addressRAM + 1;
                                    
                                    -- Avanzo lo stato della lettura
                                    read_status <= 1;
                                    state <= STALL_C; 
                                    
                                when 1 =>
                                    
                                    -- Lettura numRow
                                    numRow <= i_data;
                                    
                                    -- Set up prossima lettura
                                    o_address <= std_logic_vector(TO_UNSIGNED(addressRAM, o_address'length));
                                    addressRAM <= addressRAM + 1;
                                    
                                    -- Avanzo lo stato della lettura
                                    read_status <= 2;
                                
                                when 2 =>
                                
                                    -- Controllo edge case di immagine con almeno una dimensione nulla
                                
                                    if (numCol = "00000000" or numRow = "00000000") then
                                        -- L'immagine é vuota! Non ho nulla da fare
                                        state <= DONE;
                                    else
                                        size <= std_logic_vector(unsigned(numCol) * unsigned(numRow));
                                        read_status <= 3;
                                    end if;
                                
                                when 3 => 
                                
                                    -- Ricerca effettiva di max e min
                                    if (unsigned(size) > contatorePixel) then
                                        if (i_data > maxPixelValue) then
                                            maxPixelValue <= i_data;
                                        end if;
                                        
                                        if (i_data < minPixelValue) then
                                            minPixelValue <= i_data;
                                        end if;
                                        
                                        -- Set up lettura prossimo pixel
                                        o_address <= std_logic_vector(TO_UNSIGNED(addressRAM, o_address'length));
                                        addressRAM <= addressRAM + 1;
                                        contatorePixel <= contatorePixel + 1;
                                        state <= STALL_C;
                                    else
                                        -- Ho finito di leggere i pixel dell'immagine
                                        deltaValue <= std_logic_vector(unsigned(maxPixelValue) - unsigned(minPixelValue));
                                        addressRAM <= 2;
                                        contatorePixel <= 0;
                                        state <= COMPUTE;
                                    end if;
                                    
                                when others =>
                                    
                                    state <= COMPUTE;    

                            end case;

                        when COMPUTE =>
                            
                            -- Calcolo shiftValue con controlli di soglia
                            
                            case to_integer(unsigned(deltaValue)) is
                            
                                when 0 => shiftValue <= "1000";
                                when 1 to 2 => shiftValue <= "0111"; 
                                when 3 to 6 => shiftValue <= "0110";
                                when 7 to 14 => shiftValue <= "0101";
                                when 15 to 30 => shiftValue <= "0100";
                                when 31 to 62 => shiftValue <= "0100";
                                when 63 to 126 => shiftValue <= "0010";
                                when 127 to 254 => shiftValue <= "0001";
                                when 255 => shiftValue <= "0000";
                                when others => shiftValue <= "0000";
                            
                            end case;  
                            
                            state <= SETUP;  
                            
                        when SETUP =>
                        
                            if (unsigned(size) > contatorePixel) then
                                
                                -- Set up lettura pixel da equalizzare 
                                o_address <= std_logic_vector(TO_UNSIGNED(addressRAM, o_address'length));
                                write_target <= std_logic_vector(addressRAM + unsigned(size));
                                
                                addressRAM <= addressRAM + 1;
                                contatorePixel <= contatorePixel + 1;
                                
                                state <= STALL_W;
                            
                            else
                                -- Non ci sono piú pixel da equalizzare
                                state <= DONE;
                            
                            end if;   
                        
                        when STALL_W =>
                            
                            state <= CALC_CURRENT_DELTA;
                            
                        when CALC_CURRENT_DELTA =>
                            
                            if (i_data > minPixelValue) then
                                temp <= "00000000" & std_logic_vector(unsigned(i_data) - unsigned(minPixelValue));
                            else
                                temp <= "0000000000000000";
                            end if;
                            
                            state <= SHIFT_PIXEL;
                            
                        when SHIFT_PIXEL =>
                                
                            temp <= std_logic_vector(shift_left(unsigned(temp), to_integer(unsigned(shiftValue))));
                            
                            state <= PREP_WRITE;

                        when PREP_WRITE =>
                        
                            o_we <= '1';
                            o_address <= write_target;
                            
                            if (unsigned(temp) > 255) then
                                o_data <= "11111111";
                            else
                                o_data <= temp(7 downto 0);
                            end if;
                            
                            state <= WRITE_PIXEL;
                        
                        when WRITE_PIXEL =>
                            
                            o_we <= '0';
                            
                            state <= CLOSE_WRITE;
                        
                        when CLOSE_WRITE =>
                            
                            state <= SETUP;
                            
                        when DONE =>
                            
                            o_address <= std_logic_vector(TO_UNSIGNED(0, o_address'length));
                            o_done <= '1';
                            o_en <= '0';
                            o_we <= '0';
                            en_status <= '0';
                            
                            state <= FINISH;
                            
                        when others =>
                            state <= START;
                        
                       end case; 
                
                else
                    -- Stato FINISH
                    
                    addressRAM <= 0;
                    numCol <= "00000000";
                    numRow <= "00000000";
                    contatorePixel <= 0;
                    size <= "0000000000000000";
                    temp <= "0000000000000000";
                    minPixelValue <= "11111111";
                    maxPixelValue <= "00000000";
                    read_status <= 0;
                    o_done <= '0';
                    
                    if (i_start = '1') then
                        state <= START;
                    else
                        state <= FINISH;
                    end if;
                end if;
            end if;
        end if;
    end process;
end Behavioral;
