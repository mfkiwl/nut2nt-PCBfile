
`default_nettype none
module toplevel(

	input wire					CLK_NT_P,   // input clock &clock for input bus 53Mhz
	input wire					CLK_NT_N,
	input wire					INT_CTL,

	// input bus signals
	//input wire					IF1_MAGN,
	//input wire					IF1_SIGN,
	//input wire					IF2_MAGN,
	//input wire					IF2_SIGN,
	//input wire					IF3_MAGN,
	//input wire					IF3_SIGN,
	//input wire					IF4_MAGN,
	//input wire					IF4_SIGN,
	
	input wire					[7:0]IF_DATA,
	
	input wire					PPS,
	
	output  wire					SD_FPGA1,	// leds
	output  wire					SD_FPGA2,			

	input  wire					GPIO23,		// 
	output reg					GPIO25,		// FIFO_RDY
	input  wire					GPIO26,		// FX3_READY	
	input  wire					GPIO27,		// START USB SYSTEM

	output  wire [1:0]			A,
	output  wire [15:0]			DQ,			
	output	wire [7:0]			Test_out,
	
	output  wire					SLCSn,		
	output  wire					SLWRn,		
	output  wire					SLOEn,		
	output  wire					SLRDn,
	
	input   wire					FLAGA,		//GPIO 21
	input   wire					FLAGB,		//GPIO 22
	
	input  wire					PKTENDn,
	output  wire					RCVEN,
	input  wire					PCLK			// Cypress work clock 100Mhz	
	
);

	localparam DW = 16;

	wire 						clk;
	wire 						clk_pll;
	wire						clk_pll_div2;
	wire						pll_lock;
	wire [7:0]					wdtin;
	wire						grst;
		
	wire [15:0]				dt_from_fifo;
	wire							wfifo_empty;
	wire							wfifo_aempty;
	wire							wfifo_full;
	wire							wfifo_rd;
	wire							wfifo_wr;
	//wire							slwr;

	wire [DW-1:0]			wfdatao;
	wire [DW-1: 0]			test_data;
	wire							tg_on;			
	//wire [DW-1:0]			wfdatai;

	// ---- fifo signals ----
	wire [7:0] data_bus;
	reg [7:0] data_in_reg;
	wire [7:0]  data_fifo_out;
	wire [15:0] fifo_data;
	reg [15:0] fifo_data_reg;
	wire fifo_empty;
	wire fifo_full;
	wire alm_empty;
	wire rp_reset;
	wire rd_ena;
	wire reset;
	wire wr_ena;

	wire fifo_pre_ready;
	wire [7:0] fifo_pre_qdata;
	reg fifo_pre_rd;
	reg [7:0]data_box;
	reg [7:0]data_box2;
	wire [7:0] data_box_w;
	
	
	parameter F_ZERO = 3'b000;
	parameter F_RDY = 3'b001;
	parameter F_WRT = 3'b010;
	parameter F_ENDPCKG = 3'b011;
	parameter F_WRT_N1 = 3'b100;
	parameter F_WRT_N2 = 3'b101;
	parameter F_WRT_N3 = 3'b110;
	parameter F_WRT_LST = 3'b111;
	
	reg [2:0] state = 'b001;
	
	reg [31:0] packet_cnt = 32'h00000001;
	
	reg [9:0]data_cnt = 10'h000;
	reg data_cnt_en = 'b0;
	
	reg fifo_pre_start = 'b0;
	
	reg tt_led = 'b0;
	reg error_full = 'b0;
	
	wire [14:0] fifo_counter;
	wire fifo_s_ready;
	wire overload;
	reg	overload_manual;
	
	wire ff_full;
	wire ff_emty;
//	
//---------------------------------------------------------------------------------------------------------------------------------------------------------------------	
//
	ILVDS ilvds_I(.A(CLK_NT_P), .AN(CLK_NT_N), .Z(clk));


// --------- PLL --------- //

	PLL	main_PLL (
		.CLKI(clk),
		.CLKOP(clk_pll),
		.LOCK(pll_lock)
	);

	assign reset = !pll_lock;

	assign  RCVEN = 1;

	//reg oe;
	//always @(posedge clk_pll)
	//		oe <= pll_lock;

	assign A[0] = pll_lock;
	//assign SLWRn = !pll_lock;
	
	
	reg divider2;		
	always @(posedge clk)
		divider2 <= ~divider2;	
			

	reg [27:0] counter_1 = 28'h0000000;
	reg [7:0] counter_2 = 8'h00;
	reg WR_r = 1'b0;
	reg STRT = 1'b0;

	reg state_1 = 1'b0;

	reg [1:0]stat = 2'b00;
	
	assign SD_FPGA1 = fifo_full;			// ----- Led HL3
	assign SD_FPGA2 = dden;			// ----- Led HL4

 
// ----------------- Delay process start ------------------- O
	always @(posedge clk)
		begin

				// Start warming delay
				if (counter_1 < 28'h4C174E2) begin // 6516E80 - 2 sec / 53Mhz
					counter_1 = counter_1+1;
					STRT <= 0;
				end	else
					STRT <= 1;

		end

	//assign GPIO27 = STRT; // START USB SYSTEM
	always @(STRT, GPIO27)
		fifo_pre_start <= STRT & GPIO27; // START FIFO BUFFER (system ready & usb cypress ready)

// ----------------- Muxer data -------------------- O

	always @(negedge clk)
		begin

			// Test counter
			// uncomment line down and line connection to data_in_reg
			//if (fifo_pre_start)
			//	counter_2 <= counter_2 + 1;
			//	counter_2 <= 8'h00;
			

			//data_in_reg <= counter_2;
			//data_in_reg <= {IF4_SIGN, IF4_MAGN ,IF3_SIGN, IF3_MAGN, IF2_SIGN, IF2_MAGN, IF1_SIGN, IF1_MAGN};
			data_in_reg <= IF_DATA;
		end

	//assign data_in_reg = {IF4_SIGN, IF4_MAGN ,IF3_SIGN, IF3_MAGN, IF2_SIGN, IF2_MAGN, IF1_SIGN, IF1_MAGN};

// --------------- Fifo input buffer ----------------- O 

	fifo_8bit_buffer	fifo_8bit_buffer_inst  (
		.RPReset(reset), 
		.Reset(reset), 
		.Data (data_in_reg), 
		.AlmostFull(fifo_pre_ready),
		.WrClock(clk),
        .WrEn(fifo_pre_start),
		.Q(fifo_pre_qdata),
		.RdClock(clk_pll),
        .RdEn(fifo_pre_rd),
		.Full(ff_full),
		.Empty(ff_emty)
        
	);
	

// ------------ Data stream counter ------------- O

always @(posedge clk_pll)
      if (!data_cnt_en)
            data_cnt <= 10'h000;
      else        
            data_cnt <= data_cnt + 1'b1;

/*
  parameter COUNTER_WIDTH = <width>;

   reg [COUNTER_WIDTH-1:0] <reg_name> = {COUNTER_WIDTH{1'b0}};

   always @(posedge <clock>)
      if (!<reset>)
         <reg_name> <= {COUNTER_WIDTH{1'b0}};
      else if (<clock_enable>)
         <reg_name> <= <reg_name> + 1'b1;

*/
// ---------------- Commutator ------------------ O

	always @(posedge clk_pll)
		begin
		
		
		// reset condition
		if (!STRT) begin
			data_cnt_en <= 0;
			fifo_pre_rd <= 0;
			state <= F_RDY;
			WR_r <= 0;
			error_full <= 'b0;
			data_box <= 8'hA0;
			packet_cnt = 32'h00000001;
			overload_manual = 0;
		end
		else
		
			case (state)
			
				// zero condition
				F_ZERO	: begin
					data_cnt_en <= 0;
					fifo_pre_rd <= 0;
					WR_r <= 0;
					error_full <= 'b0;
					
					state <= F_RDY;
					
				end
				
				// waiting for fifo_pre be ready
				F_RDY	: begin
					if (fifo_pre_ready) begin
						//fifo_pre_rd <= 1;
						//data_cnt_en <= 1;
						// if fifo slave full, we miss the package
						
						if (!overload)
							WR_r = 1;
						else
							error_full <= 'b1;
						
						
						data_box <= packet_cnt[31:24];//packet_cnt[7:0];
						state <= F_WRT_N1;
					end
					
				end
				
				
				// Packages counter
				F_WRT_N1	:begin							
					data_box <= packet_cnt[23:16];//packet_cnt[15:8];
					state <= F_WRT_N2;
				end
				
				
				F_WRT_N2	:begin
					data_box <= packet_cnt[15:8];//packet_cnt[23:16];
					state <= F_WRT_N3;
					fifo_pre_rd <= 1;
				end
				
				F_WRT_N3	:begin
					data_box <= packet_cnt[7:0];//packet_cnt[31:24];
					state <= F_WRT;
					//fifo_pre_rd <= 1;
					data_cnt_en <= 1;
				end
				
				// read and write fifo
				F_WRT	:begin
					data_box <= fifo_pre_qdata;
					//data_box <= data_cnt[7:0];
					if (data_cnt == 10'h3FA) begin
						fifo_pre_rd <= 0;

						state <= F_WRT_LST;
					end
				end
				
				F_WRT_LST	:begin
					data_box <= fifo_pre_qdata;
					state <= F_ENDPCKG;
				end
				
				
				F_ENDPCKG	:begin
					data_box <= 8'h77;
					data_cnt_en <= 0;
					WR_r <= 0;
					error_full <= 'b0;
					packet_cnt <= packet_cnt + 1;
					state <= F_RDY;
				end
				
			endcase
			
		
		end


//	assign Test_out = data_box;
//	assign data_bus = data_in_reg;
//	assign data_box_w = data_box;

// ---------------- Slave fifo module ------------------- O

	


// ------  FIFO buffer  -------- O
	fifo_8bit_sl	fifo_8bit_sl_inst  (
		.RPReset(reset), 
		.Reset(reset), 
		.Data (data_box), 
		.AlmostFull(overload),
		.Full(fifo_full),
		.WrClock(clk_pll), 
        .WrEn(WR_r), // wr_ena
		.Q(data_fifo_out),
		.RdClock(PCLK),
        .RdEn(GPIO26), // rd_ena
		.AlmostEmpty(fifo_s_ready),
		.Empty(fifo_empty)
        
	);
	
	
	assign SLWRn = ! fifo_s_ready; // ??????????????????

	assign DQ = {8'h00, data_fifo_out};
	//assign DQ = {8'h00, data_box};



	// ------- delayer --------- O
	// delay signal 
	reg dden = 0;

	always @(posedge PCLK)
		begin
			dden <= GPIO26;
			GPIO25 <= dden;
		end

endmodule



