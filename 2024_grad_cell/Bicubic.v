`include "DW_div.v"
module Bicubic (
input CLK,
input RST,
input [6:0] V0,
input [6:0] H0,
input [4:0] SW,
input [4:0] SH,
input [5:0] TW,
input [5:0] TH,
output DONE);

localparam FIND_P0 = 0,
            LOAD_IMG = 1,
            INTERP = 2,
            STORE = 3,
            FINISH = 7;

wire [7:0] img_data, sram_dataout;
reg [7:0] sram_datain;
wire img_cen, sram_cen, sram_wen;

reg [13:0] img_addr, sram_addr;

reg [3:0] cur_state, next_state;

reg [5:0] counter;
reg [6:0]  counter_x, counter_y;
reg signed [13:0] remainder;

reg [7:0] p_values [3:0];
reg signed [14:0] a,b,c,d;  // 1:s, 10:int, 4:frag
reg signed [34:0] ax3;
reg signed [34:0] bx2;
reg signed [34:0] cx;
reg [34:0] tmp_ans;

reg [6:0] p0_base;


reg [60:0] div_a;
reg [60:0] div_b, div_remainder;
wire [60:0] div_a_wire, div_quot_wire;
wire [60:0] div_b_wire, div_remainder_wire;
wire div_by_0, div_by_0_y;



ImgROM u_ImgROM (.Q(img_data), .CLK(~CLK), .CEN(img_cen), .A(img_addr));
ResultSRAM u_ResultSRAM (.Q(sram_dataout), .CLK(~CLK), .CEN(sram_cen), .WEN(sram_wen), .A(sram_addr), .D(sram_datain));

DW_div #(61,61,0,1) u_div (.a(div_a_wire), .b(div_b_wire), .quotient(div_quot_wire), .remainder(div_remainder_wire), .divide_by_0(div_by_0));

wire [10:0] div_a_wire_y, div_remainder_wire_y;
wire [10:0] div_b_wire_y, div_quot_wire_y;


DW_div #(11,11,0,1) u_div1 (.a(div_a_wire_y), .b(div_b_wire_y), .quotient(div_quot_wire_y), .remainder(div_remainder_wire_y), .divide_by_0(div_by_0_y));
assign div_a_wire_y = counter_y * (TH-1);
assign div_b_wire_y = SH-1;

// assign div_a = (cur_state == INTERP)? {SW*counter_x, 20'd0} : 0;
// assign div_b = (cur_state == INTERP)? TW : 0;
assign div_a_wire = (cur_state == INTERP)? {div_a, 20'd0} : 0;
assign div_b_wire = (cur_state == INTERP)? div_b : 0;

assign img_cen = ~(cur_state == LOAD_IMG);
assign sram_cen = ~(cur_state == STORE);
assign sram_wen = ~(cur_state == STORE);
assign DONE = (cur_state == FINISH);

always @(*) begin
    case (cur_state)
        FIND_P0:begin
            if((counter_x == 0 || counter_x == TW - 1)&&(counter_y == 0 || counter_y == SH - 1))begin
                next_state = LOAD_IMG;
            end
            else begin
                if(remainder < 0) next_state = LOAD_IMG;
                else next_state = FIND_P0;
            end
            
        end 
        LOAD_IMG:begin
            if(((counter_x == 0 || counter_x == TW - 1)&&(counter_y == 0 || counter_y == SH - 1)))begin
                next_state = STORE;
            end
            else if(counter == 6'd3)begin
                next_state = INTERP;
            end
            else begin
                next_state = LOAD_IMG;
            end
        end
        INTERP:begin
            if(counter == 6'd6)begin
                next_state = STORE;
            end
            else begin
                next_state = INTERP;
            end 
        end
        STORE:begin
            if(counter_x == TW - 1 && counter_y == SH - 1) next_state = FINISH;
            else next_state = FIND_P0;
        end
        default:begin
            next_state = FIND_P0;
        end
    endcase
end

always @(posedge CLK, posedge RST) begin
    if(RST)begin
        remainder <= 7'd0;
        img_addr <= 14'd0;
        p_values[0] <= 8'd0;
        p_values[1] <= 8'd0;
        p_values[2] <= 8'd0;
        p_values[3] <= 8'd0;
        a <= 15'd0;
        b <= 15'd0;
        c <= 15'd0;
        d <= 15'd0;
        tmp_ans <= 0;
        ax3 <= 0;
        bx2 <= 0;
        cx <= 0;
        sram_datain <= 8'd0;

        div_a <= 0;
        div_b <= 0;
        sram_addr <= 0;
    end
    else begin
        if(cur_state == FIND_P0)begin
            if(counter_x == 0 && counter_y == 0)begin
                img_addr <= (V0*100) + H0;
            end
            else if(counter_x == 0 && counter_y == SH-1)begin
                img_addr <= ((V0+counter_y)*100) + H0;
            end
            else if(counter_x == TW-1 && (counter_y == SH-1 || counter_y == 0))begin
                img_addr <= ((V0+counter_y)*100) + H0 + (SW-1);
            end
            else if(counter_x == TW - 1)begin
                img_addr <= ((V0+counter_y)*100) + H0 + SW - 2;
            end
            else if(remainder <= 0)begin
                img_addr <= ((V0+counter_y)*100) + (H0) + (counter-2);
                p0_base <= counter-1;
            end

            if(counter == 7'd0)begin
                remainder <= (SW-1) * counter_x - (TW-1); //
            end
            else begin
                remainder <= remainder - (TW-1);
            end
        end
        else if(cur_state == LOAD_IMG)begin
            if(counter_x == 0 && counter_y == 0)begin
                sram_datain <= img_data;
            end
            else if((counter_x == 0 || counter_x == TW - 1)&&(counter_y == 0 || counter_y == SH - 1))begin
                p_values[0] <= img_data;
                sram_datain <= img_data;

                if(counter_y == SH - 1)begin
                    sram_addr <= ((TH-1)*(TW)) + counter_x;
                end
                else begin
                    sram_addr <= (counter_y*(TW)) + counter_x;
                end
            end
            else begin
                img_addr <= img_addr + 1;
                p_values[counter] <= img_data;
            end
        end
        else if(cur_state == INTERP)begin
            if(counter == 6'd0)begin
                a <= $signed((-1)*$signed({1'b0, p_values[0], 4'b0})>>1) + $signed((3*{1'b0, p_values[1], 4'b0})>>1) - $signed((3*{1'b0, p_values[2], 4'b0})>>1) + $signed(({1'b0, p_values[3], 4'b0})>>1);
                b <= $signed({1'b0, p_values[0], 4'b0}) - $signed((5*{1'b0, p_values[1], 4'b0})>>1) + $signed((2*{1'b0, p_values[2], 4'b0})) - $signed(({p_values[3], 4'b0})>>1);
                c <= $signed((-1)*$signed({1'b0, p_values[0], 4'b0})>>1) + $signed(({1'b0, p_values[2], 4'b0})>>1);
                d <= $signed({1'b0,p_values[1], 4'b0});
            end
            else if(counter == 6'd1)begin
                div_a <= (((SW-1)*counter_x) - (p0_base*(TW-1)))*(((SW-1)*counter_x) - (p0_base*(TW-1)))*(((SW-1)*counter_x) - (p0_base*(TW-1)));
                div_b <= (TW-1) * (TW-1) * (TW-1);
            end
            else if(counter == 6'd2)begin
                ax3 <= a * $signed({1'b0,div_quot_wire[19:0]});

                div_a <= (((SW-1)*counter_x) - (p0_base*(TW-1)))*(((SW-1)*counter_x) - (p0_base*(TW-1)));
                div_b <= (TW-1) * (TW-1);
            end
            else if(counter == 6'd3)begin
                bx2 <= b * $signed({1'b0,div_quot_wire[19:0]});

                div_a <= (((SW-1)*counter_x) - (p0_base*(TW-1)));
                div_b <= (TW-1);
            end
            else if(counter == 6'd4)begin
                cx <= c * $signed({1'b0,div_quot_wire[19:0]});
            end
            else if(counter == 6'd5)begin
                tmp_ans <= $signed(ax3) + $signed(bx2) + $signed(cx) + $signed({d, 20'd0});
            end
            else if(counter == 6'd6)begin
                sram_datain <= (tmp_ans[23]) ? tmp_ans[31:24] + 1: tmp_ans[31:24];

                
                if(counter_y == SH - 1)begin
                    sram_addr <= ((TH-1)*(TW)) + counter_x;
                end
                else begin
                    sram_addr <= (div_quot_wire_y*(TW)) + counter_x;
                end
            end
        end
        else if(cur_state == STORE)begin
            remainder <= 0;
        end
    end
end

always @(posedge CLK, posedge RST) begin
    if(RST)begin
        counter <= 6'd0;
        counter_x <= 7'd0;
        counter_y <= 7'd0;
    end 
    else begin
        if(cur_state == FIND_P0)begin
            if((counter_x == 0 || counter_x == TW - 1)&&(counter_y == 0 || counter_y == TH - 1))begin
                counter <= 6'd0;
            end
            else if(remainder >= 0) begin
                counter <= counter + 6'd1;
            end
            else begin
                counter <= 6'd0;
            end
        end
        else if(cur_state == LOAD_IMG)begin
            if((counter_x == 0 || counter_x == TW - 1)&&(counter_y == 0 || counter_y == TH - 1))begin
                counter <= 6'd0;
            end
            else begin
                if(counter == 6'd3)begin
                    counter <= 6'd0;
                end
                else begin
                    counter <= counter + 1;
                end
            end
        end
        else if(cur_state == INTERP)begin
            if(counter == 6'd6)begin
                counter <= 6'd0;
            end
            else begin
                counter <= counter + 1;
            end
        end
        else if(cur_state == STORE)begin
            counter <= 0;
            if(counter_x == TW-1 && counter_y == TH-1)begin
                counter_x <= 0;
                counter_y <= 0;
            end
            else if(counter_x == (TW-1))begin
                counter_x <= 0;
                counter_y <= counter_y + 1;
            end
            else 
                counter_x <= counter_x + 1;
        end
    end
end

always @(posedge CLK, posedge RST) begin
    if(RST)begin
        cur_state <= FIND_P0;
    end
    else begin
        cur_state <= next_state;
    end
end

endmodule


