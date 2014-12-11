module musicfail(
	//////////// CLOCK //////////
	CLOCK_125_p,
	CLOCK_50_B5B,
	CLOCK_50_B6A,
	CLOCK_50_B7A,
	CLOCK_50_B8A,

	//////////// Audio //////////
	AUD_ADCDAT,
	AUD_ADCLRCK,
	AUD_BCLK,
	AUD_DACDAT,
	AUD_DACLRCK,
	AUD_XCK,

	//////////// I2C for Audio/HDMI-TX/Si5338/HSMC //////////
	I2C_SCL,
	I2C_SDA,
	
	LEDG,
	LEDR,
	
	//////////// SEG7 //////////
	HEX0,
	HEX1,
	HEX2,
	HEX3 
);

//=======================================================
//  PORT declarations
//=======================================================

	//////////// CLOCK //////////
	input CLOCK_125_p;
	input CLOCK_50_B5B;
	input CLOCK_50_B6A;
	input CLOCK_50_B7A;
	input CLOCK_50_B8A;

	//////////// Audio //////////
	input AUD_ADCDAT;
	inout AUD_ADCLRCK;
	inout AUD_BCLK;
	output AUD_DACDAT;
	inout AUD_DACLRCK;
	output AUD_XCK;

	//////////// I2C for Audio/HDMI-TX/Si5338/HSMC //////////
	output I2C_SCL;
	inout I2C_SDA;
	
	output [7:0] LEDG;
	output [9:0] LEDR;
	
	//////////// SEG7 //////////
	output		     [6:0]		HEX0;
	output		     [6:0]		HEX1;
	output		     [6:0]		HEX2;
	output		     [6:0]		HEX3;
	
//=======================================================
//  REG/WIRE declarations
//=======================================================

	reg mclk;
	reg [24:0] mclk_counter;
	reg bclk;
	reg bclk_counter;
	reg noteclk;
	reg signed [28:0] noteclk_counter;

	wire [23:0] gen_sample;	// output your audio samples to this wire
	reg signed [23:0] real_sample;

	reg [23:0] sample;
	reg [4:0] sample_ctr;

	reg pblrc;
	reg pbdat;

	reg [1:0] state;
	
	reg [9:0] quarter_note;
	reg [9:0] new_quarter;
	wire [39:0] ticks_per_sixteenth;
	wire [39:0] grace_length;
	wire [39:0] ticks_of_note;
	reg [39:0] sixteenth_tick_counter;
	reg [39:0] sixteenth_tick_counter_next;
	
	//reg signed [20:0] freqs [0:7] [0:15];
	reg [13:0] freqs [0:11];
	wire signed [20:0] freq;
	
	reg [9:0] next_note_address; // Calculated address.
	reg [9:0] note_address; // Registered address
	wire [15:0] next_note;
	wire next_note_inst;
	reg note_inst;
	reg new_note;
	reg halt;
	reg halted;
	wire unsigned [4:0] next_note_duration;
	reg unsigned [5:0] note_duration;
	wire unsigned [2:0] next_note_volume;
	wire unsigned [2:0] next_note_octave;
	reg unsigned [2:0] note_octave;
	wire unsigned [3:0] next_note_pitch;
	reg unsigned [3:0] note_pitch;

	wire unsigned [3:0] opcode;
	wire unsigned [7:0] imm8;
	wire unsigned [9:0] imm10;
	reg unsigned [9:0] new_val;
	reg unsigned [9:0] pc_reg [0:7];
	reg unsigned [8:0] imm_reg [0:7];
	wire unsigned [2:0] reg_num;
	reg [2:0] grace_count;

	reg execute;
	reg execute_next;
	reg update_imm_reg;
	reg update_pc_reg;
	
//=======================================================
//  Second voice declarations
//=======================================================


	reg second_noteclk;
	reg signed [28:0] second_noteclk_counter;

	reg signed [23:0] second_real_sample;

	reg [9:0] second_quarter_note;
	reg [9:0] second_new_quarter;
	wire [39:0] second_ticks_per_sixteenth;
	wire [39:0] second_grace_length;
	wire [39:0] second_ticks_of_note;
	reg [39:0] second_sixteenth_tick_counter;
	reg [39:0] second_sixteenth_tick_counter_next;
	
	wire signed [20:0] second_freq;
	
	reg [9:0] second_next_note_address; // Calculated address.
	reg [9:0] second_note_address; // Registered address
	wire [15:0] second_next_note;
	wire second_next_note_inst;
	reg second_note_inst;
	reg second_new_note;
	reg second_halt;
	reg second_halted;
	wire unsigned [4:0] second_next_note_duration;
	reg unsigned [5:0] second_note_duration;
	wire unsigned [2:0] second_next_note_volume;
	wire unsigned [2:0] second_next_note_octave;
	reg unsigned [2:0] second_note_octave;
	wire unsigned [3:0] second_next_note_pitch;
	reg unsigned [3:0] second_note_pitch;

	wire unsigned [3:0] second_opcode;
	wire unsigned [7:0] second_imm8;
	wire unsigned [9:0] second_imm10;
	reg unsigned [9:0] second_new_val;
	reg unsigned [9:0] second_pc_reg [0:7];
	reg unsigned [8:0] second_imm_reg [0:7];
	wire unsigned [2:0] second_reg_num;
	reg [2:0] second_grace_count;

	reg second_execute;
	reg second_execute_next;
	reg second_update_imm_reg;
	reg second_update_pc_reg;

//=======================================================
//  Defines
//=======================================================
	
	`define stimm 3'b000
	`define stpc  3'b001
	`define brnz  3'b010
	`define hlt   3'b011
	`define sq    3'b100

//=======================================================

	    // The RAM
   twovoicemem musical(
      .address_a(next_note_address),          // address is registered
      .clock(CLOCK_50_B5B),
      .q_a(next_note),
		.address_b(second_next_note_address),
		.q_b(second_next_note));

	// Clock dividers
	initial begin
		mclk <= 0;
		mclk_counter <= 0;
		bclk <= 0;
		bclk_counter <= 0;
		noteclk <= 0;
		noteclk_counter <= 0;
		real_sample <= 24'd200000;
		execute <= 1;
		grace_count <= 0;
		halted <= 0;
		
		//Change for different speed. Quarter notes per minute.
		quarter_note <= 10'd160;
		sixteenth_tick_counter <= 0;
		note_duration <= 0;
		
		//Begin at the beginning
		next_note_address <= -1;
		
		second_real_sample <= 24'd200000;
		second_execute <= 1;
		second_grace_count <= 0;
		second_halted <= 0;
		
		//Change for different speed. Quarter notes per minute.
		second_quarter_note <= 10'd160;
		second_sixteenth_tick_counter <= 0;
		second_note_duration <= 0;
		
		//Begin at the beginning
		second_next_note_address <= 0;
		
		//Frequency table for octave 0. All frequencies multiplied by 1000. Source: www.phy.mtu.edu/~suits/notefreqs.html
		freqs[0] <= 1635;
		freqs[1] <= 1732;
		freqs[2] <= 1835;
		freqs[3] <= 1945;
		freqs[4] <= 2060;
		freqs[5] <= 2183;
		freqs[6] <= 2312;
		freqs[7] <= 2450;
		freqs[8] <= 2596;
		freqs[9] <= 2750;
		freqs[10] <= 2914;
		freqs[11] <= 3087;
		
	end
	
	assign gen_sample = real_sample + second_real_sample;
	assign ticks_per_sixteenth = (750000000/quarter_note);
	assign grace_length = (ticks_per_sixteenth >> 2);
	assign freq = (1250000000)/(freqs[note_pitch]<<note_octave);
	
	assign second_ticks_per_sixteenth = (750000000/second_quarter_note);
	assign second_grace_length = (second_ticks_per_sixteenth >> 2);
	assign second_freq = (1250000000)/(freqs[second_note_pitch]<<second_note_octave);
	
	assign LEDG[0] = second_noteclk;
	assign LEDG[1] = second_next_note_inst;
	assign LEDG[2] = second_execute;
	assign LEDR[9:0] = second_note_address;
	
	//Decode:
	assign next_note_inst = next_note[15];
	assign next_note_duration = next_note[14:10];
	assign next_note_volume = next_note[9:7];
	assign next_note_octave = next_note[6:4];
	assign next_note_pitch = next_note[3:0];

	// Decode Inst:
	assign opcode = next_note[14:12];
	assign imm8 = next_note[7:0];
	assign imm10 = next_note[9:0];
	assign reg_num = next_note[11:9];
	
	assign ticks_of_note = (note_duration ? (ticks_per_sixteenth * note_duration) : (grace_length * grace_count));
	
	// VOICE 2!
	
	//Decode:
	assign second_next_note_inst = second_next_note[15];
	assign second_next_note_duration = second_next_note[14:10];
	assign second_next_note_volume = second_next_note[9:7];
	assign second_next_note_octave = second_next_note[6:4];
	assign second_next_note_pitch = second_next_note[3:0];

	// Decode Inst:
	assign second_opcode = second_next_note[14:12];
	assign second_imm8 = second_next_note[7:0];
	assign second_imm10 = second_next_note[9:0];
	assign second_reg_num = second_next_note[11:9];
	
	assign second_ticks_of_note = (second_note_duration ? (second_ticks_per_sixteenth * second_note_duration) : (second_grace_length * second_grace_count));

	always @(posedge CLOCK_50_B5B) begin
		quarter_note <= new_quarter;
		halted <= halt;
		execute <= execute_next;
		note_address <= next_note_address;
		sixteenth_tick_counter <= sixteenth_tick_counter_next;
		if(update_imm_reg) begin
			imm_reg[reg_num] <= new_val;
		end
		if(update_pc_reg) begin
			pc_reg[reg_num] <= new_val;
		end
		if(new_note) begin 
			// Time to change notes. Reset the counter.
			note_pitch <= next_note_pitch;
			note_octave <= next_note_octave;
			note_duration <= next_note_duration;
			grace_count <= (next_note_duration ? 0 : grace_count + 1);
			real_sample <= 20000 * next_note_volume * next_note_volume;
		end else begin
			if(noteclk_counter >= freq) begin
				if(noteclk == 0) real_sample <= ~real_sample;
				noteclk <= !noteclk;
				noteclk_counter <= 0;
			end else begin
				noteclk_counter <= noteclk_counter + 1;
			end
		end
	end

	// VOICE 2!!!!!!!!!!!!!!!!
	always @(posedge CLOCK_50_B5B) begin
		second_quarter_note <= second_new_quarter;
		second_halted <= second_halt;
		second_execute <= second_execute_next;
		second_note_address <= second_next_note_address;
		second_sixteenth_tick_counter <= second_sixteenth_tick_counter_next;
		if(second_update_imm_reg) begin
			second_imm_reg[second_reg_num] <= second_new_val;
		end
		if(second_update_pc_reg) begin
			second_pc_reg[second_reg_num] <= second_new_val;
		end
		if(second_new_note) begin 
			// Time to change notes. Reset the counter.
			second_note_pitch <= second_next_note_pitch;
			second_note_octave <= second_next_note_octave;
			second_note_duration <= second_next_note_duration;
			second_grace_count <= (second_next_note_duration ? 0 : second_grace_count + 1);
			second_real_sample <= 20000 * second_next_note_volume * second_next_note_volume;
		end else begin
			if(second_noteclk_counter >= second_freq) begin
				if(second_noteclk == 0) second_real_sample <= ~second_real_sample;
				second_noteclk <= !second_noteclk;
				second_noteclk_counter <= 0;
			end else begin
				second_noteclk_counter <= second_noteclk_counter + 1;
			end
		end
	end

	// VOICE 2!!!!!!!!!!!!!!!!
	always @(*) begin
		second_new_quarter = second_quarter_note;
		second_update_imm_reg = 0;
		second_update_pc_reg = 0;
		if(second_sixteenth_tick_counter >= second_ticks_of_note) begin
			// Time to change notes. Reset the counter.
			second_new_note = 1; // Flag.
			second_next_note_address = second_note_address - 1 + second_halted;
			second_halt = 0;
			second_sixteenth_tick_counter_next = second_note_duration ? 0 : (second_sixteenth_tick_counter + 1);
			second_execute_next = 1;
      end else begin
			second_new_note = 0; // Flag.
         second_sixteenth_tick_counter_next = second_sixteenth_tick_counter + 1;
			if(second_next_note_inst && second_execute) begin
				second_execute_next = 0;
				second_next_note_address = second_note_address - 1;
				second_halt = 0;
				case(second_opcode)
					`hlt : begin
						second_next_note_address = second_note_address;
						second_halt = 1;
					end
					`sq : begin
						second_new_quarter = second_imm10;
					end
					`brnz : begin
						if(second_imm_reg[second_reg_num]) begin
							second_next_note_address = second_pc_reg[second_reg_num];
							second_update_imm_reg = 1;
							second_new_val = second_imm_reg[second_reg_num] - 1;
						end
					end
					`stimm : begin
						second_update_imm_reg = 1;
						second_new_val = second_imm8;
					end
					`stpc : begin
						second_update_pc_reg = 1;
						second_new_val = second_note_address - 1;
					end
					default : begin
					end
				endcase
			end else begin
				second_execute_next = 1;
				second_next_note_address = second_note_address;
			end // end inst
		end // end stuff
	end // calculations
	
	always @(*) begin
		new_quarter = quarter_note;
		update_imm_reg = 0;
		update_pc_reg = 0;
		if(sixteenth_tick_counter >= ticks_of_note) begin
			// Time to change notes. Reset the counter.
			new_note = 1; // Flag.
			next_note_address = note_address + 1 - halted;
			halt = 0;
			sixteenth_tick_counter_next = note_duration ? 0 : (sixteenth_tick_counter + 1);
			execute_next = 1;
      end else begin
			new_note = 0; // Flag.
         sixteenth_tick_counter_next = sixteenth_tick_counter + 1;
			if(next_note_inst && execute) begin
				execute_next = 0;
				next_note_address = note_address + 1;
				halt = 0;
				case(opcode)
					`hlt : begin
						next_note_address = note_address;
						halt = 1;
					end
					`sq : begin
						new_quarter = imm10;
					end
					`brnz : begin
						if(imm_reg[reg_num]) begin
							next_note_address = pc_reg[reg_num];
							update_imm_reg = 1;
							new_val = imm_reg[reg_num] - 1;
						end
					end
					`stimm : begin
						update_imm_reg = 1;
						new_val = imm8;
					end
					`stpc : begin
						update_pc_reg = 1;
						new_val = note_address + 1;
					end
					default : begin
					end
				endcase
			end else begin
				execute_next = 1;
				next_note_address = note_address;
			end // end inst
		end // end stuff
	end // calculations
	
	always @(posedge CLOCK_50_B5B) begin
		if (mclk_counter == 1) begin
			mclk <= !mclk;
			mclk_counter <= 0;
		end else begin
			mclk_counter <= mclk_counter + 1;
		end
	end

	always @(posedge mclk) begin
		if (bclk_counter == 1) begin
			bclk <= !bclk;
			bclk_counter <= 0;
		end else begin
			bclk_counter <= bclk_counter + 1;
		end
	end

	// state machine
	initial begin
		state <= 0;
		pblrc <= 1;
		pbdat <= 0;
	end

	always @(negedge bclk) begin
		if (state == 0) begin
			sample <= gen_sample;
			pblrc <= 0;
			pbdat <= sample[23];
			sample_ctr <= 23;
			state <= 1;
		end else if (state == 1) begin
			pblrc <= 0;
			pbdat <= sample[sample_ctr];

			if (sample_ctr == 0) begin
				sample_ctr <= 23;
				state <= 2;
			end else begin
				sample_ctr <= sample_ctr - 1;
				state <= 1;
			end
		end else if (state == 2) begin
			pblrc <= 1;
			pbdat <= sample[sample_ctr];

			if (sample_ctr == 0) begin
				sample_ctr <= 23;
				state <= 3;
			end else begin
				sample_ctr <= sample_ctr - 1;
				state <= 2;
			end
		end else begin
			sample <= gen_sample;
			pblrc <= 1;
			pbdat <= 0;
			sample_ctr <= 23;
			state <= 1;
		end
	end

	// audio
	assign AUD_XCK = mclk;
	assign AUD_BCLK = bclk;
	assign AUD_DACDAT = pbdat;
	assign AUD_DACLRCK = pblrc;
		 
		 
	hexDisplay hexDisp0 (second_next_note[3:0], HEX0);
	hexDisplay hexDisp1 (second_next_note[7:4], HEX1);
	hexDisplay hexDisp2 (second_next_note[11:8], HEX2);
	hexDisplay hexDisp3 (second_next_note[15:12], HEX3);
	
endmodule

module hexDisplay (in, out);
	input [3:0] in;
   output [6:0] out;
	reg [6:0] x;
	assign out = x;

	always @ (*) begin
		case(in)
			4'd0 : x = 7'b1000000;
			4'd1 : x = 7'b1111001;
			4'd2 : x = 7'b0100100;
			4'd3 : x = 7'b0110000;
			4'd4 : x = 7'b0011001;
			4'd5 : x = 7'b0010010;
			4'd6 : x = 7'b0000010;
			4'd7 : x = 7'b1111000;
			4'd8 : x = 7'b0000000;
			4'd9 : x = 7'b0011000;
			4'd10 : x = 7'b0001000;
			4'd11 : x = 7'b0000011;
			4'd12 : x = 7'b0100111;
			4'd13 : x = 7'b0100001;
			4'd14 : x = 7'b0000110;
			4'd15 : x = 7'b0001110;
			default : x = 7'b01111111;
		endcase
	end
	
endmodule
