module Clock50New(
    input wire CLOCK_50,       
    input wire [3:0] KEY,           
    output reg [41:0] Display
); 

    wire reset       = ~KEY[0]; // Button 1 (Rightmost): Reset
    wire adjust_mode = ~KEY[1]; // Button 2: Hold to Adjust
    wire btn_min     = ~KEY[2]; // Button 3: Add Minute
    wire btn_hr      = ~KEY[3]; // Button 4 (Leftmost): Add Hour

    // Internal Trackers
    reg [25:0] counter = 0;          
    reg [7:0] seconds = 0;           
    reg [7:0] minutes = 0;                    
    reg [7:0] hours = 0;
    
    reg [7:0] sec_bcd = 0, min_bcd = 0, hr_bcd = 0;
    
    // 2. Clean Edge Detection (Prevents holding the button from adding 100 hours instantly)
    reg [1:0] key_d1 = 0, key_d2 = 0;
    wire pulse_min = (key_d1[0] & ~key_d2[0]);          // detecting minute button 
    wire pulse_hr  = (key_d1[1] & ~key_d2[1]);          // dectecting hours button 

    always @(posedge CLOCK_50) begin
        key_d1 <= {btn_hr, btn_min};
        key_d2 <= key_d1;
    end

//--------------- Main Loop ---------------//
    always @(posedge CLOCK_50) begin 
        
        // Check for Reset Button
        if(reset) begin
            seconds <= 0;
            minutes <= 0;
            hours <= 0;
            counter <= 0;
        end 
        
        // Check for Time Adjust Mode
        else if(adjust_mode) begin
            if(pulse_hr) begin
                if(hours == 23) hours <= 0;
                else hours <= hours + 1;
            end
            
            if(pulse_min) begin
                if(minutes == 59) minutes <= 0;
                else minutes <= minutes + 1;
            end
        end
        
        // Normal Clock Ticking (Wait 1 exact second)
        else if (counter >= 49999999) begin     
            counter <= 0;                
            
            if(seconds == 59) begin              
                seconds <= 0;                
                
                if(minutes == 59) begin          
                    minutes <= 0;            
                    
                    if(hours == 23) begin        
                        hours <= 0;      
                    end else begin                   
                        hours <= hours + 1;
                    end
                    
                end else begin                       
                    minutes <= minutes + 1;
                end
                
            end else begin                           
                seconds <= seconds + 1;
            end
            
        end else begin                               
            counter <= counter + 1;
        end
        
        //----------- Binary to BCD conversion calls
        bin_to_bcd(seconds, sec_bcd);
        bin_to_bcd(minutes, min_bcd);
        bin_to_bcd(hours, hr_bcd);

        //----------- count value to display value conversion
        seg_display(sec_bcd[3:0], Display[6:0]);    
        seg_display(sec_bcd[7:4], Display[13:7]);   
        seg_display(min_bcd[3:0], Display[20:14]);  
        seg_display(min_bcd[7:4], Display[27:21]);  
        seg_display(hr_bcd[3:0],  Display[34:28]);  
        seg_display(hr_bcd[7:4],  Display[41:35]);  

    end   
        
//----------- Binary to BCD conversion task
    task bin_to_bcd;
        input [7:0] binary;  
        output [7:0] BCD;
        reg [15:0] shifter;
        reg [3:0] i;   
        begin
            shifter = binary;
            for(i = 0; i < 8; i = i + 1) begin      
                if(shifter[11:8] >= 5)                      
                    shifter[11:8] = shifter[11:8] + 3;      
                if(shifter[15:12] >= 5)                     
                    shifter[15:12] = shifter[15:12] + 3;    
                shifter = shifter << 1;                   
            end
            BCD = shifter[15:8];    
        end
    endtask
     
//----------- Display Driver Task
    task seg_display;
        input  [3:0] digit;
        output [6:0] seg;
        begin
            case(digit)
               (0) : seg = 7'b1000000;
               (1) : seg = 7'b1111001;
               (2) : seg = 7'b0100100;
               (3) : seg = 7'b0110000;
               (4) : seg = 7'b0011001;
               (5) : seg = 7'b0010010;
               (6) : seg = 7'b0000010;
               (7) : seg = 7'b1111000;
               (8) : seg = 7'b0000000;
               (9) : seg = 7'b0010000;
                default: seg = 7'b1111111;
            endcase
        end
    endtask

endmodule