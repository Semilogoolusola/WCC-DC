function ToA_est_signal = generate_ToA_est_signal(symbol_length, cp_length, bitspersymbol, forsender)
%GENERATE_TOA_EST_SIGNAL Summary of this function goes here
%   Detailed explanation goes here
if forsender
    ToA_est_bits = generate_ToA_est_bits(2*symbol_length*bitspersymbol);
else
    ToA_est_bits = generate_ToA_est_bits(symbol_length*bitspersymbol);
end
am_bits = length(ToA_est_bits);
am_symbols = am_bits/bitspersymbol;
am_blocks = am_symbols/symbol_length;
if cp_length ~= 0
    am_bits_padded = am_bits + cp_length*am_blocks*bitspersymbol;
    am_symbols_padded = am_symbols + cp_length*am_blocks;
else
    am_bits_padded = am_bits;
    am_symbols_padded = am_symbols;
end
Symbols = QAM_modulation(ToA_est_bits, bitspersymbol);
symbols = zeros(1,am_symbols);
for i = 1:am_blocks
    begin_index = (i-1)*symbol_length + 1;
    end_index = i*symbol_length;
    % OFDM: IFFT
    symbols(begin_index:end_index) = ifft(Symbols(begin_index:end_index));
    %symbols(begin_index) = 0;
end
%add cp_padding
symbols_padded = zeros(1, am_symbols_padded);
if cp_length == 0
    symbols_padded = symbols;
else
    if forsender == 0
        for i = 1:am_blocks
             begin_index = (i-1)*symbol_length + 1;
             end_index = i*symbol_length;   
             symbols_padded_start = (i-1)*(symbol_length + cp_length) + 1;
             symbols_padded_end = (i)*(symbol_length + cp_length);
             symbols_padded(symbols_padded_start:symbols_padded_start + cp_length - 1) = symbols(end_index-cp_length + 1: end_index);
             symbols_padded(symbols_padded_start + cp_length : symbols_padded_end) = symbols(begin_index: end_index);
             %symbols_padded(symbols_padded_start) = 0;
        end
    else
        %different for this prefix:
        symbols_padded(1:am_blocks*cp_length) = symbols(end-am_blocks*cp_length+1:end);
        symbols_padded(am_blocks*cp_length+1:end) = symbols;
    end
end
ToA_est_signal = symbols_padded;
end

