# 24-Hour Digital Clock (DE2-115 FPGA, Verilog)

A 24-hour clock written in Verilog and running on a **Terasic DE2-115** FPGA board (Intel Cyclone IV E). It shows **HH:MM:SS** on six common-anode 7-segment displays. Four push buttons reset the clock and set the time.

Built for *UEEEC0054 Provide Gate Array solutions for complex electronics systems* (Advanced Diploma of Electronics and Communications Engineering, RMIT, 2026).

## Features

- Counts seconds, minutes and hours from the board's 50 MHz oscillator, rolling over 23:59:59 → 00:00:00.
- Uses **Verilog tasks** for the repeated work, as the brief required: one binary-to-BCD converter and one 7-segment decoder, each called for every digit.
- Button presses are edge-detected, so holding a button adds exactly one minute or hour, not millions.
- Kept within the $30 budget. The board was supplied by RMIT.

| Button | Function |
|---|---|
| `KEY0` (rightmost) | Reset to 00:00:00 |
| `KEY1` | Hold to adjust. The clock pauses |
| `KEY2` | While adjusting, each press adds a minute |
| `KEY3` (leftmost) | While adjusting, each press adds an hour |

## How it works

The full source is [`Clock50New.v`](Clock50New.v). The module's ports are:

```verilog
module Clock50New(
    input wire CLOCK_50,         // 50 MHz board oscillator
    input wire [3:0] KEY,        // push buttons (active-low)
    output reg [41:0] Display    // six 7-segment digits, HEX2..HEX7
);
```

### 1. One-second timebase

`CLOCK_50` runs at 50 MHz. A 26-bit counter counts up to 49,999,999, which is exactly one second. Each time it gets there, the seconds register goes up by one. Seconds roll into minutes at 60, minutes into hours at 60, and hours back to 0 at 24.

The main loop checks things in a fixed order:

1. **Reset**: zero everything.
2. **Adjust mode**: pause timekeeping and apply minute/hour button pulses.
3. **Normal**: tick.

```verilog
// Internal Trackers
reg [25:0] counter = 0;
reg [7:0] seconds = 0;
reg [7:0] minutes = 0;
reg [7:0] hours = 0;

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
    ...
```

### 2. Button edge detection

The DE2-115 keys are active-low, so they're inverted first. Each button then passes through two registers clocked at 50 MHz (`key_d1`, `key_d2`). `pulse = key_d1 & ~key_d2` is high for exactly one clock cycle on the rising edge of a press.

```verilog
wire reset       = ~KEY[0]; // Button 1 (Rightmost): Reset
wire adjust_mode = ~KEY[1]; // Button 2: Hold to Adjust
wire btn_min     = ~KEY[2]; // Button 3: Add Minute
wire btn_hr      = ~KEY[3]; // Button 4 (Leftmost): Add Hour

// Clean Edge Detection (Prevents holding the button from adding 100 hours instantly)
reg [1:0] key_d1 = 0, key_d2 = 0;
wire pulse_min = (key_d1[0] & ~key_d2[0]);   // detecting minute button
wire pulse_hr  = (key_d1[1] & ~key_d2[1]);   // detecting hours button

always @(posedge CLOCK_50) begin
    key_d1 <= {btn_hr, btn_min};
    key_d2 <= key_d1;
end
```

### 3. Binary → BCD: the `bin_to_bcd` task (double dabble)

Each 8-bit time value is loaded into a 16-bit shift register and shifted left 8 times. Before each shift, any BCD column (ones in bits 11:8, tens in bits 15:12) that is 5 or more has 3 added to it. That forces the carry into the next decimal digit. After 8 shifts, the upper byte holds the two BCD digits.

```verilog
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
```

The task is called three times per clock cycle, once for each time value:

```verilog
//----------- Binary to BCD conversion calls
bin_to_bcd(seconds, sec_bcd);
bin_to_bcd(minutes, min_bcd);
bin_to_bcd(hours, hr_bcd);
```

| Worked example (27) | 35, before shifting | 35, after shifting |
|---|---|---|
| ![Double dabble](docs/double-dabble-worked-example.png) | ![Before](docs/bcd-35-before.png) | ![After](docs/bcd-35-after.png) |

### 4. BCD → 7-segment: the `seg_display` task

A `case` statement maps each 4-bit digit to its 7-segment pattern. The patterns are active-low for common-anode displays, so `0` lights a segment.

```verilog
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
```

Each BCD byte is split into its ones (`[3:0]`) and tens (`[7:4]`) digits. Each digit goes to its own display:

```verilog
//----------- count value to display value conversion
seg_display(sec_bcd[3:0], Display[6:0]);
seg_display(sec_bcd[7:4], Display[13:7]);
seg_display(min_bcd[3:0], Display[20:14]);
seg_display(min_bcd[7:4], Display[27:21]);
seg_display(hr_bcd[3:0],  Display[34:28]);
seg_display(hr_bcd[7:4],  Display[41:35]);
```

The 42-bit `Display` output is split into six 7-bit fields:

| Display bits | Digit | Board display |
|---|---|---|
| `[6:0]` | seconds ones | HEX2 |
| `[13:7]` | seconds tens | HEX3 |
| `[20:14]` | minutes ones | HEX4 |
| `[27:21]` | minutes tens | HEX5 |
| `[34:28]` | hours ones | HEX6 |
| `[41:35]` | hours tens | HEX7 |

## Files

| File | Contents |
|---|---|
| [`Clock50New.v`](Clock50New.v) | The whole design: timebase, counters, button edge detection, and the `bin_to_bcd` and `seg_display` tasks |
| `Clock50New.qpf`, `Clock50New.qsf` | Quartus project for the Cyclone IV E `EP4CE115F29C7`, with all the DE2-115 pin assignments |
| `docs/` | BCD conversion diagrams and the project Gantt chart |

## Build it

1. Open `Clock50New.qpf` in Quartus II 13.0 SP1 or later.
2. Run **Processing → Start Compilation**.
3. Connect the DE2-115 with the USB-Blaster and program it with **Tools → Programmer**.

## Planning

![Gantt chart](docs/gantt-chart.png)

## What I learned

- Building an accurate timebase by dividing a 50 MHz clock in hardware.
- Using Verilog tasks to avoid repeating code, and implementing the double dabble algorithm.
- Handling active-low inputs and outputs on a real board.
- Why raw push buttons need edge detection at 50 MHz, and building it with a two-register synchroniser.
- Splitting a design into clear stages (timebase → counters → BCD → display) so it's easy to debug.
